const { getPool } = require('../config/db');

async function listDepartments() {
  const pool = await getPool();
  const r = await pool.request().execute('sp_Departments_List');
  return r.recordset;
}

/* Staff currently tagged as trainers (active Trainers row) */
async function listTrainers(branchId) {
  const pool = await getPool();
  const r = await pool.request()
    .input('BranchID', branchId || null)
    .execute('sp_Staff_ListTrainers');
  return r.recordset;
}

async function list({ page, pageSize, search, branchId, departmentId, status, isTrainer }) {
  const pool = await getPool();
  const r = await pool.request()
    .input('Page', page)
    .input('PageSize', pageSize)
    .input('Search', search || null)
    .input('BranchID', branchId || null)
    .input('DepartmentID', departmentId || null)
    .input('Status', status || null)
    .input('IsTrainer', isTrainer === undefined ? null : isTrainer)
    .execute('sp_Staff_List');
  return { rows: r.recordsets[0], total: r.recordsets[1][0]?.Total || 0 };
}

async function get(id) {
  const pool = await getPool();
  const r = await pool.request().input('StaffID', id).execute('sp_Staff_Get');
  return r.recordset[0] || null;
}

async function create(data, createdBy) {
  const pool = await getPool();
  const r = await pool.request()
    .input('BranchID', data.BranchID)
    .input('DepartmentID', data.DepartmentID)
    .input('UserID', data.UserID || null)
    .input('FullName', data.FullName)
    .input('FatherName', data.FatherName || null)
    .input('CNIC', data.CNIC || null)
    .input('Mobile', data.Mobile || null)
    .input('Email', data.Email || null)
    .input('Address', data.Address || null)
    .input('Photo', data.Photo || null)
    .input('JoiningDate', data.JoiningDate)
    .input('Designation', data.Designation || null)
    .input('BaseSalary', data.BaseSalary || 0)
    .input('Status', data.Status || 'Active')
    .input('Specialization', data.Specialization || null)
    .input('Experience', data.Experience || null)
    .input('CreatedBy', createdBy)
    .execute('sp_Staff_Create');
  return r.recordset[0];
}

async function update(id, data, updatedBy) {
  const pool = await getPool();
  await pool.request()
    .input('StaffID', id)
    .input('BranchID', data.BranchID || null)
    .input('DepartmentID', data.DepartmentID || null)
    .input('UserID', data.UserID || null)
    .input('FullName', data.FullName || null)
    .input('FatherName', data.FatherName || null)
    .input('CNIC', data.CNIC || null)
    .input('Mobile', data.Mobile || null)
    .input('Email', data.Email || null)
    .input('Address', data.Address || null)
    .input('Photo', data.Photo || null)
    .input('JoiningDate', data.JoiningDate || null)
    .input('Designation', data.Designation || null)
    .input('BaseSalary', data.BaseSalary || null)
    .input('Status', data.Status || null)
    .input('Specialization', data.Specialization || null)
    .input('Experience', data.Experience || null)
    .input('UpdatedBy', updatedBy)
    .execute('sp_Staff_Update');
}

async function softDelete(id, deletedBy) {
  const pool = await getPool();
  await pool.request().input('StaffID', id).input('DeletedBy', deletedBy).execute('sp_Staff_SoftDelete');
}

/* Staff Attendance */
async function listAttendance({ staffId, fromDate, toDate }) {
  const pool = await getPool();
  const r = await pool.request()
    .input('StaffID', staffId || null)
    .input('FromDate', fromDate || null)
    .input('ToDate', toDate || null)
    .execute('sp_StaffAttendance_List');
  return r.recordset;
}

async function markAttendance(data) {
  const pool = await getPool();
  await pool.request()
    .input('StaffID', data.StaffID)
    .input('Date', data.Date)
    .input('CheckIn', data.CheckIn || null)
    .input('CheckOut', data.CheckOut || null)
    .input('Status', data.Status || 'Present')
    .input('Notes', data.Notes || null)
    .execute('sp_StaffAttendance_Mark');
}

/* Staff Leaves */
async function listLeaves({ staffId, status }) {
  const pool = await getPool();
  const r = await pool.request()
    .input('StaffID', staffId || null)
    .input('Status', status || null)
    .execute('sp_StaffLeaves_List');
  return r.recordset;
}

async function createLeave(data) {
  const pool = await getPool();
  const r = await pool.request()
    .input('StaffID', data.StaffID)
    .input('LeaveType', data.LeaveType)
    .input('StartDate', data.StartDate)
    .input('EndDate', data.EndDate)
    .input('Reason', data.Reason || null)
    .execute('sp_StaffLeaves_Create');
  return r.recordset[0].LeaveID;
}

async function updateLeaveStatus(leaveId, status, approvedBy) {
  const pool = await getPool();
  await pool.request()
    .input('LeaveID', leaveId)
    .input('Status', status)
    .input('ApprovedBy', approvedBy)
    .execute('sp_StaffLeaves_UpdateStatus');
}

module.exports = {
  listDepartments, listTrainers, list, get, create, update, softDelete,
  listAttendance, markAttendance,
  listLeaves, createLeave, updateLeaveStatus,
};
