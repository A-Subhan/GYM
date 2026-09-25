/**
 * Central Accounting Service.
 *
 * Business orchestration for the Finance module. All atomic accounting
 * (validation, numbering, entries, balances) lives in the stored procedures
 * (sp_Accounting_*); this service is the single entry point every Finance
 * controller — and every future module integration — uses to:
 *   - post a saved draft,
 *   - create + post a voucher atomically (direct posting),
 *   - reverse a posted voucher,
 *   - translate SQL business errors (THROW 51xxx) into friendly API errors.
 */
const { translateFinanceError } = require('../utils/financeErrors');
const { error } = require('../utils/response');

/** Wraps a model call, translating Finance SQL business errors. */
async function callOnce(fn) {
  return fn();
}

/**
 * Executes a Finance operation, retrying on SQL Server deadlock (1205).
 * Deadlock victims are transient by design; the SP transaction rolled back
 * cleanly, so a fresh attempt is always safe.
 */
async function call(fn, attempts = 3) {
  for (let i = 0; i < attempts; i++) {
    try {
      return await callOnce(fn);
    } catch (err) {
      if (err && err.number === 1205 && i < attempts - 1) {
        await new Promise((r) => setTimeout(r, 50 + Math.floor(Math.random() * 100)));
        continue;
      }
      const mapped = translateFinanceError(err);
      if (mapped) {
        const friendly = new Error(mapped.message);
        friendly.status = mapped.status;
        friendly.code = mapped.code;
        throw friendly;
      }
      throw err;
    }
  }
}

module.exports = { call };
