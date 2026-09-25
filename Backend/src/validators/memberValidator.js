const Joi = require('joi');

const namePattern = /^[A-Za-z0-9 ]+$/;
const digitsPattern = /^\d+$/;

const commonFields = {
  FullName: Joi.string()
    .trim()
    .min(3)
    .max(50)
    .pattern(namePattern)
    .required()
    .messages({
      'string.empty': 'Full Name is required',
      'string.min': 'Full Name must contain at least 3 characters',
      'string.max': 'Full Name cannot exceed 50 characters',
      'string.pattern.base':
        'Full Name may contain only letters, numbers and spaces'
    }),

  FatherName: Joi.string()
    .trim()
    .max(50)
    .pattern(namePattern)
    .allow('', null)
    .optional()
    .messages({
      'string.max': 'Father Name cannot exceed 50 characters',
      'string.pattern.base':
        'Father Name may contain only letters, numbers and spaces'
    }),

  Gender: Joi.string()
    .valid('Male', 'Female', 'Other')
    .allow('', null)
    .optional(),

  DOB: Joi.date()
    .min('1900-01-01')
    .max('now')
    .allow('', null)
    .optional()
    .messages({
      'date.base': 'DOB must be a valid date',
      'date.min': 'DOB cannot be before 1900',
      'date.max': 'DOB cannot be in the future'
    }),

  CNIC: Joi.string()
    .trim()
    .pattern(digitsPattern)
    .max(16)
    .required()
    .messages({
      'string.empty': 'CNIC is required',
      'string.max': 'CNIC cannot exceed 16 digits',
      'string.pattern.base':
        'CNIC must contain digits only'
    }),

  Mobile: Joi.string()
    .trim()
    .pattern(digitsPattern)
    .max(16)
    .required()
    .messages({
      'string.empty': 'Mobile is required',
      'string.max':
        'Mobile cannot exceed 16 digits',
      'string.pattern.base':
        'Mobile must contain digits only'
    }),

  WhatsApp: Joi.string()
    .trim()
    .pattern(digitsPattern)
    .max(16)
    .allow('', null)
    .optional()
    .messages({
      'string.max':
        'WhatsApp cannot exceed 16 digits',
      'string.pattern.base':
        'WhatsApp must contain digits only'
    }),

  Email: Joi.string()
    .trim()
    .email()
    .max(50)
    .allow('', null)
    .optional()
    .messages({
      'string.email':
        'Please enter a valid email address',
      'string.max':
        'Email cannot exceed 50 characters'
    }),

  Address: Joi.string()
    .trim()
    .max(120)
    .allow('', null)
    .optional()
    .messages({
      'string.max':
        'Address cannot exceed 120 characters'
    }),

  EmergencyContact: Joi.string()
    .trim()
    .pattern(digitsPattern)
    .max(16)
    .allow('', null)
    .optional()
    .messages({
      'string.max':
        'Emergency Contact cannot exceed 16 digits',
      'string.pattern.base':
        'Emergency Contact must contain digits only'
    }),

  JoiningDate: Joi.date()
    .required()
    .messages({
      'date.base':
        'Joining Date must be a valid date',
      'any.required':
        'Joining Date is required'
    }),

  TrainerID: Joi.number()
    .integer()
    .allow('', null)
    .optional()
    .messages({
      'number.base':
        'Trainer must be a valid trainer'
    }),

  HeightFeet: Joi.number()
    .integer()
    .min(1)
    .max(8)
    .allow('', null)
    .optional(),

  HeightInches: Joi.number()
    .integer()
    .min(0)
    .max(11)
    .allow('', null)
    .optional(),

  MembershipPlanID: Joi.number()
    .integer()
    .allow('', null)
    .optional()
    .messages({
      'number.base': 'Membership plan must be valid'
    }),

  Weight: Joi.number()
    .precision(1)
    .min(0)
    .max(999.9)
    .allow('', null)
    .optional()
    .messages({
      'number.base':
        'Weight must be a valid number',
      'number.max':
        'Weight cannot exceed 999.9 kg'
    }),

  MedicalNotes: Joi.string()
    .trim()
    .max(120)
    .required()
    .messages({
      'string.empty':
        'Medical Notes are required',
      'string.max':
        'Medical Notes cannot exceed 120 characters'
    }),

  Status: Joi.string()
    .valid(
      'Active',
      'Inactive',
      'Frozen',
      'Expired'
    )
    .default('Active')
};

const create = Joi.object({
  BranchID: Joi.number()
    .integer()
    .required()
    .messages({
      'any.required':
        'Branch is required',
      'number.base':
        'Branch must be valid'
    }),

  ...commonFields
});

const update = Joi.object({
  BranchID: Joi.number()
    .integer()
    .allow('', null)
    .optional(),

  FullName:
    commonFields.FullName.optional(),

  FatherName:
    commonFields.FatherName,

  Gender:
    commonFields.Gender,

  DOB:
    commonFields.DOB,

  CNIC:
    commonFields.CNIC,

  Mobile:
    commonFields.Mobile,

  WhatsApp:
    commonFields.WhatsApp,

  Email:
    commonFields.Email,

  Address:
    commonFields.Address,

  EmergencyContact:
    commonFields.EmergencyContact,

  JoiningDate:
    commonFields.JoiningDate.optional(),

  TrainerID:
    commonFields.TrainerID,

  HeightFeet:
    commonFields.HeightFeet,

  HeightInches:
    commonFields.HeightInches,

  Weight:
    commonFields.Weight,

  MedicalNotes:
    commonFields.MedicalNotes.optional(),

  Status:
    commonFields.Status.optional()
});

const list = Joi.object({
  page: Joi.number()
    .integer()
    .min(1)
    .default(1),

  pageSize: Joi.number()
    .integer()
    .min(1)
    .max(200)
    .default(20),

  search: Joi.string()
    .allow('', null)
    .optional(),

  BranchID: Joi.number()
    .integer()
    .allow('', null)
    .optional(),

  Status: Joi.string()
    .valid(
      'Active',
      'Inactive',
      'Frozen',
      'Expired'
    )
    .allow('', null)
    .optional(),

  TrainerID: Joi.number()
    .integer()
    .allow('', null)
    .optional()
});

module.exports = {
  create,
  update,
  list
};