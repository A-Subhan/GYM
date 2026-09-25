const Joi = require('joi');

const login = Joi.object({
  username: Joi.string().min(3).max(150).required(),
  password: Joi.string().min(1).max(200).required(),
  location: Joi.string().allow('', null).max(200).optional(),
});

const changePassword = Joi.object({
  currentPassword: Joi.string().required(),
  newPassword: Joi.string().min(8).max(100).required(),
});

const forgotPassword = Joi.object({
  email: Joi.string().email().required(),
});

const resetPassword = Joi.object({
  token: Joi.string().required(),
  newPassword: Joi.string().min(8).max(100).required(),
});

const refresh = Joi.object({
  refreshToken: Joi.string().required(),
});

module.exports = { login, changePassword, forgotPassword, resetPassword, refresh };
