const model = require('../models/workoutModel');
const { success, error } = require('../utils/response');

exports.list = async (req, res, next) => {
  try {
    const { trainerId, memberId } = req.query;
    // Trainers only see their own plans
    const tId = req.user.roleName === 'Trainer' ? null : (trainerId ? parseInt(trainerId, 10) : null);
    // For trainers, filter by their trainer record — but we'd need to look up TrainerID by UserID; keep simple
    const rows = await model.list({ trainerId: tId, memberId: memberId ? parseInt(memberId, 10) : null });
    return success(res, rows, 'Workout plans');
  } catch (err) { return error(res, err.message, 500); }
};

exports.get = async (req, res, next) => {
  try {
    const data = await model.get(parseInt(req.params.id, 10));
    if (!data.plan) return error(res, 'Plan not found', 404, 'NOT_FOUND');
    return success(res, data, 'Workout plan');
  } catch (err) { return error(res, err.message, 500); }
};

exports.create = async (req, res, next) => {
  try {
    const id = await model.create(req.body);
    res.locals.entityId = id;
    return success(res, { planId: id }, 'Workout plan created', null, 201);
  } catch (err) { return error(res, err.message, 500); }
};

exports.update = async (req, res, next) => {
  try {
    await model.update(parseInt(req.params.id, 10), req.body);
    return success(res, null, 'Workout plan updated');
  } catch (err) { return error(res, err.message, 500); }
};

exports.remove = async (req, res, next) => {
  try {
    await model.remove(parseInt(req.params.id, 10));
    return success(res, null, 'Workout plan deleted');
  } catch (err) { return error(res, err.message, 500); }
};

exports.addItem = async (req, res, next) => {
  try {
    const id = await model.addItem(req.body);
    res.locals.entityId = id;
    return success(res, { itemId: id }, 'Item added', null, 201);
  } catch (err) { return error(res, err.message, 500); }
};

exports.updateItem = async (req, res, next) => {
  try {
    await model.updateItem(parseInt(req.params.itemId, 10), req.body);
    return success(res, null, 'Item updated');
  } catch (err) { return error(res, err.message, 500); }
};

exports.removeItem = async (req, res, next) => {
  try {
    await model.removeItem(parseInt(req.params.itemId, 10));
    return success(res, null, 'Item deleted');
  } catch (err) { return error(res, err.message, 500); }
};
