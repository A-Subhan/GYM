const model = require('../models/auditModel');
const { success, error, paginate } = require('../utils/response');

exports.list = async (req, res, next) => {
  try {
    const { page, pageSize, userId, module, action, fromDate, toDate } = req.query;
    const { rows, total } = await model.list({
      page: parseInt(page, 10) || 1,
      pageSize: parseInt(pageSize, 10) || 50,
      userId: userId ? parseInt(userId, 10) : null,
      module: module || null,
      action: action || null,
      fromDate: fromDate || null,
      toDate: toDate || null,
    });
    return paginate(res, rows, total, page || 1, pageSize || 50, 'Audit logs');
  } catch (err) { return error(res, err.message, 500); }
};
