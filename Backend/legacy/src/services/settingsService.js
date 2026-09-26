const model = require('../models/settingsModel');

module.exports = {
  getAll: () => model.getAll(),
  get: (k) => model.get(k),
  getByCategory: (c) => model.getByCategory(c),
  upsert: (k, v, c, u) => model.upsert(k, v, c, u),
  bulkUpsert: (items, u) => model.bulkUpsert(items, u),
};
