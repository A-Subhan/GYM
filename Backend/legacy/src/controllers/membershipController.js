const service = require('../services/membershipService');
const { success, error } = require('../utils/response');

/* ----------- Plans ----------- */

exports.listPlans = async (req, res, next) => {
  try {
    const isActive =
      req.query.isActive === undefined
        ? null
        : req.query.isActive === 'true';

    const rows = await service.listPlans(isActive);

    return success(res, rows, 'Membership plans');
  } catch (err) {
    return error(res, err.message, 500);
  }
};

exports.createPlan = async (req, res, next) => {
  try {
    const id = await service.createPlan(
      req.body,
      req.user.userId
    );

    res.locals.entityId = id;

    return success(
      res,
      { planId: id },
      'Plan created',
      null,
      201
    );
  } catch (err) {
    return error(res, err.message, 500);
  }
};

exports.updatePlan = async (req, res, next) => {
  try {
    await service.updatePlan(
      parseInt(req.params.id, 10),
      req.body,
      req.user.userId
    );

    return success(res, null, 'Plan updated');
  } catch (err) {
    return error(res, err.message, 500);
  }
};

exports.deletePlan = async (req, res, next) => {
  try {
    await service.deletePlan(
      parseInt(req.params.id, 10),
      req.user.userId
    );

    return success(res, null, 'Plan deleted');
  } catch (err) {
    if (
      err.message ===
      'This membership plan is currently in use and cannot be deleted.'
    ) {
      return error(res, err.message, 409);
    }

    if (
      err.message ===
      'Membership plan not found.'
    ) {
      return error(res, err.message, 404);
    }

    return error(res, err.message, 500);
  }
};
