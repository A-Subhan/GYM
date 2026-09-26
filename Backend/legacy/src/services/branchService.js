const branchModel = require('../models/branchModel');

module.exports = {
  list: (isActive) => branchModel.list(isActive),
  get: (id) => branchModel.get(id),
  create: (data, createdBy) => branchModel.create(data, createdBy),
  update: (id, data, updatedBy) => branchModel.update(id, data, updatedBy),
  delete: (id) => branchModel.softDelete(id),
};
