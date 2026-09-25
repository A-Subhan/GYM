const service = require('../services/settingsService');
const { success, error } = require('../utils/response');

exports.list = async (req, res, next) => {
  try {
    const rows = await service.getAll();
    // Convert to key-value object
    const obj = {};
    rows.forEach((r) => { obj[r.Key] = r.Value; });
    return success(res, { items: rows, map: obj }, 'Settings');
  } catch (err) { return error(res, err.message, 500); }
};

exports.getByCategory = async (req, res, next) => {
  try {
    const rows = await service.getByCategory(req.params.category);
    return success(res, rows, 'Settings by category');
  } catch (err) { return error(res, err.message, 500); }
};

exports.update = async (req, res, next) => {
  try {
    const { key, value, category } = req.body;
    if (!key) return error(res, 'key is required', 400, 'BAD_REQUEST');
    await service.upsert(key, value, category, req.user.userId);
    res.locals.entityId = null;
    res.locals.auditDetails = { key, value, category };
    return success(res, null, 'Setting updated');
  } catch (err) { return error(res, err.message, 500); }
};

exports.bulkUpdate = async (req, res, next) => {
  try {
    const { items } = req.body;
    if (!Array.isArray(items)) return error(res, 'items must be an array', 400, 'BAD_REQUEST');
    await service.bulkUpsert(items, req.user.userId);
    res.locals.auditDetails = { count: items.length };
    return success(res, null, `${items.length} settings updated`);
  } catch (err) { return error(res, err.message, 500); }
};
