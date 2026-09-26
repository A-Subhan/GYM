const { getPool } = require('../config/db');

async function listUsers({ page, pageSize, search, roleId, branchId }) {
  const pool = await getPool();
  const result = await pool
    .request()
    .input('Page', page)
    .input('PageSize', pageSize)
    .input('Search', search || null)
    .input('RoleID', roleId || null)
    .input('BranchID', branchId || null)
    .execute('sp_Users_List');
  return { rows: result.recordsets[0], total: result.recordsets[1][0]?.Total || 0 };
}

async function getUserById(id) {
  const pool = await getPool();
  const result = await pool.request().input('UserID', id).execute('sp_Users_GetByID');
  return result.recordset[0] || null;
}

async function createUser(data) {
  const pool = await getPool();
  const result = await pool
    .request()
    .input('Username', data.Username)
    .input('Email', data.Email)
    .input('FullName', data.FullName)
    .input('PasswordHash', data.PasswordHash)
    .input('RoleID', data.RoleID)
    .input('BranchID', data.BranchID || null)
    .input('Phone', data.Phone || null)
    .input('Photo', data.Photo || null)
    .input('MustChangePassword', data.MustChangePassword || 0)
    .input('CreatedBy', data.CreatedBy || null)
    .execute('sp_Users_Create');
  return result.recordset[0]?.NewUserID;
}

async function updateUser(id, data, updatedBy) {
  const pool = await getPool();
  await pool
    .request()
    .input('UserID', id)
    .input('Email', data.Email || null)
    .input('FullName', data.FullName || null)
    .input('RoleID', data.RoleID || null)
    .input('BranchID', data.BranchID || null)
    .input('Phone', data.Phone || null)
    .input('Photo', data.Photo || null)
    .input('IsActive', data.IsActive !== undefined ? (data.IsActive ? 1 : 0) : null)
    .input('UpdatedBy', updatedBy)
    .execute('sp_Users_Update');
}

async function softDeleteUser(id, deletedBy) {
  const pool = await getPool();
  await pool.request().input('UserID', id).input('DeletedBy', deletedBy).execute('sp_Users_SoftDelete');
}

async function listRoles() {
  const pool = await getPool();
  const result = await pool.request().execute('sp_Roles_List');
  return result.recordset;
}

async function listPermissions() {
  const pool = await getPool();
  const result = await pool.request().execute('sp_Permissions_List');
  return result.recordset;
}

async function getRolePermissions(roleId) {
  const pool = await getPool();
  const result = await pool.request().input('RoleID', roleId).execute('sp_RolePermissions_Get');
  return result.recordset;
}

async function setRolePermissions(roleId, permissionIds) {
  const pool = await getPool();
  await pool
    .request()
    .input('RoleID', roleId)
    .input('PermissionIDs', permissionIds && permissionIds.length ? permissionIds.join(',') : null)
    .execute('sp_RolePermissions_Set');
}

module.exports = {
  listUsers,
  getUserById,
  createUser,
  updateUser,
  softDeleteUser,
  listRoles,
  listPermissions,
  getRolePermissions,
  setRolePermissions,
};
