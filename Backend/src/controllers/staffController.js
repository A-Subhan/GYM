const model = require('../models/staffModel');
const { success, error, paginate } = require('../utils/response');

exports.departments = async (req, res, next) => {
  try {
    const rows = await model.listDepartments();
    return success(res, rows, 'Departments');
  } catch (err) { return error(res, err.message, 500); }
};

/* Staff tagged as trainers — used by member/workout/diet dropdowns */
exports.listTrainers = async (req, res, next) => {
  try {
    const branchId = req.user.isSuperAdmin
      ? (req.query.BranchID ? parseInt(req.query.BranchID, 10) : null)
      : req.user.branchId;
    const rows = await model.listTrainers(branchId);
    return success(res, rows, 'Trainers list');
  } catch (err) { return error(res, err.message, 500); }
};

exports.list = async (req, res, next) => {
  try {
    const { page, pageSize, search, DepartmentID, Status, IsTrainer } = req.query;
    const branchId = req.user.isSuperAdmin ? (req.query.BranchID ? parseInt(req.query.BranchID, 10) : null) : req.user.branchId;
    const isTrainer = IsTrainer === undefined || IsTrainer === ''
      ? null
      : (IsTrainer === 'true' || IsTrainer === '1' ? 1 : 0);
    const { rows, total } = await model.list({
      page: parseInt(page, 10) || 1,
      pageSize: parseInt(pageSize, 10) || 20,
      search: search || null,
      branchId,
      departmentId: DepartmentID ? parseInt(DepartmentID, 10) : null,
      status: Status || null,
      isTrainer,
    });
    return paginate(res, rows, total, page || 1, pageSize || 20, 'Staff list');
  } catch (err) { return error(res, err.message, 500); }
};

exports.get = async (req, res, next) => {
  try {
    const row = await model.get(parseInt(req.params.id, 10));
    if (!row) return error(res, 'Staff not found', 404, 'NOT_FOUND');
    return success(res, row, 'Staff details');
  } catch (err) { return error(res, err.message, 500); }
};

exports.create = async (req, res, next) => {
  try {
    const data = { ...req.body };
    if (!req.user.isSuperAdmin) data.BranchID = req.user.branchId;
    if (!data.BranchID) {
      return error(res, 'BranchID is required', 400, 'BAD_REQUEST');
    }
    const result = await model.create(data, req.user.userId);
    res.locals.entityId = result.StaffID;
    return success(res, { staffId: result.StaffID, staffCode: result.StaffCode }, 'Staff created', null, 201);
  } catch (err) { return error(res, err.message, 500); }
};

exports.update = async (req, res, next) => {
  try {
    await model.update(parseInt(req.params.id, 10), req.body, req.user.userId);
    return success(res, null, 'Staff updated');
  } catch (err) { return error(res, err.message, 500); }
};

exports.remove = async (req, res, next) => {
  try {
    await model.softDelete(parseInt(req.params.id, 10), req.user.userId);
    return success(res, null, 'Staff deleted');
  } catch (err) { return error(res, err.message, 500); }
};

/* Attendance */
exports.listAttendance = async (req, res, next) => {
  try {
    const { staffId, fromDate, toDate } = req.query;
    const rows = await model.listAttendance({
      staffId: staffId ? parseInt(staffId, 10) : null,
      fromDate: fromDate || null,
      toDate: toDate || null,
    });
    return success(res, rows, 'Staff attendance');
  } catch (err) { return error(res, err.message, 500); }
};

exports.markAttendance = async (req, res, next) => {
  try {
    await model.markAttendance(req.body);
    res.locals.entityId = req.body.StaffID;
    return success(res, null, 'Attendance marked', null, 201);
  } catch (err) { return error(res, err.message, 500); }
};

/* Leaves */
exports.listLeaves = async (req, res, next) => {
  try {
    const { staffId, status } = req.query;
    const rows = await model.listLeaves({
      staffId: staffId ? parseInt(staffId, 10) : null,
      status: status || null,
    });
    return success(res, rows, 'Staff leaves');
  } catch (err) { return error(res, err.message, 500); }
};

exports.createLeave = async (req, res, next) => {
  try {
    const id = await model.createLeave(req.body);
    res.locals.entityId = id;
    return success(res, { leaveId: id }, 'Leave requested', null, 201);
  } catch (err) { return error(res, err.message, 500); }
};

exports.updateLeaveStatus = async (req, res, next) => {
  try {
    await model.updateLeaveStatus(parseInt(req.params.id, 10), req.body.Status, req.user.userId);
    return success(res, null, 'Leave status updated');
  } catch (err) { return error(res, err.message, 500); }
};
