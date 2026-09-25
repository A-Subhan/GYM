/**
 * Voucher document data access — SPs only.
 * Families: CASH (CashVouchers), BANK (BankVouchers), JOURNAL (JournalVouchers),
 * OTB (OpeningTrialBalances). Documents post to the unified ledger through
 * sp_Accounting_* inside the save/delete SPs (atomic).
 */
const { getPool, sql } = require('../config/db');

const SAVE_SP = { CASH: 'sp_FinanceDocuments_SaveCash', BANK: 'sp_FinanceDocuments_SaveBank', JOURNAL: 'sp_FinanceDocuments_SaveJournal', OTB: 'sp_FinanceDocuments_SaveOpeningTB' };
const ID_OUT = { CASH: 'NewID', BANK: 'NewID', JOURNAL: 'NewID', OTB: 'NewID' };

/**
 * Creates or edits a voucher document and posts it atomically.
 * For edit, body.VoucherID carries the document id and body.VoucherDate must
 * equal the stored date (the SP enforces immutability).
 */
async function save(family, payload) {
  const pool = await getPool();
  const req = pool.request()
    .input('Status', payload.status || 'Posted')
    .input('VoucherDate', payload.voucherDate)
    .input('BranchID', payload.branchId)
    .input('Narrative', payload.narrative || null)
    .input('LinesJson', sql.NVarChar(sql.MAX), JSON.stringify(payload.lines))
    .input('UserId', payload.userId);

  if (family === 'CASH') {
    req.input('Direction', payload.direction)
       .input('CashAccountID', payload.moneyAccountId)
       .input('CashVoucherID', payload.documentId || null);
  } else if (family === 'BANK') {
    req.input('Direction', payload.direction)
       .input('BankAccountID', payload.moneyAccountId)
       .input('BankVoucherID', payload.documentId || null);
  } else if (family === 'JOURNAL') {
    req.input('JournalVoucherID', payload.documentId || null);
  } else if (family === 'OTB') {
    req.input('OpeningTBID', payload.documentId || null);
  } else {
    throw new Error('Invalid voucher family');
  }

  req.output('NewID', sql.Int);
  req.output('NewVoucherNo', sql.NVarChar(50));
  const result = await req.execute(SAVE_SP[family]);
  return result.recordset[0];
}

async function list(family, { page, pageSize, direction, status, branchId, fromDate, toDate, search, bookAccountId, accountId }) {
  const pool = await getPool();
  const result = await pool.request()
    .input('Family', family)
    .input('Page', page)
    .input('PageSize', pageSize)
    .input('Direction', direction || null)
    .input('Status', status || null)
    .input('BranchID', branchId || null)
    .input('FromDate', fromDate || null)
    .input('ToDate', toDate || null)
    .input('Search', search || null)
    .input('BookAccountID', bookAccountId || null)
    .input('AccountID', accountId || null)
    .execute('sp_FinanceDocuments_List');
  return { rows: result.recordsets[0], total: result.recordsets[1][0] };
}

async function post(family, id, userId) {
  const pool = await getPool();
  const req = pool.request()
    .input('Family', family).input('ID', id).input('UserId', userId);
  req.output('NewVoucherNo', sql.NVarChar(50));
  const result = await req.execute('sp_FinanceDocuments_Post');
  return result.recordset[0];
}

async function saveAllocations(family, documentId, lineId, allocations, userId) {
  const pool = await getPool();
  await pool.request()
    .input('Family', family).input('DocumentID', documentId).input('LineID', lineId)
    .input('AllocJson', sql.NVarChar(sql.MAX), JSON.stringify(allocations))
    .input('UserId', userId)
    .execute('sp_FinanceDocuments_SaveAllocations');
}

async function getAllocations(family, documentId) {
  const pool = await getPool();
  const result = await pool.request()
    .input('Family', family).input('DocumentID', documentId)
    .execute('sp_FinanceDocuments_GetAllocations');
  return result.recordset;
}

async function get(family, id) {
  const pool = await getPool();
  const result = await pool.request()
    .input('Family', family)
    .input('ID', id)
    .execute('sp_FinanceDocuments_Get');
  return { voucher: result.recordsets[0][0] || null, lines: result.recordsets[1] };
}

async function remove(family, id, userId) {
  const pool = await getPool();
  await pool.request()
    .input('Family', family)
    .input('ID', id)
    .input('UserId', userId)
    .execute('sp_FinanceDocuments_Delete');
}

/* ---------------- tax heads master ---------------- */

async function listTaxHeads(includeInactive) {
  const pool = await getPool();
  const result = await pool.request()
    .input('IncludeInactive', includeInactive ? 1 : 0)
    .execute('sp_TaxHeads_List');
  return result.recordset;
}

async function createTaxHead({ code, name, description, ratePercent, taxType }, userId) {
  const pool = await getPool();
  const result = await pool.request()
    .input('Code', code)
    .input('Name', name)
    .input('Description', description || null)
    .input('RatePercent', ratePercent === undefined || ratePercent === '' || ratePercent === null ? null : Number(ratePercent))
    .input('TaxType', taxType || null)
    .input('CreatedBy', userId)
    .execute('sp_TaxHeads_Create');
  return result.recordset[0].TaxHeadID;
}

async function updateTaxHead(id, { name, description, ratePercent, taxType }, userId) {
  const pool = await getPool();
  await pool.request()
    .input('TaxHeadID', id)
    .input('Name', name)
    .input('Description', description || null)
    .input('RatePercent', ratePercent === undefined || ratePercent === '' || ratePercent === null ? null : Number(ratePercent))
    .input('TaxType', taxType || null)
    .input('UpdatedBy', userId)
    .execute('sp_TaxHeads_Update');
}

async function setTaxHeadStatus(id, isActive, userId) {
  const pool = await getPool();
  await pool.request()
    .input('TaxHeadID', id)
    .input('IsActive', isActive ? 1 : 0)
    .input('UpdatedBy', userId)
    .execute('sp_TaxHeads_SetStatus');
}

module.exports = {
  save, list, get, remove, post, saveAllocations, getAllocations,
  listTaxHeads, createTaxHead, updateTaxHead, setTaxHeadStatus,
};
