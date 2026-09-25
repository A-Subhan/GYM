const { getPool } = require('../config/db');

async function list({ page, pageSize, branchId, memberId, date, fromDate, toDate }) {
  const pool = await getPool();
  const result = await pool
    .request()
    .input('Page', page)
    .input('PageSize', pageSize)
    .input('BranchID', branchId || null)
    .input('MemberID', memberId || null)
    .input('Date', date || null)
    .input('FromDate', fromDate || null)
    .input('ToDate', toDate || null)
    .execute('sp_Attendance_List');
  return { rows: result.recordsets[0], total: result.recordsets[1][0]?.Total || 0 };
}

async function checkIn({ memberId, branchId, method, ipAddress, createdBy }) {
  const pool = await getPool();
  const result = await pool
    .request()
    .input('MemberID', memberId)
    .input('BranchID', branchId)
    .input('Method', method || 'Manual')
    .input('IPAddress', ipAddress || null)
    .input('CreatedBy', createdBy)
    .execute('sp_Attendance_CheckIn');
  return result.recordset[0]?.AttendanceID;
}

async function checkOut(id) {
  const pool = await getPool();
  await pool.request().input('AttendanceID', id).execute('sp_Attendance_CheckOut');
}

async function todayCount(branchId = null) {
  const pool = await getPool();
  const result = await pool.request().input('BranchID', branchId).execute('sp_Attendance_TodayCount');
  return result.recordset[0]?.TodayCount || 0;
}

module.exports = { list, checkIn, checkOut, todayCount };
