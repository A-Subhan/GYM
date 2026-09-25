/**
 * Finance module error translation.
 *
 * Stored procedures raise business rules via THROW 51xxx. The generic error
 * handler would surface them as an opaque "Database error", so this map
 * converts each number into a friendly message + HTTP status + envelope code.
 * Any unknown 51xxx falls back to the raw SQL message (still not raw to the
 * user as a stack trace); non-Finance errors pass through untouched.
 */
const FINANCE_ERROR_MAP = {
  // vouchers
  51001: { status: 404, code: 'NOT_FOUND',        message: 'Voucher not found.' },
  51002: { status: 422, code: 'BUSINESS_RULE',    message: 'Voucher is not a draft.' },
  51003: { status: 409, code: 'CONFLICT',         message: 'Voucher is already posted.' },
  51004: { status: 422, code: 'BUSINESS_RULE',    message: 'Debit and credit totals do not match.' },
  51005: { status: 422, code: 'BUSINESS_RULE',    message: 'A posted voucher must contain at least two entries.' },
  51006: { status: 422, code: 'BUSINESS_RULE',    message: 'Debit total must be greater than zero.' },
  51007: { status: 422, code: 'BUSINESS_RULE',    message: 'Control accounts cannot receive postings. Select active Detail accounts only.' },
  51008: { status: 404, code: 'NOT_FOUND',        message: 'Account not found or inactive.' },
  // COA
  51010: { status: 422, code: 'BUSINESS_RULE',    message: 'Invalid COA configuration.' },
  51011: { status: 409, code: 'DUPLICATE',        message: 'Duplicate account code.' },
  51012: { status: 422, code: 'BUSINESS_RULE',    message: 'Invalid account code, level or hierarchy.' },
  51013: { status: 422, code: 'BUSINESS_RULE',    message: 'The account has child accounts.' },
  51014: { status: 422, code: 'BUSINESS_RULE',    message: 'The account has posted transactions and cannot be deleted.' },
  // years / periods
  51015: { status: 422, code: 'BUSINESS_RULE',    message: 'No financial year covers the voucher date.' },
  51016: { status: 422, code: 'BUSINESS_RULE',    message: 'The financial year is locked or closed.' },
  51017: { status: 422, code: 'BUSINESS_RULE',    message: 'The accounting period is closed or locked.' },
  51018: { status: 422, code: 'BUSINESS_RULE',    message: 'Invalid or inactive branch.' },
  51019: { status: 422, code: 'BUSINESS_RULE',    message: 'Invalid party reference.' },
  // voucher types / numbering
  51020: { status: 422, code: 'BUSINESS_RULE',    message: 'Voucher prefix is locked.' },
  51021: { status: 404, code: 'NOT_FOUND',        message: 'Voucher type not found or inactive.' },
  51022: { status: 409, code: 'CONFLICT',         message: 'Voucher has already been reversed.' },
  51023: { status: 422, code: 'BUSINESS_RULE',    message: 'A draft voucher cannot be reversed — delete it instead.' },
  51024: { status: 422, code: 'BUSINESS_RULE',    message: 'The reversal date falls in a closed period.' },
  51025: { status: 409, code: 'CONFLICT',         message: 'The financial year overlaps an existing year.' },
  51026: { status: 409, code: 'DUPLICATE',        message: 'A financial year with this name already exists.' },
  51027: { status: 422, code: 'BUSINESS_RULE',    message: 'Retained earnings account is not configured.' },
  51028: { status: 422, code: 'BUSINESS_RULE',    message: 'Retained earnings must be an active Detail account of type Capital.' },
  51029: { status: 422, code: 'BUSINESS_RULE',    message: 'COA structure is locked: the change would invalidate existing account codes.' },
  51030: { status: 409, code: 'CONFLICT',         message: 'Voucher prefix is locked after use.' },
  51031: { status: 422, code: 'BUSINESS_RULE',    message: 'Every entry must have exactly one of debit or credit.' },
  51032: { status: 422, code: 'BUSINESS_RULE',    message: 'The account does not carry the required tag.' },
  // reconciliation
  51033: { status: 422, code: 'BUSINESS_RULE',    message: 'Reconciliation run state does not allow this action.' },
  // voucher immutability
  51034: { status: 409, code: 'CONFLICT',         message: 'Voucher cannot be edited after posting.' },
  51035: { status: 409, code: 'CONFLICT',         message: 'Posted vouchers cannot be deleted.' },
  // year close
  51036: { status: 422, code: 'BUSINESS_RULE',    message: 'Draft vouchers must be resolved before closing the financial year.' },
  51037: { status: 404, code: 'NOT_FOUND',        message: 'Financial year not found.' },
  51038: { status: 404, code: 'NOT_FOUND',        message: 'Accounting period not found.' },
  51039: { status: 422, code: 'BUSINESS_RULE',    message: 'This voucher type requires a Cash or Bank tagged account on the money side.' },
  51040: { status: 409, code: 'CONFLICT',         message: 'Financial year is already closed.' },
  51041: { status: 422, code: 'BUSINESS_RULE',    message: 'Invalid report filters.' },
  // voucher documents (14_finance_rework)
  51050: { status: 409, code: 'CONFLICT',         message: 'The voucher date cannot be changed after the voucher has been saved.' },
  51051: { status: 400, code: 'BAD_REQUEST',      message: 'Invalid voucher direction or family.' },
  51052: { status: 422, code: 'BUSINESS_RULE',    message: 'The selected account must be an active Detail account tagged Cash or Bank.' },
  51053: { status: 422, code: 'BUSINESS_RULE',    message: 'Every line amount must be greater than zero.' },
  51054: { status: 422, code: 'BUSINESS_RULE',    message: 'The voucher is not balanced: total debit and total credit must be equal and greater than zero.' },
  51055: { status: 422, code: 'BUSINESS_RULE',    message: 'Tax head not found or inactive.' },
  51056: { status: 422, code: 'BUSINESS_RULE',    message: 'Knock Off is not enabled for the selected account.' },
  51057: { status: 422, code: 'BUSINESS_RULE',    message: 'Add at least one detail line.' },
  51058: { status: 409, code: 'DUPLICATE',        message: 'A tax head with this code already exists.' },
  // voucher upgrade (16)
  51059: { status: 409, code: 'CONFLICT',         message: 'This voucher has reconciled entries and cannot be edited.' },
  51060: { status: 422, code: 'BUSINESS_RULE',    message: 'Tax Account is mandatory when tax percentage or tax amount is entered.' },
  51061: { status: 422, code: 'BUSINESS_RULE',    message: 'Invalid cheque status.' },
  51062: { status: 422, code: 'BUSINESS_RULE',    message: 'Tax Account must be an active Detail account tagged Tax.' },
  51063: { status: 422, code: 'BUSINESS_RULE',    message: 'One or more selected accounts are not available for this branch.' },
  51064: { status: 422, code: 'BUSINESS_RULE',    message: 'Invalid voucher status.' },
  51065: { status: 422, code: 'BUSINESS_RULE',    message: 'Tax Percentage must be between 0 and 100.' },
  51066: { status: 422, code: 'BUSINESS_RULE',    message: 'Total allocation exceeds the voucher line amount.' },
  51067: { status: 422, code: 'BUSINESS_RULE',    message: 'Allocation exceeds the outstanding amount of the bill.' },
};

/**
 * Converts a thrown MSSQL error from Finance SPs into a friendly error.
 * Returns { status, code, message } or null when the error is not a Finance
 * business error.
 */
function translateFinanceError(err) {
  if (!err || typeof err.number !== 'number') return null;
  if (err.number < 51001 || err.number > 51999) return null;
  const mapped = FINANCE_ERROR_MAP[err.number];
  if (mapped) return mapped;
  return { status: 422, code: 'BUSINESS_RULE', message: err.message || 'Finance validation failed.' };
}

module.exports = { translateFinanceError, FINANCE_ERROR_MAP };
