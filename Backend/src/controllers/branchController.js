const service = require('../services/branchService');
const { success, error } = require('../utils/response');

exports.list = async (req, res, next) => {
  try {
    const isActive = req.query.isActive === undefined ? null : req.query.isActive === 'true';
    const rows = await service.list(isActive);
    return success(res, rows, 'Branches list');
  } catch (err) { return error(res, err.message, 500); }
};

exports.get = async (req, res, next) => {
  try {
    const row = await service.get(parseInt(req.params.id, 10));
    if (!row) return error(res, 'Branch not found', 404, 'NOT_FOUND');
    return success(res, row, 'Branch details');
  } catch (err) { return error(res, err.message, 500); }
};

exports.create = async (req, res, next) => {
  try {
    const id = await service.create(req.body, req.user.userId);
    res.locals.entityId = id;
    return success(res, { branchId: id }, 'Branch created', null, 201);
  } catch (err) {
    if (/duplicate/i.test(err.message)) return error(res, 'Branch code already exists', 409, 'DUPLICATE');
    return error(res, err.message, 500);
  }
};

exports.update = async (req, res, next) => {
  try {
    await service.update(parseInt(req.params.id, 10), req.body, req.user.userId);
    return success(res, null, 'Branch updated');
  } catch (err) { return error(res, err.message, 500); }
};

exports.remove = async (req, res, next) => {
  try {
    await service.delete(parseInt(req.params.id, 10));
    return success(res, null, 'Branch deleted');
  } catch (err) { return error(res, err.message, 500); }
};
