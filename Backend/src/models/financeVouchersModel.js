/**
 * Vouchers + voucher types data access — SPs only.
 * Posting / reversal / atomic create+post is executed by the central engine
 * SPs (sp_Accounting_*); this model only passes parameters.
 */
const { getPool, sql } = require('../config/db');

/* ---------------- voucher types ---------------- */

async function listTypes() {
  const pool = await getPool();
  const result = await pool.request().execute('sp_FinanceVoucherTypes_List');
  return result.recordset;
}

async function updateType(id, { title, prefix, isActive }, updatedBy) {
  const pool = await getPool();
  await pool.request()
    .input('VoucherTypeID', id)
    .input('Title', title || null)
    .input('Prefix', prefix || null)
    .input('IsActive', isActive === undefined || isActive === null ? null : (isActive ? 1 : 0))
    .input('UpdatedBy', updatedBy)
    .execute('sp_FinanceVoucherTypes_Update');
}

/* ---------------- vouchers ---------------- */

async function list({ page, pageSize, voucherTypeId, status, branchId, fromDate, toDate, accountId, search, createdBy }) {
  const pool = await getPool();
  const result = await pool.request()
    .input('Page', page)
    .input('PageSize', pageSize)
    .input('VoucherTypeID', voucherTypeId || null)
    .input('Status', status || null)
    .input('BranchID', branchId || null)
    .input('FromDate', fromDate || null)
    .input('ToDate', toDate || null)
    .input('AccountID', accountId || null)
    .input('Search', search || null)
    .input('CreatedBy', createdBy || null)
    .execute('sp_FinanceVouchers_List');
  return { rows: result.recordsets[0], total: result.recordsets[1][0] };
}

async function get(id) {
  const pool = await getPool();
  const result = await pool.request()
    .input('VoucherID', id)
    .execute('sp_FinanceVouchers_Get');
  return { voucher: result.recordsets[0][0] || null, entries: result.recordsets[1] };
}

module.exports = { listTypes, updateType, list, get };
