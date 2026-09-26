const { getPool } = require('../config/db');

async function members({ branchId, status, fromDate, toDate }) {
  const pool = await getPool();
  const r = await pool.request()
    .input('BranchID', branchId || null)
    .input('Status', status || null)
    .input('FromDate', fromDate || null)
    .input('ToDate', toDate || null)
    .execute('sp_Reports_Members');
  return r.recordset;
}

async function attendance({ branchId, fromDate, toDate }) {
  const pool = await getPool();
  const r = await pool.request()
    .input('BranchID', branchId || null)
    .input('FromDate', fromDate || null)
    .input('ToDate', toDate || null)
    .execute('sp_Reports_Attendance');
  return r.recordset;
}

async function payments({ branchId, fromDate, toDate, methodId }) {
  const pool = await getPool();
  const r = await pool.request()
    .input('BranchID', branchId || null)
    .input('FromDate', fromDate || null)
    .input('ToDate', toDate || null)
    .input('MethodID', methodId || null)
    .execute('sp_Reports_Payments');
  return r.recordset;
}

async function salary({ branchId, month, year }) {
  const pool = await getPool();
  const r = await pool.request()
    .input('BranchID', branchId || null)
    .input('Month', month || null)
    .input('Year', year || null)
    .execute('sp_Reports_Salary');
  return r.recordset;
}

async function equipment({ branchId, status }) {
  const pool = await getPool();
  const r = await pool.request()
    .input('BranchID', branchId || null)
    .input('Status', status || null)
    .execute('sp_Reports_Equipment');
  return r.recordset;
}

async function inventory({ branchId, category }) {
  const pool = await getPool();
  const r = await pool.request()
    .input('BranchID', branchId || null)
    .input('Category', category || null)
    .execute('sp_Reports_Inventory');
  return r.recordset;
}

module.exports = { members, attendance, payments, salary, equipment, inventory };
