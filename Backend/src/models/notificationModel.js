const { getPool } = require('../config/db');

async function list({ userId, unreadOnly, page, pageSize }) {
  const pool = await getPool();
  const r = await pool.request()
    .input('UserID', userId || null)
    .input('UnreadOnly', unreadOnly ? 1 : 0)
    .input('Page', page || 1)
    .input('PageSize', pageSize || 50)
    .execute('sp_Notifications_List');
  return { rows: r.recordsets[0], meta: r.recordsets[1][0] || {} };
}

async function markRead(id, userId) {
  const pool = await getPool();
  await pool.request().input('NotificationID', id).input('UserID', userId || null).execute('sp_Notifications_MarkRead');
}

async function markAllRead(userId) {
  const pool = await getPool();
  await pool.request().input('UserID', userId).execute('sp_Notifications_MarkAllRead');
}

async function create(data) {
  const pool = await getPool();
  const r = await pool.request()
    .input('Type', data.Type)
    .input('Title', data.Title)
    .input('Message', data.Message)
    .input('UserID', data.UserID || null)
    .input('EntityID', data.EntityID || null)
    .execute('sp_Notifications_Create');
  return r.recordset[0].NotificationID;
}

async function remove(id) {
  const pool = await getPool();
  await pool.request().input('NotificationID', id).execute('sp_Notifications_Delete');
}

module.exports = { list, markRead, markAllRead, create, remove };
