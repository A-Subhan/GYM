const authModel = require('../models/authModel');
const { comparePassword, hashPassword } = require('../utils/hash');
const { signAccessToken, signRefreshToken, verifyToken } = require('../utils/jwt');
const { writeAudit } = require('../middleware/audit');
const { AUDIT_ACTIONS, MODULES } = require('../config/constants');

async function login({ username, password, ipAddress, userAgent, location }) {
  const normalizedUsername = String(username ?? '').trim();
  const normalizedPassword = String(password ?? '').trim();

  const user = await authModel.getUserByUsername(normalizedUsername);
  if (!user) {
    await writeAudit({ action: AUDIT_ACTIONS.LOGIN_FAILED, module: MODULES.AUTH, details: JSON.stringify({ username: normalizedUsername }), ipAddress, location });
    const err = new Error('Invalid username or password'); err.code = 'INVALID_CREDENTIALS'; err.status = 401; throw err;
  }
  if (!user.IsActive || user.IsDeleted) {
    const err = new Error('Account is inactive. Contact administrator.'); err.code = 'ACCOUNT_INACTIVE'; err.status = 403; throw err;
  }

  const ok = comparePassword(normalizedPassword, user.PasswordHash);
  if (!ok) {
    await writeAudit({ userId: user.UserID, action: AUDIT_ACTIONS.LOGIN_FAILED, module: MODULES.AUTH, details: JSON.stringify({ username: normalizedUsername }), ipAddress, location });
    const err = new Error('Invalid username or password'); err.code = 'INVALID_CREDENTIALS'; err.status = 401; throw err;
  }

  await authModel.updateLoginSuccess(user.UserID);

  const accessToken = signAccessToken({ userId: user.UserID, username: user.Username });
  const refreshToken = signRefreshToken({ userId: user.UserID, tokenType: 'refresh' });

  await authModel.createSession({
    userId: user.UserID,
    refreshToken,
    ipAddress,
    userAgent,
    location,
  });

  const permissions = await authModel.getUserPermissions(user.UserID);

  await writeAudit({
    userId: user.UserID,
    action: AUDIT_ACTIONS.LOGIN,
    module: MODULES.AUTH,
    details: JSON.stringify({ username, location }),
    ipAddress,
    location,
  });

  return {
    accessToken,
    refreshToken,
    user: {
      userId: user.UserID,
      username: user.Username,
      fullName: user.FullName,
      email: user.Email,
      phone: user.Phone,
      photo: user.Photo,
      roleId: user.RoleID,
      roleName: user.RoleName,
      branchId: user.BranchID,
      isSuperAdmin: user.RoleID === 1,
      lastLoginAt: user.LastLoginAt,
    },
    permissions: permissions.map((p) => p.Code),
  };
}

async function logout(refreshToken, userId, ipAddress) {
  if (!refreshToken) return;
  await authModel.logoutSession(refreshToken);
  await writeAudit({ userId, action: AUDIT_ACTIONS.LOGOUT, module: MODULES.AUTH, ipAddress });
}

async function refresh(refreshToken) {
  if (!refreshToken) {
    const err = new Error('Refresh token required'); err.code = 'BAD_REQUEST'; err.status = 400; throw err;
  }
  let decoded;
  try { decoded = verifyToken(refreshToken); } catch (_) {
    const err = new Error('Invalid or expired refresh token'); err.code = 'TOKEN_EXPIRED'; err.status = 401; throw err;
  }
  const session = await authModel.getSessionByToken(refreshToken);
  if (!session || session.Status !== 'Active') {
    const err = new Error('Session not found or expired'); err.code = 'SESSION_EXPIRED'; err.status = 401; throw err;
  }
  if (!session.IsActive) {
    const err = new Error('Account is inactive'); err.code = 'ACCOUNT_INACTIVE'; err.status = 403; throw err;
  }
  const accessToken = signAccessToken({ userId: session.UserID, username: session.Username });
  return { accessToken };
}

async function heartbeat(refreshToken) {
  if (!refreshToken) return;
  await authModel.heartbeat(refreshToken);
}

async function changePassword(userId, currentPassword, newPassword) {
  const user = await authModel.getUserById(userId);
  if (!user) { const err = new Error('User not found'); err.status = 404; throw err; }
  const fullUser = await authModel.getUserByUsername(user.Username);
  if (!comparePassword(currentPassword, fullUser.PasswordHash)) {
    const err = new Error('Current password is incorrect'); err.code = 'INVALID_PASSWORD'; err.status = 400; throw err;
  }
  const newPasswordHash = hashPassword(newPassword);
  await authModel.changePassword(userId, newPasswordHash, false);
}

async function listSessions(userId) {
  return authModel.listUserSessions(userId);
}

module.exports = { login, logout, refresh, heartbeat, changePassword, listSessions };
