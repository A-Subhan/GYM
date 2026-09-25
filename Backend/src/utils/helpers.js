/**
 * Generic pagination + filter param extractor for Express routes.
 */
function paginationParams(req) {
  return {
    page: Math.max(1, parseInt(req.query.page, 10) || 1),
    pageSize: Math.min(200, Math.max(1, parseInt(req.query.pageSize, 10) || 20)),
  };
}

function getClientIp(req) {
  const forwarded = req.headers['x-forwarded-for'];
  if (forwarded) return forwarded.split(',')[0].trim();
  return req.socket?.remoteAddress || req.ip || null;
}

/**
 * Wraps an async Express handler so rejections reach the centralized error
 * middleware instead of becoming unhandled rejections (which crash the
 * process). Used by the Finance controllers.
 */
function wrap(handler) {
  return (req, res, next) => Promise.resolve(handler(req, res, next)).catch(next);
}

module.exports = { paginationParams, getClientIp, wrap };
