const model = require('../models/equipmentModel');
const { success, error } = require('../utils/response');

exports.list = async (req, res, next) => {
  try {
    const { page, pageSize, status, search } = req.query;
    const branchId = req.user.isSuperAdmin ? (req.query.branchId ? parseInt(req.query.branchId, 10) : null) : req.user.branchId;
    const { rows, meta } = await model.list({
      page: parseInt(page, 10) || 1,
      pageSize: parseInt(pageSize, 10) || 50,
      branchId,
      status: status || null,
      search: search || null,
    });
    return res.status(200).json({ success: true, data: rows, message: 'Equipment list', meta: { ...meta, page: parseInt(page, 10) || 1, pageSize: parseInt(pageSize, 10) || 50 } });
  } catch (err) { return error(res, err.message, 500); }
};

exports.get = async (req, res, next) => {
  try {
    const row = await model.get(parseInt(req.params.id, 10));
    if (!row) return error(res, 'Equipment not found', 404, 'NOT_FOUND');
    return success(res, row, 'Equipment details');
  } catch (err) { return error(res, err.message, 500); }
};

exports.create = async (req, res, next) => {
  try {
    const data = { ...req.body };
    if (!req.user.isSuperAdmin) data.BranchID = req.user.branchId;
    const id = await model.create(data, req.user.userId);
    res.locals.entityId = id;
    return success(res, { equipmentId: id }, 'Equipment created', null, 201);
  } catch (err) { return error(res, err.message, 500); }
};

exports.update = async (req, res, next) => {
  try {
    await model.update(parseInt(req.params.id, 10), req.body);
    return success(res, null, 'Equipment updated');
  } catch (err) { return error(res, err.message, 500); }
};

exports.remove = async (req, res, next) => {
  try {
    await model.softDelete(parseInt(req.params.id, 10));
    return success(res, null, 'Equipment deleted');
  } catch (err) { return error(res, err.message, 500); }
};

exports.listMaintenance = async (req, res, next) => {
  try {
    const { equipmentId } = req.query;
    const branchId = req.user.isSuperAdmin ? (req.query.branchId ? parseInt(req.query.branchId, 10) : null) : req.user.branchId;
    const rows = await model.listMaintenance({
      equipmentId: equipmentId ? parseInt(equipmentId, 10) : null,
      branchId,
    });
    return success(res, rows, 'Maintenance records');
  } catch (err) { return error(res, err.message, 500); }
};

exports.createMaintenance = async (req, res, next) => {
  try {
    const id = await model.createMaintenance(req.body, req.user.userId);
    res.locals.entityId = id;
    return success(res, { maintId: id }, 'Maintenance record created', null, 201);
  } catch (err) { return error(res, err.message, 500); }
};

exports.completeMaintenance = async (req, res, next) => {
  try {
    await model.completeMaintenance(parseInt(req.params.id, 10));
    return success(res, null, 'Maintenance completed');
  } catch (err) { return error(res, err.message, 500); }
};
