const model = require('../models/inventoryModel');
const { success, error } = require('../utils/response');

/* Suppliers */
exports.listSuppliers = async (req, res, next) => {
  try {
    const isActive = req.query.isActive === undefined ? null : req.query.isActive === 'true';
    const rows = await model.listSuppliers(isActive);
    return success(res, rows, 'Suppliers');
  } catch (err) { return error(res, err.message, 500); }
};
exports.createSupplier = async (req, res, next) => {
  try {
    const id = await model.createSupplier(req.body);
    res.locals.entityId = id;
    return success(res, { supplierId: id }, 'Supplier created', null, 201);
  } catch (err) { return error(res, err.message, 500); }
};
exports.updateSupplier = async (req, res, next) => {
  try {
    await model.updateSupplier(parseInt(req.params.id, 10), req.body);
    return success(res, null, 'Supplier updated');
  } catch (err) { return error(res, err.message, 500); }
};
exports.deleteSupplier = async (req, res, next) => {
  try {
    await model.deleteSupplier(parseInt(req.params.id, 10));
    return success(res, null, 'Supplier deactivated');
  } catch (err) { return error(res, err.message, 500); }
};

/* Items */
exports.list = async (req, res, next) => {
  try {
    const { page, pageSize, category, search, lowStock } = req.query;
    const branchId = req.user.isSuperAdmin ? (req.query.branchId ? parseInt(req.query.branchId, 10) : null) : req.user.branchId;
    const { rows, meta } = await model.list({
      page: parseInt(page, 10) || 1,
      pageSize: parseInt(pageSize, 10) || 50,
      branchId,
      category: category || null,
      search: search || null,
      lowStockOnly: lowStock === 'true',
    });
    return res.status(200).json({ success: true, data: rows, message: 'Inventory items', meta: { ...meta, page: parseInt(page, 10) || 1, pageSize: parseInt(pageSize, 10) || 50 } });
  } catch (err) { return error(res, err.message, 500); }
};
exports.createItem = async (req, res, next) => {
  try {
    const data = { ...req.body };
    if (!req.user.isSuperAdmin) data.BranchID = req.user.branchId;
    const id = await model.createItem(data, req.user.userId);
    res.locals.entityId = id;
    return success(res, { itemId: id }, 'Item created', null, 201);
  } catch (err) { return error(res, err.message, 500); }
};
exports.updateItem = async (req, res, next) => {
  try {
    await model.updateItem(parseInt(req.params.id, 10), req.body);
    return success(res, null, 'Item updated');
  } catch (err) { return error(res, err.message, 500); }
};
exports.deleteItem = async (req, res, next) => {
  try {
    await model.deleteItem(parseInt(req.params.id, 10));
    return success(res, null, 'Item deleted');
  } catch (err) { return error(res, err.message, 500); }
};

/* Transactions */
exports.listTransactions = async (req, res, next) => {
  try {
    const { itemId, type, fromDate, toDate, page, pageSize } = req.query;
    const { rows, meta } = await model.listTransactions({
      itemId: itemId ? parseInt(itemId, 10) : null,
      type: type || null,
      fromDate: fromDate || null,
      toDate: toDate || null,
      page: parseInt(page, 10) || 1,
      pageSize: parseInt(pageSize, 10) || 50,
    });
    return res.status(200).json({ success: true, data: rows, message: 'Transactions', meta: { ...meta, page: parseInt(page, 10) || 1, pageSize: parseInt(pageSize, 10) || 50 } });
  } catch (err) { return error(res, err.message, 500); }
};
exports.createTransaction = async (req, res, next) => {
  try {
    const id = await model.createTransaction(req.body, req.user.userId);
    res.locals.entityId = id;
    return success(res, { txnId: id }, 'Transaction recorded', null, 201);
  } catch (err) { return error(res, err.message, 500); }
};
