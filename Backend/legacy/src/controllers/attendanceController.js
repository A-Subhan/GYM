const service = require('../services/attendanceService');
const { success, error, paginate } = require('../utils/response');
const { getClientIp } = require('../utils/helpers');

exports.list = async (req, res, next) => {
  try {
    const { page, pageSize, memberId, date, fromDate, toDate } = req.query;
    const branchId = req.user.isSuperAdmin ? (req.query.branchId ? parseInt(req.query.branchId, 10) : null) : req.user.branchId;
    const { rows, total } = await service.list({
      page: parseInt(page, 10) || 1,
      pageSize: parseInt(pageSize, 10) || 50,
      branchId,
      memberId: memberId ? parseInt(memberId, 10) : null,
      date: date || null,
      fromDate: fromDate || null,
      toDate: toDate || null,
    });
    return paginate(res, rows, total, page || 1, pageSize || 50, 'Attendance list');
  } catch (err) { return error(res, err.message, 500); }
};

exports.checkIn = async (req, res, next) => {
  try {
    const { memberId, method } = req.body;
    if (!memberId) return error(res, 'memberId required', 400, 'BAD_REQUEST');
    const branchId = req.user.isSuperAdmin ? (req.body.branchId || req.user.branchId) : req.user.branchId;
    const id = await service.checkIn({
      memberId: parseInt(memberId, 10),
      branchId,
      method: method || 'Manual',
      ipAddress: getClientIp(req),
      createdBy: req.user.userId,
    });
    res.locals.entityId = id;
    return success(res, { attendanceId: id }, 'Checked in', null, 201);
  } catch (err) {
    if (/Member not found/i.test(err.message)) {
      return error(res, 'Member not found. Please select a valid member.', 404, 'NOT_FOUND');
    }
    return error(res, err.message, 500);
  }
};

exports.checkOut = async (req, res, next) => {
  try {
    const { id } = req.params;
    await service.checkOut(parseInt(id, 10));
    return success(res, null, 'Checked out');
  } catch (err) { return error(res, err.message, 500); }
};

exports.todayCount = async (req, res, next) => {
  try {
    const branchId = req.user.isSuperAdmin ? (req.query.branchId ? parseInt(req.query.branchId, 10) : null) : req.user.branchId;
    const count = await service.todayCount(branchId);
    return success(res, { count }, "Today's attendance count");
  } catch (err) { return error(res, err.message, 500); }
};
