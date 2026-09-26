const service = require('../services/dashboardService');
const { success, error } = require('../utils/response');

exports.stats = async (req, res, next) => {
  try {
    // Non-super-admins always see only their branch
    const branchId = req.user.isSuperAdmin ? (req.query.branchId ? parseInt(req.query.branchId, 10) : null) : req.user.branchId;
    const stats = await service.getStats(branchId);
    return success(res, stats, 'Dashboard stats');
  } catch (err) { return error(res, err.message, 500); }
};

exports.charts = async (req, res, next) => {
  try {
    const months = req.query.months ? Math.min(12, Math.max(1, parseInt(req.query.months, 10))) : 6;
    const branchId = req.user.isSuperAdmin ? (req.query.branchId ? parseInt(req.query.branchId, 10) : null) : req.user.branchId;
    const charts = await service.getCharts(months, branchId);
    return success(res, charts, 'Dashboard charts');
  } catch (err) { return error(res, err.message, 500); }
};
