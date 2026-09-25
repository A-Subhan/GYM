const model = require('../models/dietModel');
const { success, error } = require('../utils/response');

exports.list = async (req, res, next) => {
  try {
    const { trainerId, memberId } = req.query;
    const rows = await model.list({
      trainerId: trainerId ? parseInt(trainerId, 10) : null,
      memberId: memberId ? parseInt(memberId, 10) : null,
    });
    return success(res, rows, 'Diet plans');
  } catch (err) { return error(res, err.message, 500); }
};

exports.get = async (req, res, next) => {
  try {
    const data = await model.get(parseInt(req.params.id, 10));
    if (!data.plan) return error(res, 'Plan not found', 404, 'NOT_FOUND');
    return success(res, data, 'Diet plan');
  } catch (err) { return error(res, err.message, 500); }
};

exports.create = async (req, res, next) => {
  try {
    const id = await model.create(req.body);
    res.locals.entityId = id;
    return success(res, { planId: id }, 'Diet plan created', null, 201);
  } catch (err) { return error(res, err.message, 500); }
};

exports.update = async (req, res, next) => {
  try {
    await model.update(parseInt(req.params.id, 10), req.body);
    return success(res, null, 'Diet plan updated');
  } catch (err) { return error(res, err.message, 500); }
};

exports.remove = async (req, res, next) => {
  try {
    await model.remove(parseInt(req.params.id, 10));
    return success(res, null, 'Diet plan deleted');
  } catch (err) { return error(res, err.message, 500); }
};

exports.addItem = async (req, res, next) => {
  try {
    const id = await model.addItem({ ...req.body, PlanID: parseInt(req.params.id, 10) });
    res.locals.entityId = id;
    return success(res, { itemId: id }, 'Item added', null, 201);
  } catch (err) { return error(res, err.message, 500); }
};

exports.removeItem = async (req, res, next) => {
  try {
    await model.removeItem(parseInt(req.params.itemId, 10));
    return success(res, null, 'Item deleted');
  } catch (err) { return error(res, err.message, 500); }
};
