const { getPool } = require('../config/db');

async function getStats(branchId = null) {
  const pool = await getPool();
  const result = await pool.request().input('BranchID', branchId).execute('sp_Dashboard_Stats');
  return result.recordset[0];
}

async function getCharts(months = 6, branchId = null) {
  const pool = await getPool();
  const result = await pool
    .request()
    .input('Months', months)
    .input('BranchID', branchId)
    .execute('sp_Dashboard_Charts');
  return {
    revenue: result.recordsets[0],
    expenses: result.recordsets[1],
    attendance: result.recordsets[2],
    membershipGrowth: result.recordsets[3],
  };
}

module.exports = { getStats, getCharts };
