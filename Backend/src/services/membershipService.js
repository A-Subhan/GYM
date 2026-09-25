const model = require('../models/membershipModel');

module.exports = {
  listPlans: (isActive) => model.listPlans(isActive),

  createPlan: (data, userId) =>
    model.createPlan(data, userId),

  updatePlan: (id, data, userId) =>
    model.updatePlan(id, data, userId),

  deletePlan: (id, userId) =>
    model.deletePlan(id, userId),

  createMemberMembership: (data, userId) =>
    model.createMemberMembership(data, userId),
};
