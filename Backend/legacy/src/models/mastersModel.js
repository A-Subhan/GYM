const { getPool } = require('../config/db');

/* ----------- Master definitions ----------- */

async function listDefinitions() {
  const pool = await getPool();
  const r = await pool.request().execute('sp_MasterDefinitions_List');
  return r.recordset;
}

async function createDefinition(data, createdBy) {
  const pool = await getPool();
  const r = await pool.request()
    .input('Name', data.Name)
    .input('MasterCode', data.MasterCode || null)
    .input('Scope', data.Scope || 'Global')
    .input('CreatedBy', createdBy)
    .execute('sp_MasterDefinitions_Create');
  return r.recordset[0];
}

async function updateDefinition(id, data, updatedBy) {
  const pool = await getPool();
  await pool.request()
    .input('MasterDefinitionID', id)
    .input('Name', data.Name || null)
    .input('Scope', data.Scope || null)
    .input('IsActive', data.IsActive !== undefined && data.IsActive !== null ? (data.IsActive ? 1 : 0) : null)
    .input('UpdatedBy', updatedBy)
    .execute('sp_MasterDefinitions_Update');
}

async function deleteDefinition(id) {
  const pool = await getPool();
  await pool.request()
    .input('MasterDefinitionID', id)
    .execute('sp_MasterDefinitions_Delete');
}

/* ----------- Master items ----------- */

async function listItems({ definitionId, search, isActive, branchId, page, pageSize }) {
  const pool = await getPool();
  const r = await pool.request()
    .input('MasterDefinitionID', definitionId)
    .input('Search', search || null)
    .input('IsActive', isActive === undefined ? null : isActive)
    .input('BranchID', branchId || null)
    .input('Page', page)
    .input('PageSize', pageSize)
    .execute('sp_MasterItems_List');
  return { rows: r.recordsets[0], total: r.recordsets[1][0]?.Total || 0 };
}

async function createItem({ definitionId, name, branchId, createdBy }) {
  const pool = await getPool();
  const r = await pool.request()
    .input('MasterDefinitionID', definitionId)
    .input('Name', name)
    .input('BranchID', branchId || null)
    .input('CreatedBy', createdBy)
    .execute('sp_MasterItems_Create');
  return r.recordset[0];
}

async function updateItem(id, data, updatedBy) {
  const pool = await getPool();
  await pool.request()
    .input('MasterItemID', id)
    .input('Name', data.Name)
    .input('UpdatedBy', updatedBy)
    .execute('sp_MasterItems_Update');
}

async function setItemStatus(id, isActive, updatedBy) {
  const pool = await getPool();
  await pool.request()
    .input('MasterItemID', id)
    .input('IsActive', isActive ? 1 : 0)
    .input('UpdatedBy', updatedBy)
    .execute('sp_MasterItems_SetStatus');
}

async function deleteItem(id) {
  const pool = await getPool();
  await pool.request()
    .input('MasterItemID', id)
    .execute('sp_MasterItems_Delete');
}

module.exports = {
  listDefinitions,
  createDefinition,
  updateDefinition,
  deleteDefinition,
  listItems,
  createItem,
  updateItem,
  setItemStatus,
  deleteItem
};
