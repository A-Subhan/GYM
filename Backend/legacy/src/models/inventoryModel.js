const { getPool } = require('../config/db');

/* Suppliers */
async function listSuppliers(isActive = null) {
  const pool = await getPool();
  const r = await pool.request().input('IsActive', isActive).execute('sp_Suppliers_List');
  return r.recordset;
}
async function createSupplier(data) {
  const pool = await getPool();
  const r = await pool.request()
    .input('Name', data.Name)
    .input('Contact', data.Contact || null)
    .input('Phone', data.Phone || null)
    .input('Email', data.Email || null)
    .input('Address', data.Address || null)
    .execute('sp_Suppliers_Create');
  return r.recordset[0].SupplierID;
}
async function updateSupplier(id, data) {
  const pool = await getPool();
  await pool.request()
    .input('SupplierID', id)
    .input('Name', data.Name || null)
    .input('Contact', data.Contact || null)
    .input('Phone', data.Phone || null)
    .input('Email', data.Email || null)
    .input('Address', data.Address || null)
    .input('IsActive', data.IsActive !== undefined ? (data.IsActive ? 1 : 0) : null)
    .execute('sp_Suppliers_Update');
}
async function deleteSupplier(id) {
  const pool = await getPool();
  await pool.request().input('SupplierID', id).execute('sp_Suppliers_SoftDelete');
}

/* Items */
async function list({ page, pageSize, branchId, category, search, lowStockOnly }) {
  const pool = await getPool();
  const r = await pool.request()
    .input('Page', page)
    .input('PageSize', pageSize)
    .input('BranchID', branchId || null)
    .input('Category', category || null)
    .input('Search', search || null)
    .input('LowStockOnly', lowStockOnly ? 1 : 0)
    .execute('sp_Inventory_List');
  return { rows: r.recordsets[0], meta: r.recordsets[1][0] || {} };
}
async function createItem(data, createdBy) {
  const pool = await getPool();
  const r = await pool.request()
    .input('BranchID', data.BranchID)
    .input('Name', data.Name)
    .input('Category', data.Category)
    .input('SKU', data.SKU || null)
    .input('StockQty', data.StockQty || 0)
    .input('ReorderLevel', data.ReorderLevel || 0)
    .input('SalePrice', data.SalePrice || 0)
    .input('PurchasePrice', data.PurchasePrice || 0)
    .input('CreatedBy', createdBy)
    .execute('sp_Inventory_Create');
  return r.recordset[0].ItemID;
}
async function updateItem(id, data) {
  const pool = await getPool();
  await pool.request()
    .input('ItemID', id)
    .input('Name', data.Name || null)
    .input('Category', data.Category || null)
    .input('SKU', data.SKU || null)
    .input('StockQty', data.StockQty || null)
    .input('ReorderLevel', data.ReorderLevel || null)
    .input('SalePrice', data.SalePrice || null)
    .input('PurchasePrice', data.PurchasePrice || null)
    .input('IsActive', data.IsActive !== undefined ? (data.IsActive ? 1 : 0) : null)
    .execute('sp_Inventory_Update');
}
async function deleteItem(id) {
  const pool = await getPool();
  await pool.request().input('ItemID', id).execute('sp_Inventory_SoftDelete');
}

/* Transactions */
async function listTransactions({ itemId, type, fromDate, toDate, page, pageSize }) {
  const pool = await getPool();
  const r = await pool.request()
    .input('ItemID', itemId || null)
    .input('Type', type || null)
    .input('FromDate', fromDate || null)
    .input('ToDate', toDate || null)
    .input('Page', page || 1)
    .input('PageSize', pageSize || 50)
    .execute('sp_InventoryTransactions_List');
  return { rows: r.recordsets[0], meta: r.recordsets[1][0] || {} };
}
async function createTransaction(data, createdBy) {
  const pool = await getPool();
  const r = await pool.request()
    .input('ItemID', data.ItemID)
    .input('Type', data.Type)
    .input('Qty', data.Qty)
    .input('UnitPrice', data.UnitPrice || 0)
    .input('SupplierID', data.SupplierID || null)
    .input('TxnDate', data.TxnDate || null)
    .input('Notes', data.Notes || null)
    .input('CreatedBy', createdBy)
    .execute('sp_InventoryTransactions_Create');
  return r.recordset[0].TxnID;
}

module.exports = {
  listSuppliers, createSupplier, updateSupplier, deleteSupplier,
  list, createItem, updateItem, deleteItem,
  listTransactions, createTransaction,
};
