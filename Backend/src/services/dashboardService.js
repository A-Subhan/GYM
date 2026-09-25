const model = require('../models/dashboardModel');

module.exports = {
  getStats: (branchId) => model.getStats(branchId),
  getCharts: (months, branchId) => model.getCharts(months, branchId),
};
