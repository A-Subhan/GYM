/**
 * Finance administration data access — SPs only.
 * Financial years, accounting periods, mappings, user report formats,
 * bank reconciliation, dashboard.
 */
const { getPool, sql } = require('../config/db');

/* ---------------- financial years ---------------- */

async function listYears() {
  const pool = await getPool();
  const result = await pool.request().execute('sp_FinanceYears_List');
  return result.recordset;
}

async function createYear({ name, startDate, endDate }, createdBy) {
  const pool = await getPool();
  const result = await pool.request()
    .input('Name', name)
    .input('StartDate', startDate)
    .input('EndDate', endDate)
    .input('CreatedBy', createdBy)
    .execute('sp_FinanceYears_Create');
  return result.recordset[0].FinancialYearID;
}

async function setYearStatus(id, status, updatedBy) {
  const pool = await getPool();
  await pool.request()
    .input('FinancialYearID', id)
    .input('Status', status)
    .input('UpdatedBy', updatedBy)
    .execute('sp_FinanceYears_SetStatus');
}

async function closeYear(id, closedBy, retainedEarningsAccountId) {
  const pool = await getPool();
  const result = await pool.request()
    .input('FinancialYearID', id)
    .input('ClosedBy', closedBy)
    .input('RetainedEarningsAccountID', retainedEarningsAccountId || null)
    .execute('sp_FinanceYears_Close');
  return result.recordset[0];
}

/* ---------------- accounting periods ---------------- */

async function listPeriods(financialYearId) {
  const pool = await getPool();
  const result = await pool.request()
    .input('FinancialYearID', financialYearId)
    .execute('sp_FinancePeriods_List');
  return result.recordset;
}

async function setPeriodStatus(periodId, status, updatedBy) {
  const pool = await getPool();
  await pool.request()
    .input('PeriodID', periodId)
    .input('Status', status)
    .input('UpdatedBy', updatedBy)
    .execute('sp_FinancePeriods_SetStatus');
}

/* ---------------- mappings ---------------- */

async function listMappings(mappingType) {
  const pool = await getPool();
  const result = await pool.request()
    .input('MappingType', mappingType || null)
    .execute('sp_FinanceMappings_List');
  return result.recordset;
}

async function setMapping({ mappingType, sourceKey, accountId }, updatedBy) {
  const pool = await getPool();
  await pool.request()
    .input('MappingType', mappingType)
    .input('SourceKey', sourceKey || null)
    .input('AccountID', accountId)
    .input('UserId', updatedBy)
    .execute('sp_FinanceMappings_Set');
}

async function deleteMapping(id) {
  const pool = await getPool();
  await pool.request()
    .input('MappingID', id)
    .execute('sp_FinanceMappings_Delete');
}

/* ---------------- user report formats ---------------- */

async function listFormats(userId, reportKey) {
  const pool = await getPool();
  const result = await pool.request()
    .input('UserID', userId)
    .input('ReportKey', reportKey || null)
    .execute('sp_FinanceUserFormats_List');
  return result.recordset;
}

async function saveFormat({ formatId, userId, reportKey, formatName, columns, isDefault }) {
  const pool = await getPool();
  const result = await pool.request()
    .input('FormatID', formatId || null)
    .input('UserID', userId)
    .input('ReportKey', reportKey)
    .input('FormatName', formatName)
    .input('ColumnsJson', sql.NVarChar(sql.MAX), JSON.stringify(columns))
    .input('IsDefault', isDefault ? 1 : 0)
    .execute('sp_FinanceUserFormats_Save');
  return result.recordset[0].FormatID;
}

async function deleteFormat(formatId, userId) {
  const pool = await getPool();
  await pool.request()
    .input('FormatID', formatId)
    .input('UserID', userId)
    .execute('sp_FinanceUserFormats_Delete');
}

/* ---------------- bank reconciliation ---------------- */

async function createReconRun({ accountId, statementDate, openingBalance, closingBalance, branchId, notes, createdBy }) {
  const pool = await getPool();
  const result = await pool.request()
    .input('AccountID', accountId)
    .input('StatementDate', statementDate)
    .input('StatementOpeningBalance', openingBalance || 0)
    .input('StatementClosingBalance', closingBalance || 0)
    .input('BranchID', branchId || null)
    .input('Notes', notes || null)
    .input('CreatedBy', createdBy)
    .execute('sp_FinanceRecon_CreateRun');
  return result.recordset[0];
}

async function listReconRuns(accountId) {
  const pool = await getPool();
  const result = await pool.request()
    .input('AccountID', accountId || null)
    .execute('sp_FinanceRecon_ListRuns');
  return result.recordset;
}

async function getReconRun(reconId) {
  const pool = await getPool();
  const result = await pool.request()
    .input('ReconID', reconId)
    .execute('sp_FinanceRecon_GetRun');
  return { run: result.recordsets[0][0] || null, lines: result.recordsets[1] };
}

async function setReconLine(lineId, isReconciled, userId) {
  const pool = await getPool();
  await pool.request()
    .input('LineID', lineId)
    .input('IsReconciled', isReconciled ? 1 : 0)
    .input('UserId', userId)
    .execute('sp_FinanceRecon_SetLine');
}

async function completeReconRun(reconId, userId) {
  const pool = await getPool();
  await pool.request()
    .input('ReconID', reconId)
    .input('UserId', userId)
    .execute('sp_FinanceRecon_CompleteRun');
}

async function deleteReconRun(reconId) {
  const pool = await getPool();
  await pool.request()
    .input('ReconID', reconId)
    .execute('sp_FinanceRecon_DeleteRun');
}

/* ---------------- dashboard ---------------- */

async function dashboard({ asOf, branchId }) {
  const pool = await getPool();
  const result = await pool.request()
    .input('AsOf', asOf || null)
    .input('BranchID', branchId || null)
    .execute('sp_FinanceDashboard_Stats');
  return result.recordset[0];
}

module.exports = {
  listYears, createYear, setYearStatus, closeYear,
  listPeriods, setPeriodStatus,
  listMappings, setMapping, deleteMapping,
  listFormats, saveFormat, deleteFormat,
  createReconRun, listReconRuns, getReconRun, setReconLine, completeReconRun, deleteReconRun,
  dashboard,
};
