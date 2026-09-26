const { error } = require('../utils/response');
const logger = require('../utils/logger');

/**
 * 404 handler — unknown routes.
 */
function notFound(req, res, next) {
  return error(res, `Route not found: ${req.method} ${req.originalUrl}`, 404, 'NOT_FOUND');
}

/**
 * Centralized error handler.
 */
function errorHandler(err, req, res, next) {
  logger.error(err.stack || err.message);

  if (err.name === 'UnauthorizedError') {
    return error(res, 'Invalid token', 401, 'UNAUTHORIZED');
  }

  if (err.code === 'EBADCSRFTOKEN') {
    return error(res, 'Invalid CSRF token', 403, 'CSRF_ERROR');
  }

  // MSSQL errors
  if (err.code && err.code.startsWith('E') && err.number) {
    return error(res, 'Database error', 500, 'DB_ERROR', { sqlErrorCode: err.number, sqlMessage: err.message });
  }

  return error(res, err.message || 'Internal Server Error', err.status || 500, err.code || 'INTERNAL_ERROR');
}

module.exports = { notFound, errorHandler };
