const { getPool } = require('../config/db');

async function list(isActive = null) {
  const pool = await getPool();
  const result = await pool.request().input('IsActive', isActive).execute('sp_Branches_List');
  return result.recordset;
}

async function get(id) {
  const pool = await getPool();
  const result = await pool.request().input('BranchID', id).execute('sp_Branches_Get');
  return result.recordset[0] || null;
}

async function create(data, createdBy) {
  const pool = await getPool();
  const result = await pool
    .request()
    .input('Code', data.Code)
    .input('Name', data.Name)
    .input('Address', data.Address || null)
    .input('City', data.City || null)
    .input('Phone', data.Phone || null)
    .input('Email', data.Email || null)
    .input('ManagerName', data.ManagerName || null)
    .input('CreatedBy', createdBy)
    .execute('sp_Branches_Create');
  return result.recordset[0]?.NewBranchID;
}

async function update(id, data, updatedBy) {
  const pool = await getPool();
  await pool
    .request()
    .input('BranchID', id)
    .input('Code', data.Code || null)
    .input('Name', data.Name || null)
    .input('Address', data.Address || null)
    .input('City', data.City || null)
    .input('Phone', data.Phone || null)
    .input('Email', data.Email || null)
    .input('ManagerName', data.ManagerName || null)
    .input('IsActive', data.IsActive !== undefined ? (data.IsActive ? 1 : 0) : null)
    .input('UpdatedBy', updatedBy)
    .execute('sp_Branches_Update');
}

async function softDelete(id) {
  const pool = await getPool();
  await pool.request().input('BranchID', id).execute('sp_Branches_SoftDelete');
}

module.exports = { list, get, create, update, softDelete };
