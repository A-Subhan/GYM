const Joi = require('joi');

/* ----------- Master definitions ----------- */

const createDefinition = Joi.object({
  Name: Joi.string()
    .trim()
    .min(2)
    .max(50)
    .required()
    .messages({
      'string.empty': 'Master name is required',
      'string.max': 'Master name cannot exceed 50 characters'
    }),

  /* Optional — auto-generated when omitted */
  MasterCode: Joi.string()
    .trim()
    .pattern(/^\d{2,5}$/)
    .allow('', null)
    .optional()
    .messages({
      'string.pattern.base': 'Master code must be 2-5 digits (e.g. 04)'
    }),

  Scope: Joi.string()
    .valid('Global', 'Branch')
    .default('Global')
});

const updateDefinition = Joi.object({
  Name: Joi.string()
    .trim()
    .min(2)
    .max(50)
    .optional(),

  Scope: Joi.string()
    .valid('Global', 'Branch')
    .optional(),

  IsActive: Joi.boolean()
    .optional()
});

/* ----------- Master items ----------- */

const createItem = Joi.object({
  Name: Joi.string()
    .trim()
    .min(1)
    .max(50)
    .required()
    .messages({
      'string.empty': 'Name is required',
      'string.max': 'Name cannot exceed 50 characters'
    }),

  /* Required only for Branch-scope masters (forced for non-super-admins) */
  BranchID: Joi.number()
    .integer()
    .allow('', null)
    .optional()
});

const updateItem = Joi.object({
  Name: Joi.string()
    .trim()
    .min(1)
    .max(50)
    .required()
    .messages({
      'string.empty': 'Name is required',
      'string.max': 'Name cannot exceed 50 characters'
    })
});

const setStatus = Joi.object({
  IsActive: Joi.boolean()
    .required()
    .messages({
      'any.required': 'IsActive is required',
      'boolean.base': 'IsActive must be true or false'
    })
});

const listItems = Joi.object({
  search: Joi.string()
    .trim()
    .allow('', null)
    .optional(),

  status: Joi.string()
    .valid('active', 'inactive')
    .allow('', null)
    .optional(),

  BranchID: Joi.number()
    .integer()
    .allow('', null)
    .optional(),

  page: Joi.number()
    .integer()
    .min(1)
    .default(1),

  pageSize: Joi.number()
    .integer()
    .min(1)
    .max(200)
    .default(20)
});

module.exports = {
  createDefinition,
  updateDefinition,
  createItem,
  updateItem,
  setStatus,
  listItems
};
