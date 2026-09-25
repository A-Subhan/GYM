const { getPool } = require('../config/db');

async function list({ page, pageSize, branchId, status, search }) {
  const pool = await getPool();
  const r = await pool.request()
    .input('Page', page)
    .input('PageSize', pageSize)
    .input('BranchID', branchId || null)
    .input('Status', status || null)
    .input('Search', search || null)
    .execute('sp_Equipment_List');
  return { rows: r.recordsets[0], meta: r.recordsets[1][0] || {} };
}

async function get(id) {
  const pool = await getPool();
  const r = await pool.request().input('EquipmentID', id).execute('sp_Equipment_Get');
  return r.recordset[0] || null;
}

async function create(data, createdBy) {
  const pool = await getPool();
  const r = await pool.request()
    .input('BranchID', data.BranchID)
    .input('Name', data.Name)
    .input('Brand', data.Brand || null)
    .input('SerialNo', data.SerialNo || null)
    .input('PurchaseDate', data.PurchaseDate || null)
    .input('PurchasePrice', data.PurchasePrice || null)
    .input('WarrantyExpiry', data.WarrantyExpiry || null)
    .input('Status', data.Status || 'Active')
    .input('Notes', data.Notes || null)
    .input('CreatedBy', createdBy)
    .execute('sp_Equipment_Create');
  return r.recordset[0].EquipmentID;
}

async function update(id, data) {
  const pool = await getPool();
  await pool.request()
    .input('EquipmentID', id)
    .input('BranchID', data.BranchID || null)
    .input('Name', data.Name || null)
    .input('Brand', data.Brand || null)
    .input('SerialNo', data.SerialNo || null)
    .input('PurchaseDate', data.PurchaseDate || null)
    .input('PurchasePrice', data.PurchasePrice || null)
    .input('WarrantyExpiry', data.WarrantyExpiry || null)
    .input('Status', data.Status || null)
    .input('Notes', data.Notes || null)
    .execute('sp_Equipment_Update');
}

async function softDelete(id) {
  const pool = await getPool();
  await pool.request().input('EquipmentID', id).execute('sp_Equipment_SoftDelete');
}

async function listMaintenance({ equipmentId, branchId }) {
  const pool = await getPool();
  const r = await pool.request()
    .input('EquipmentID', equipmentId || null)
    .input('BranchID', branchId || null)
    .execute('sp_EquipmentMaintenance_List');
  return r.recordset;
}

async function createMaintenance(data, createdBy) {
  const pool = await getPool();
  const r = await pool.request()
    .input('EquipmentID', data.EquipmentID)
    .input('Type', data.Type || 'Routine')
    .input('Cost', data.Cost || 0)
    .input('StartDate', data.StartDate)
    .input('EndDate', data.EndDate || null)
    .input('Notes', data.Notes || null)
    .input('CreatedBy', createdBy)
    .execute('sp_EquipmentMaintenance_Create');
  return r.recordset[0].MaintID;
}

async function completeMaintenance(id) {
  const pool = await getPool();
  await pool.request().input('MaintID', id).execute('sp_EquipmentMaintenance_Complete');
}

module.exports = {
  list, get, create, update, softDelete,
  listMaintenance, createMaintenance, completeMaintenance,
};
