/**
 * Unified API response helpers.
 * Every controller returns one of these via res.json().
 */
function success(res, data = null, message = 'OK', meta = null, status = 200) {
  const body = { success: true, data, message };
  if (meta) body.meta = meta;
  return res.status(status).json(body);
}

function error(res, message = 'Internal Server Error', status = 500, code = 'INTERNAL_ERROR', details = null) {
  const body = { success: false, error: { code, message } };
  if (details) body.error.details = details;
  return res.status(status).json(body);
}

function paginate(res, rows, total, page, pageSize, message = 'OK') {
  return res.status(200).json({
    success: true,
    data: rows,
    message,
    meta: {
      page: parseInt(page, 10),
      pageSize: parseInt(pageSize, 10),
      total: Array.isArray(total) ? total[0]?.Total || 0 : total,
      totalPages: Math.ceil((Array.isArray(total) ? total[0]?.Total || 0 : total) / pageSize),
    },
  });
}

module.exports = { success, error, paginate };
