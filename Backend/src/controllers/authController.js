const authService = require('../services/authService');
const { success, error } = require('../utils/response');
const { getClientIp } = require('../utils/helpers');
const logger = require('../utils/logger');

exports.login = async (req, res, next) => {
  try {
    const ipAddress = getClientIp(req);
    const userAgent = req.headers['user-agent'];
    const { username, password, location } = req.body;
    const result = await authService.login({ username, password, ipAddress, userAgent, location });
    return success(res, result, 'Login successful');
  } catch (err) {
    logger.warn(`[authCtrl] login failed: ${err.message}`);
    return error(res, err.message || 'Login failed', err.status || 401, err.code || 'AUTH_ERROR');
  }
};

exports.logout = async (req, res, next) => {
  try {
    const { refreshToken } = req.body;
    await authService.logout(refreshToken, req.user?.userId, getClientIp(req));
    return success(res, null, 'Logged out');
  } catch (err) {
    return error(res, err.message, 500);
  }
};

exports.refresh = async (req, res, next) => {
  try {
    const { refreshToken } = req.body;
    const result = await authService.refresh(refreshToken);
    return success(res, result, 'Token refreshed');
  } catch (err) {
    return error(res, err.message, err.status || 401, err.code || 'TOKEN_EXPIRED');
  }
};

exports.heartbeat = async (req, res, next) => {
  try {
    const { refreshToken } = req.body;
    await authService.heartbeat(refreshToken);
    return success(res, null, 'Heartbeat received');
  } catch (err) {
    return error(res, err.message, 500);
  }
};

exports.changePassword = async (req, res, next) => {
  try {
    const { currentPassword, newPassword } = req.body;
    await authService.changePassword(req.user.userId, currentPassword, newPassword);
    return success(res, null, 'Password changed successfully');
  } catch (err) {
    return error(res, err.message, err.status || 400, err.code || 'PASSWORD_ERROR');
  }
};

exports.me = async (req, res, next) => {
  return success(res, { user: req.user }, 'Current user');
};

exports.mySessions = async (req, res, next) => {
  try {
    const sessions = await authService.listSessions(req.user.userId);
    return success(res, sessions, 'Sessions retrieved');
  } catch (err) {
    return error(res, err.message, 500);
  }
};
