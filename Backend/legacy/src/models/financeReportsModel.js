/**
 * Finance reports data access — SPs only.
 * All reports compute from VoucherEntries (the ledger ground truth),
 * restricted to vouchers that have been posted (status Posted or Reversed).
 */
const { getPool, sql } = require('../config/db');

async function ledger(params) {
  const pool = await getPool();
  const result = await pool.request()
    .input('AccountID', params.accountId || null)
    .input('GroupAccountID', params.groupAccountId || null)
    .input('FromDate', params.fromDate || null)
    .input('ToDate', params.toDate || null)
    .input('BranchID', params.branchId || null)
    .input('VoucherTypeID', params.voucherTypeId || null)
    .input('VoucherNo', params.voucherNo || null)
    .input('PartyMemberID', params.partyMemberId || null)
    .input('PartySupplierID', params.partySupplierId || null)
    .input('PartyStaffID', params.partyStaffId || null)
    .input('RequireTag', params.requireTag || null)
    .execute('sp_FinanceReports_Ledger');
  return { summary: result.recordsets[0][0], lines: result.recordsets[1] };
}

async function trialBalance(params) {
  const pool = await getPool();
  const result = await pool.request()
    .input('FromDate', params.fromDate || null)
    .input('ToDate', params.toDate || null)
    .input('BranchID', params.branchId || null)
    .input('RollupLevel', params.rollupLevel || null)
    .execute('sp_FinanceReports_TrialBalance');
  return { rows: result.recordsets[0], totals: result.recordsets[1][0] };
}

async function openingTB({ financialYearId, branchId }) {
  const pool = await getPool();
  const result = await pool.request()
    .input('FinancialYearID', financialYearId)
    .input('BranchID', branchId || null)
    .execute('sp_FinanceReports_OpeningTB');
  return { rows: result.recordsets[0], totals: result.recordsets[1][0] };
}

async function balanceSheet({ asOf, branchId }) {
  const pool = await getPool();
  const result = await pool.request()
    .input('AsOf', asOf || null)
    .input('BranchID', branchId || null)
    .execute('sp_FinanceReports_BalanceSheet');
  return { rows: result.recordsets[0], totals: result.recordsets[1][0] };
}

async function profitLoss(params) {
  const pool = await getPool();
  const result = await pool.request()
    .input('FromDate', params.fromDate || null)
    .input('ToDate', params.toDate || null)
    .input('BranchID', params.branchId || null)
    .execute('sp_FinanceReports_ProfitLoss');
  return { rows: result.recordsets[0], totals: result.recordsets[1][0] };
}

async function aging({ partyKind, asOf, branchId, partyId, mode }) {
  const pool = await getPool();
  const result = await pool.request()
    .input('PartyKind', partyKind)
    .input('AsOf', asOf || null)
    .input('BranchID', branchId || null)
    .input('PartyID', partyId || null)
    .input('Mode', mode || null)
    .execute('sp_FinanceReports_Aging');
  return result.recordset;
}

async function bankStatement(params) {
  const pool = await getPool();
  const result = await pool.request()
    .input('AccountID', params.accountId)
    .input('FromDate', params.fromDate || null)
    .input('ToDate', params.toDate || null)
    .input('BranchID', params.branchId || null)
    .execute('sp_FinanceReports_BankStatement');
  // BankStatement streams: summary + ledger summary + ledger lines
  const sets = result.recordsets;
  const summary = sets[0][0];
  const lines = sets[sets.length - 1];
  return { summary, lines };
}

module.exports = { ledger, trialBalance, openingTB, balanceSheet, profitLoss, aging, bankStatement };
