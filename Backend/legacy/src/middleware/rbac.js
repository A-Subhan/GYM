const { error } = require('../utils/response');

/**
 * Checks whether the logged in user has the required permission.
 * Super Admin bypasses permission checks.
 */
function requirePermission(code) {
  return (req, res, next) => {
    if (!req.user) {
      return error(
        res,
        'Authentication required',
        401,
        'UNAUTHORIZED'
      );
    }

    if (req.user.isSuperAdmin) {
      return next();
    }

    if (
      !req.user.permissions ||
      !req.user.permissions.includes(code)
    ) {
      return error(
        res,
        `You do not have permission to perform this action (${code})`,
        403,
        'FORBIDDEN'
      );
    }

    next();
  };
}

/**
 * Checks whether the logged in user has ANY of the given permissions.
 * Super Admin bypasses permission checks.
 */
function requireAnyPermission(codes) {
  return (req, res, next) => {
    if (!req.user) {
      return error(
        res,
        'Authentication required',
        401,
        'UNAUTHORIZED'
      );
    }

    if (req.user.isSuperAdmin) {
      return next();
    }

    const userPerms =
      req.user.permissions || [];

    if (
      !codes.some((code) =>
        userPerms.includes(code)
      )
    ) {
      return error(
        res,
        `You do not have permission to perform this action (${codes.join(' or ')})`,
        403,
        'FORBIDDEN'
      );
    }

    next();
  };
}

/**
 * Checks whether the logged in user has one of the required roles.
 * Super Admin always passes.
 */
function requireRole(...roleNames) {
  return (req, res, next) => {
    if (!req.user) {
      return error(
        res,
        'Authentication required',
        401,
        'UNAUTHORIZED'
      );
    }

    if (req.user.isSuperAdmin) {
      return next();
    }

    const currentRole = String(req.user.roleName || '')
      .trim()
      .toLowerCase();

    const allowedRoles = roleNames.map((role) =>
      String(role).trim().toLowerCase()
    );

    if (!allowedRoles.includes(currentRole)) {
      return error(
        res,
        'Insufficient role privileges',
        403,
        'FORBIDDEN'
      );
    }

    next();
  };
}

module.exports = {
  requirePermission,
  requireAnyPermission,
  requireRole
};