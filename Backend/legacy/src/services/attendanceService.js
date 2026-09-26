const model = require('../models/attendanceModel');

module.exports = {
  list: (params) => model.list(params),
  checkIn: (data) => model.checkIn(data),
  checkOut: (id) => model.checkOut(id),
  todayCount: (b) => model.todayCount(b),
};
