const model = require('../models/reportModel');
const { success, error } = require('../utils/response');

function getBranchId(req) {
  return req.user.isSuperAdmin ? (req.query.branchId ? parseInt(req.query.branchId, 10) : null) : req.user.branchId;
}

exports.members = async (req, res, next) => {
  try {
    const rows = await model.members({
      branchId: getBranchId(req),
      status: req.query.status || null,
      fromDate: req.query.fromDate || null,
      toDate: req.query.toDate || null,
    });
    return success(res, rows, 'Members report');
  } catch (err) { return error(res, err.message, 500); }
};

exports.attendance = async (req, res, next) => {
  try {
    const rows = await model.attendance({
      branchId: getBranchId(req),
      fromDate: req.query.fromDate || null,
      toDate: req.query.toDate || null,
    });
    return success(res, rows, 'Attendance report');
  } catch (err) { return error(res, err.message, 500); }
};

exports.payments = async (req, res, next) => {
  try {
    const rows = await model.payments({
      branchId: getBranchId(req),
      fromDate: req.query.fromDate || null,
      toDate: req.query.toDate || null,
      methodId: req.query.methodId ? parseInt(req.query.methodId, 10) : null,
    });
    return success(res, rows, 'Payments report');
  } catch (err) { return error(res, err.message, 500); }
};

exports.salary = async (req, res, next) => {
  try {
    const rows = await model.salary({
      branchId: getBranchId(req),
      month: req.query.month ? parseInt(req.query.month, 10) : null,
      year: req.query.year ? parseInt(req.query.year, 10) : null,
    });
    return success(res, rows, 'Salary report');
  } catch (err) { return error(res, err.message, 500); }
};

exports.equipment = async (req, res, next) => {
  try {
    const rows = await model.equipment({
      branchId: getBranchId(req),
      status: req.query.status || null,
    });
    return success(res, rows, 'Equipment report');
  } catch (err) { return error(res, err.message, 500); }
};

exports.inventory = async (req, res, next) => {
  try {
    const rows = await model.inventory({
      branchId: getBranchId(req),
      category: req.query.category || null,
    });
    return success(res, rows, 'Inventory report');
  } catch (err) { return error(res, err.message, 500); }
};
