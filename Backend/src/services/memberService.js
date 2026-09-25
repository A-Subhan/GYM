const memberModel = require('../models/memberModel');
const membershipModel = require('../models/membershipModel');

module.exports = {
  list: (params) => memberModel.list(params),
  get: (id) => memberModel.get(id),
  create: (data, createdBy) => memberModel.create(data, createdBy),
  update: (id, data, updatedBy) => memberModel.update(id, data, updatedBy),
  delete: (id, deletedBy) => memberModel.softDelete(id, deletedBy),
  getPayments: (id) => memberModel.getPayments(id),
  getAttendance: (id, f, t) => memberModel.getAttendance(id, f, t),
  getMemberships: (id) => memberModel.getMemberships(id),
  getProgress: (id) => memberModel.getProgress(id),
  assignMembership: (data, createdBy) =>
    membershipModel.createMemberMembership(data, createdBy),
};
