const Joi = require('joi');

const createPlan = Joi.object({
  Name: Joi.string().min(2).max(60).required(),

  DurationMonths: Joi.number()
    .integer()
    .min(0)
    .max(120)
    .required(),

  Price: Joi.number()
    .precision(2)
    .min(0)
    .max(9999999)
    .required(),

  JoiningFee: Joi.number()
    .precision(2)
    .min(0)
    .max(9999999)
    .default(0),

  Discount: Joi.number()
    .precision(2)
    .min(0)
    .max(100)
    .default(0),

  Description: Joi.string()
    .max(200)
    .allow('', null)
    .optional(),

  IsActive: Joi.boolean()
    .default(true)
});

const updatePlan = Joi.object({
  Name: Joi.string()
    .min(2)
    .max(60)
    .optional(),

  DurationMonths: Joi.number()
    .integer()
    .min(0)
    .max(120)
    .optional(),

  Price: Joi.number()
    .precision(2)
    .min(0)
    .max(9999999)
    .optional(),

  JoiningFee: Joi.number()
    .precision(2)
    .min(0)
    .max(9999999)
    .optional(),

  Discount: Joi.number()
    .precision(2)
    .min(0)
    .max(100)
    .optional(),

  Description: Joi.string()
    .max(200)
    .allow('', null)
    .optional(),

  IsActive: Joi.boolean()
    .optional()
});

const createMemberMembership = Joi.object({
  MemberID: Joi.number()
    .integer()
    .required(),

  PlanID: Joi.number()
    .integer()
    .required(),

  StartDate: Joi.date()
    .required(),

  AmountPaid: Joi.number()
    .precision(2)
    .min(0)
    .max(9999999)
    .default(0),

  Notes: Joi.string()
    .max(500)
    .allow('', null)
    .optional()
});

module.exports = {
  createPlan,
  updatePlan,
  createMemberMembership
};