const { getPool } = require('../config/db');
const { VarBinary } = require('mssql');

/* ----------- Members ----------- */

async function list({ page, pageSize, search, branchId, status, trainerId }) {
  const pool = await getPool();

  const result = await pool
    .request()
    .input('Page', page)
    .input('PageSize', pageSize)
    .input('Search', search)
    .input('BranchID', branchId)
    .input('Status', status)
    .input('TrainerID', trainerId)
    .execute('sp_Members_List');

  return {
    rows: result.recordsets[0],
    total: result.recordsets[1][0]?.Total || 0
  };
}

async function get(id) {
  const pool = await getPool();

  const result = await pool
    .request()
    .input('MemberID', id)
    .execute('sp_Members_Get');

  return result.recordset[0] || null;
}

async function create(data, createdBy) {
  const pool = await getPool();

  const result = await pool
    .request()
    .input('BranchID', data.BranchID)
    .input('FullName', data.FullName)
    .input('FatherName', data.FatherName || null)
    .input('Gender', data.Gender || null)
    .input('DOB', data.DOB || null)
    .input('CNIC', data.CNIC || null)
    .input('Mobile', data.Mobile || null)
    .input('WhatsApp', data.WhatsApp || null)
    .input('Email', data.Email || null)
    .input('Address', data.Address || null)
    .input('EmergencyContact', data.EmergencyContact || null)
    .input('Photo', VarBinary(VarBinary.MAX), data.Photo || null)
    .input('JoiningDate', data.JoiningDate)
    .input('TrainerID', data.TrainerID || null)
    .input('HeightFeet', data.HeightFeet || null)
    .input('HeightInches', data.HeightInches || null)
    .input('Weight', data.Weight || null)
    .input('MedicalNotes', data.MedicalNotes || null)
    .input('Status', data.Status || 'Active')
    .input('CreatedBy', createdBy)
    .execute('sp_Members_Create');

  return result.recordset[0];
}

async function update(id, data, updatedBy) {
  const pool = await getPool();

  await pool
    .request()
    .input('MemberID', id)
    .input('FullName', data.FullName || null)
    .input('FatherName', data.FatherName || null)
    .input('Gender', data.Gender || null)
    .input('DOB', data.DOB || null)
    .input('CNIC', data.CNIC || null)
    .input('Mobile', data.Mobile || null)
    .input('WhatsApp', data.WhatsApp || null)
    .input('Email', data.Email || null)
    .input('Address', data.Address || null)
    .input('EmergencyContact', data.EmergencyContact || null)
    .input('Photo', VarBinary(VarBinary.MAX), data.Photo || null)
    .input('JoiningDate', data.JoiningDate || null)
    .input('TrainerID', data.TrainerID || null)
    .input('HeightFeet', data.HeightFeet || null)
    .input('HeightInches', data.HeightInches || null)
    .input('Weight', data.Weight || null)
    .input('MedicalNotes', data.MedicalNotes || null)
    .input('Status', data.Status || null)
    .input('UpdatedBy', updatedBy)
    .execute('sp_Members_Update');
}

async function softDelete(id, deletedBy) {
  const pool = await getPool();

  await pool
    .request()
    .input('MemberID', id)
    .input('DeletedBy', deletedBy)
    .execute('sp_Members_SoftDelete');
}

/* ----------- Member sub-resources ----------- */

async function getPayments(id) {
  const pool = await getPool();

  const result = await pool
    .request()
    .input('MemberID', id)
    .execute('sp_Members_GetPayments');

  return result.recordset;
}

async function getAttendance(id, fromDate, toDate) {
  const pool = await getPool();

  const result = await pool
    .request()
    .input('MemberID', id)
    .input('FromDate', fromDate || null)
    .input('ToDate', toDate || null)
    .execute('sp_Members_GetAttendance');

  return result.recordset;
}

async function getMemberships(id) {
  const pool = await getPool();

  const result = await pool
    .request()
    .input('MemberID', id)
    .execute('sp_Members_GetMemberships');

  return result.recordset;
}

async function getProgress(id) {
  const pool = await getPool();

  const result = await pool
    .request()
    .input('MemberID', id)
    .execute('sp_Members_GetProgress');

  return result.recordset;
}

module.exports = {
  list,
  get,
  create,
  update,
  softDelete,
  getPayments,
  getAttendance,
  getMemberships,
  getProgress
};
