const Joi = require('joi');

const createBranch = Joi.object({
  Code: Joi.string().min(2).max(20).required(),
  Name: Joi.string().min(2).max(150).required(),
  Address: Joi.string().max(500).allow('', null).optional(),
  City: Joi.string().max(100).allow('', null).optional(),
  Phone: Joi.string().max(30).allow('', null).optional(),
  Email: Joi.string().email().allow('', null).optional(),
  ManagerName: Joi.string().max(150).allow('', null).optional(),
});

const updateBranch = Joi.object({
  Code: Joi.string().min(2).max(20).optional(),
  Name: Joi.string().min(2).max(150).optional(),
  Address: Joi.string().max(500).allow('', null).optional(),
  City: Joi.string().max(100).allow('', null).optional(),
  Phone: Joi.string().max(30).allow('', null).optional(),
  Email: Joi.string().email().allow('', null).optional(),
  ManagerName: Joi.string().max(150).allow('', null).optional(),
  IsActive: Joi.boolean().optional(),
});

module.exports = { createBranch, updateBranch };
