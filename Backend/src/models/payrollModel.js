const { getPool } = require('../config/db');

async function list({ page, pageSize, staffId, branchId, month, year, status }) {
  const pool = await getPool();
  const r = await pool.request()
    .input('Page', page)
    .input('PageSize', pageSize)
    .input('StaffID', staffId || null)
    .input('BranchID', branchId || null)
    .input('Month', month || null)
    .input('Year', year || null)
    .input('Status', status || null)
    .execute('sp_Payroll_List');
  return { rows: r.recordsets[0], total: r.recordsets[1][0]?.Total || 0, totalNet: r.recordsets[1][0]?.TotalNet || 0 };
}

async function get(id) {
  const pool = await getPool();
  const r = await pool.request().input('PayrollID', id).execute('sp_Payroll_Get');
  return r.recordset[0] || null;
}

async function generate(data, generatedBy) {
  const pool = await getPool();
  const r = await pool.request()
    .input('StaffID', data.StaffID)
    .input('Month', data.Month)
    .input('Year', data.Year)
    .input('Bonus', data.Bonus || 0)
    .input('Overtime', data.Overtime || 0)
    .input('LeaveDeduction', data.LeaveDeduction || 0)
    .input('Commission', data.Commission || 0)
    .input('GeneratedBy', generatedBy)
    .execute('sp_Payroll_Generate');
  return r.recordset[0].PayrollID;
}

async function generateAll(data, generatedBy) {
  const pool = await getPool();
  const r = await pool.request()
    .input('Month', data.Month)
    .input('Year', data.Year)
    .input('BranchID', data.BranchID || null)
    .input('Bonus', data.Bonus || 0)
    .input('Overtime', data.Overtime || 0)
    .input('LeaveDeduction', data.LeaveDeduction || 0)
    .input('Commission', data.Commission || 0)
    .input('GeneratedBy', generatedBy)
    .execute('sp_Payroll_GenerateAll');
  return r.recordset[0]?.InsertedCount || 0;
}

async function markPaid(id) {
  const pool = await getPool();
  await pool.request().input('PayrollID', id).execute('sp_Payroll_MarkPaid');
}

async function update(id, data) {
  const pool = await getPool();
  await pool.request()
    .input('PayrollID', id)
    .input('Bonus', data.Bonus)
    .input('Overtime', data.Overtime)
    .input('LeaveDeduction', data.LeaveDeduction)
    .input('Commission', data.Commission)
    .execute('sp_Payroll_Update');
}

module.exports = { list, get, generate, generateAll, markPaid, update };
