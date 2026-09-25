const { getPool } = require('../config/db');
const { AUDIT_ACTIONS } = require('../config/constants');
const { getClientIp } = require('../utils/helpers');

/**
 * Audit logging middleware.
 *
 *   router.post('/', verifyJWT, requirePermission('members.add'),
 *               audit('CREATE', 'members'), controller);
 *
 * Writes a row to AuditLogs AFTER the controller successfully completes (status 2xx).
 * Records: UserID, Action, Module, EntityID (best-effort from res.locals.entityId),
 * Details (res.locals.auditDetails), IP, Location (res.locals.location).
 */
function audit(action, module) {
  return async (req, res, next) => {
    const oldSend = res.send.bind(res);

    res.send = function (body) {
      // Restore original send so it can be called normally
      res.send = oldSend;

      // Only audit successful actions
      const isSuccess = res.statusCode >= 200 && res.statusCode < 300;

      if (isSuccess && req.user) {
        const ipAddress = getClientIp(req);
        const location = req.body?.location || req.headers['x-user-location'] || null;

        // Try to parse body if it's a string (Express sometimes sends as Buffer/string)
        let parsed = body;
        try {
          if (typeof body === 'string' && body.length) parsed = JSON.parse(body);
        } catch (_) {}

        const entityId =
          res.locals.entityId ||
          (parsed && parsed.data && (parsed.data.MemberID || parsed.data.UserID || parsed.data.BranchID || parsed.data.PlanID || parsed.data.InvoiceID || parsed.data.CollectionID)) ||
          (req.params.id && parseInt(req.params.id, 10)) ||
          null;

        const details = res.locals.auditDetails
          ? JSON.stringify(res.locals.auditDetails)
          : null;

        // Fire-and-forget — don't block the response
        (async () => {
          try {
            const pool = await getPool();
            await pool
              .request()
              .input('UserID', req.user.userId)
              .input('Action', action)
              .input('Module', module)
              .input('EntityID', entityId)
              .input('Details', details)
              .input('IPAddress', ipAddress)
              .input('Location', location)
              .execute('sp_AuditLog_Write');
          } catch (err) {
            console.error('[audit] write failed:', err.message);
          }
        })();
      }

      return oldSend(body);
    };

    next();
  };
}

/**
 * Direct audit helper for use inside services/controllers when middleware
 * can't capture the event (e.g. login flow).
 */
async function writeAudit({ userId = null, action, module, entityId = null, details = null, ipAddress = null, location = null }) {
  try {
    const pool = await getPool();
    await pool
      .request()
      .input('UserID', userId)
      .input('Action', action)
      .input('Module', module)
      .input('EntityID', entityId)
      .input('Details', details)
      .input('IPAddress', ipAddress)
      .input('Location', location)
      .execute('sp_AuditLog_Write');
  } catch (err) {
    console.error('[audit] writeAudit failed:', err.message);
  }
}

module.exports = { audit, writeAudit };
