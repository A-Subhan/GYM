const { getPool } = require('../config/db');

async function list({ page, pageSize, userId, module, action, fromDate, toDate }) {
  const pool = await getPool();
  const result = await pool
    .request()
    .input('Page', page)
    .input('PageSize', pageSize)
    .input('UserID', userId || null)
    .input('Module', module || null)
    .input('Action', action || null)
    .input('FromDate', fromDate || null)
    .input('ToDate', toDate || null)
    .execute('sp_AuditLogs_List');
  return { rows: result.recordsets[0], total: result.recordsets[1][0]?.Total || 0 };
}

module.exports = { list };
