const model = require('../models/payrollModel');
const { success, error, paginate } = require('../utils/response');

exports.list = async (req, res, next) => {
  try {
    const { page, pageSize, staffId, month, year, status } = req.query;
    const branchId = req.user.isSuperAdmin ? (req.query.branchId ? parseInt(req.query.branchId, 10) : null) : req.user.branchId;
    const { rows, total, totalNet } = await model.list({
      page: parseInt(page, 10) || 1,
      pageSize: parseInt(pageSize, 10) || 20,
      staffId: staffId ? parseInt(staffId, 10) : null,
      branchId,
      month: month ? parseInt(month, 10) : null,
      year: year ? parseInt(year, 10) : null,
      status: status || null,
    });
    return res.status(200).json({
      success: true, data: rows, message: 'Payroll list',
      meta: { page: parseInt(page, 10) || 1, pageSize: parseInt(pageSize, 10) || 20, total, totalNet },
    });
  } catch (err) { return error(res, err.message, 500); }
};

exports.get = async (req, res, next) => {
  try {
    const row = await model.get(parseInt(req.params.id, 10));
    if (!row) return error(res, 'Payroll not found', 404, 'NOT_FOUND');
    return success(res, row, 'Payroll details');
  } catch (err) { return error(res, err.message, 500); }
};

exports.generate = async (req, res, next) => {
  try {
    const id = await model.generate(req.body, req.user.userId);
    res.locals.entityId = id;
    return success(res, { payrollId: id }, 'Payroll generated', null, 201);
  } catch (err) { return error(res, err.message, 500); }
};

exports.generateAll = async (req, res, next) => {
  try {
    const data = { ...req.body };
    if (!req.user.isSuperAdmin) data.BranchID = req.user.branchId;
    const count = await model.generateAll(data, req.user.userId);
    return success(res, { insertedCount: count }, `${count} payroll records generated`, null, 201);
  } catch (err) { return error(res, err.message, 500); }
};

exports.markPaid = async (req, res, next) => {
  try {
    await model.markPaid(parseInt(req.params.id, 10));
    return success(res, null, 'Marked as paid');
  } catch (err) { return error(res, err.message, 500); }
};

exports.update = async (req, res, next) => {
  try {
    await model.update(parseInt(req.params.id, 10), req.body);
    return success(res, null, 'Payroll updated');
  } catch (err) { return error(res, err.message, 500); }
};
