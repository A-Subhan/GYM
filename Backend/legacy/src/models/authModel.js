const { getPool } = require('../config/db');

async function getUserByUsername(username) {
  const pool = await getPool();
  const result = await pool.request().input('Username', username).execute('sp_Users_GetByUsername');
  return result.recordset[0] || null;
}

async function getUserById(userId) {
  const pool = await getPool();
  const result = await pool.request().input('UserID', userId).execute('sp_Users_GetByID');
  return result.recordset[0] || null;
}

async function getUserPermissions(userId) {
  const pool = await getPool();
  const result = await pool.request().input('UserID', userId).execute('sp_Users_GetPermissions');
  return result.recordset;
}

async function updateLoginSuccess(userId) {
  const pool = await getPool();
  await pool.request().input('UserID', userId).execute('sp_Users_UpdateLogin');
}

async function createSession({ userId, refreshToken, ipAddress, userAgent, location }) {
  const pool = await getPool();
  const result = await pool
    .request()
    .input('UserID', userId)
    .input('RefreshToken', refreshToken)
    .input('IPAddress', ipAddress)
    .input('UserAgent', userAgent)
    .input('Location', location)
    .execute('sp_Sessions_Create');
  return result.recordset[0];
}

async function logoutSession(refreshToken) {
  const pool = await getPool();
  await pool.request().input('RefreshToken', refreshToken).execute('sp_Sessions_Logout');
}

async function getSessionByToken(refreshToken) {
  const pool = await getPool();
  const result = await pool.request().input('RefreshToken', refreshToken).execute('sp_Sessions_GetByToken');
  return result.recordset[0] || null;
}

async function heartbeat(refreshToken) {
  const pool = await getPool();
  await pool.request().input('RefreshToken', refreshToken).execute('sp_Sessions_Heartbeat');
}

async function changePassword(userId, hash, mustChange = false) {
  const pool = await getPool();
  await pool
    .request()
    .input('UserID', userId)
    .input('PasswordHash', hash)
    .input('MustChangePassword', mustChange)
    .execute('sp_Users_ChangePassword');
}

async function listUserSessions(userId) {
  const pool = await getPool();
  const result = await pool.request().input('UserID', userId).execute('sp_Sessions_ListByUser');
  return result.recordset;
}

module.exports = {
  getUserByUsername,
  getUserById,
  getUserPermissions,
  updateLoginSuccess,
  createSession,
  logoutSession,
  getSessionByToken,
  heartbeat,
  changePassword,
  listUserSessions,
};
