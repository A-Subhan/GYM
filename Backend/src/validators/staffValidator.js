const Joi = require('joi');

const create = Joi.object({
  BranchID: Joi.number()
    .integer()
    .allow('', null)
    .optional()
    .messages({
      'number.base': 'Branch must be valid'
    }),

  DepartmentID: Joi.number()
    .integer()
    .required()
    .messages({
      'any.required': 'Department is required',
      'number.base': 'Department must be valid'
    }),

  UserID: Joi.number()
    .integer()
    .allow('', null)
    .optional(),

  FullName: Joi.string()
    .trim()
    .min(3)
    .max(50)
    .required()
    .messages({
      'string.empty': 'Full Name is required',
      'string.min': 'Full Name must contain at least 3 characters',
      'string.max': 'Full Name cannot exceed 50 characters'
    }),

  FatherName: Joi.string()
    .trim()
    .max(50)
    .allow('', null)
    .optional()
    .messages({
      'string.max': 'Father Name cannot exceed 50 characters'
    }),

  CNIC: Joi.string()
    .trim()
    .max(20)
    .allow('', null)
    .optional(),

  Mobile: Joi.string()
    .trim()
    .max(30)
    .allow('', null)
    .optional(),

  Email: Joi.string()
    .trim()
    .email()
    .max(150)
    .allow('', null)
    .optional()
    .messages({
      'string.email': 'Please enter a valid email address'
    }),

  Address: Joi.string()
    .trim()
    .max(200)
    .allow('', null)
    .optional()
    .messages({
      'string.max': 'Address cannot exceed 200 characters'
    }),

  Photo: Joi.string()
    .max(500)
    .allow('', null)
    .optional(),

  JoiningDate: Joi.date()
    .required()
    .messages({
      'date.base': 'Joining Date must be a valid date',
      'any.required': 'Joining Date is required'
    }),

  Designation: Joi.string()
    .trim()
    .max(30)
    .required()
    .messages({
      'string.empty': 'Designation is required',
      'string.max': 'Designation cannot exceed 30 characters',
      'any.required': 'Designation is required'
    }),

  BaseSalary: Joi.number()
    .precision(2)
    .min(0)
    .max(9999999)
    .allow('', null)
    .optional()
    .messages({
      'number.max': 'Salary cannot exceed 9999999'
    }),

  Status: Joi.string()
    .valid('Active', 'OnLeave', 'Resigned', 'Terminated')
    .optional(),

  /* Extra trainer info — used when the designation is Trainer */
  Specialization: Joi.string()
    .trim()
    .max(200)
    .allow('', null)
    .optional(),

  Experience: Joi.string()
    .trim()
    .max(100)
    .allow('', null)
    .optional()
});

const update = Joi.object({
  BranchID: Joi.number()
    .integer()
    .allow('', null)
    .optional(),

  DepartmentID: Joi.number()
    .integer()
    .optional(),

  UserID: Joi.number()
    .integer()
    .allow('', null)
    .optional(),

  FullName: Joi.string()
    .trim()
    .min(3)
    .max(50)
    .optional(),

  FatherName: Joi.string()
    .trim()
    .max(50)
    .allow('', null)
    .optional(),

  CNIC: Joi.string()
    .trim()
    .max(20)
    .allow('', null)
    .optional(),

  Mobile: Joi.string()
    .trim()
    .max(30)
    .allow('', null)
    .optional(),

  Email: Joi.string()
    .trim()
    .email()
    .max(150)
    .allow('', null)
    .optional()
    .messages({
      'string.email': 'Please enter a valid email address'
    }),

  Address: Joi.string()
    .trim()
    .max(200)
    .allow('', null)
    .optional(),

  Photo: Joi.string()
    .max(500)
    .allow('', null)
    .optional(),

  JoiningDate: Joi.date()
    .optional(),

  Designation: Joi.string()
    .trim()
    .max(30)
    .optional(),

  BaseSalary: Joi.number()
    .precision(2)
    .min(0)
    .max(9999999)
    .allow('', null)
    .optional(),

  Status: Joi.string()
    .valid('Active', 'OnLeave', 'Resigned', 'Terminated')
    .optional(),

  Specialization: Joi.string()
    .trim()
    .max(200)
    .allow('', null)
    .optional(),

  Experience: Joi.string()
    .trim()
    .max(100)
    .allow('', null)
    .optional()
});

module.exports = {
  create,
  update
};
