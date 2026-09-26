const { verifyToken } = require('../utils/jwt');
const { getPool } = require('../config/db');
const { error } = require('../utils/response');
const { ROLE_IDS } = require('../config/constants');

/**
 * Verifies the JWT access token in Authorization: Bearer <token>
 * Loads the user's roles and permissions and attaches them to req.user.
 */
async function verifyJWT(req, res, next) {
  try {
    const authHeader = req.headers.authorization || '';
    const token = authHeader.startsWith('Bearer ')
      ? authHeader.slice(7)
      : null;

    if (!token) {
      return error(
        res,
        'Authentication required',
        401,
        'UNAUTHORIZED'
      );
    }

    let decoded;

    try {
      decoded = verifyToken(token);
    } catch (e) {
      return error(
        res,
        'Invalid or expired token',
        401,
        'TOKEN_EXPIRED'
      );
    }

    const pool = await getPool();

    const result = await pool
      .request()
      .input('UserID', decoded.userId)
      .execute('sp_Users_GetByID');

    if (!result.recordset.length) {
      return error(
        res,
        'User not found',
        401,
        'USER_NOT_FOUND'
      );
    }

    const user = result.recordset[0];

    if (!user.IsActive) {
      return error(
        res,
        'Account is inactive. Contact administrator.',
        403,
        'ACCOUNT_INACTIVE'
      );
    }

    const perms = await pool
      .request()
      .input('UserID', user.UserID)
      .execute('sp_Users_GetPermissions');

    const roleName = String(user.RoleName || '').trim();

    req.user = {
      userId: user.UserID,
      username: user.Username,
      fullName: user.FullName,
      email: user.Email,
      roleId: user.RoleID,
      roleName,
      branchId: user.BranchID,
      photo: user.Photo,

      isSuperAdmin:
        user.RoleID === ROLE_IDS.SUPER_ADMIN ||
        roleName.toLowerCase() === 'super admin' ||
        roleName.toLowerCase() === 'superadmin',

      isOwner:
        roleName.toLowerCase() === 'owner',

      isAdmin:
        roleName.toLowerCase() === 'admin',

      permissions: perms.recordset.map((p) => p.Code)
    };

    next();
  } catch (err) {
    console.error('[auth] verifyJWT error:', err);

    return error(
      res,
      'Authentication failed',
      500,
      'AUTH_ERROR'
    );
  }
}

module.exports = { verifyJWT };
