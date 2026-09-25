const Joi = require('joi');

const create = Joi.object({
  Username: Joi.string().alphanum().min(3).max(50).required(),
  Email: Joi.string().email().allow('', null).optional(),
  FullName: Joi.string().min(3).max(150).required(),
  Password: Joi.string().min(8).max(100).required(),
  RoleID: Joi.number().integer().required(),
  BranchID: Joi.number().integer().allow(null).optional(),
  Phone: Joi.string().max(30).allow('', null).optional(),
  Photo: Joi.string().max(500).allow('', null).optional(),
  MustChangePassword: Joi.boolean().default(false),
});

const update = Joi.object({
  Email: Joi.string().email().allow('', null).optional(),
  FullName: Joi.string().min(3).max(150).optional(),
  RoleID: Joi.number().integer().optional(),
  BranchID: Joi.number().integer().allow(null).optional(),
  Phone: Joi.string().max(30).allow('', null).optional(),
  Photo: Joi.string().max(500).allow('', null).optional(),
  IsActive: Joi.boolean().optional(),
});

const list = Joi.object({
  page: Joi.number().integer().min(1).default(1),
  pageSize: Joi.number().integer().min(1).max(200).default(20),
  search: Joi.string().allow('', null).optional(),
  RoleID: Joi.number().integer().allow(null).optional(),
  BranchID: Joi.number().integer().allow(null).optional(),
});

module.exports = { create, update, list };
