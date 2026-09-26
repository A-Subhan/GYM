/**
 * Finance administration controller — years, periods, mappings, formats,
 * bank reconciliation, defaults, dashboard.
 */
const adminModel = require('../models/financeAdminModel');
const accountingService = require('../services/accountingService');
const settingsService = require('../services/settingsService');
const { success, error } = require('../utils/response');
const { wrap } = require('../utils/helpers');

function getBranchId(req) {
  if (req.user.isSuperAdmin) {
    const passed = req.query.branchId || req.body?.BranchID;
    return passed ? parseInt(passed, 10) : (req.user.branchId || null);
  }
  return req.user.branchId;
}

/* ---------------- financial years ---------------- */

exports.listYears = wrap(async (req, res) => {
  const rows = await adminModel.listYears();
  return success(res, rows, 'Financial years');
});

exports.createYear = wrap(async (req, res) => {
  const id = await accountingService.call(() => adminModel.createYear({
    name: req.body.Name, startDate: req.body.StartDate, endDate: req.body.EndDate,
  }, req.user.userId));
  res.locals.entityId = id;
  res.locals.auditDetails = { name: req.body.Name, startDate: req.body.StartDate, endDate: req.body.EndDate };
  return success(res, { financialYearId: id }, 'Financial year created', null, 201);
});

exports.setYearStatus = wrap(async (req, res) => {
  await accountingService.call(() => adminModel.setYearStatus(
    parseInt(req.params.id, 10), req.body.Status, req.user.userId));
  res.locals.entityId = parseInt(req.params.id, 10);
  res.locals.auditDetails = { status: req.body.Status };
  return success(res, null, `Financial year ${req.body.Status === 'Locked' ? 'locked' : 'unlocked'}`);
});

exports.closeYear = wrap(async (req, res) => {
  const result = await accountingService.call(() => adminModel.closeYear(
    parseInt(req.params.id, 10), req.user.userId, req.body.RetainedEarningsAccountID || null));
  res.locals.entityId = parseInt(req.params.id, 10);
  res.locals.auditDetails = { closingVoucherId: result.ClosingVoucherID, nextFY: result.NextFinancialYearID, netProfit: result.NetProfit };
  return success(res, result, 'Financial year closed');
});

/* ---------------- accounting periods ---------------- */

exports.listPeriods = wrap(async (req, res) => {
  const rows = await adminModel.listPeriods(parseInt(req.params.id, 10));
  return success(res, rows, 'Accounting periods');
});

exports.setPeriodStatus = wrap(async (req, res) => {
  await accountingService.call(() => adminModel.setPeriodStatus(
    parseInt(req.params.id, 10), req.body.Status, req.user.userId));
  res.locals.entityId = parseInt(req.params.id, 10);
  res.locals.auditDetails = { periodId: req.params.id, status: req.body.Status };
  return success(res, null, `Period ${req.body.Status === 'Open' ? 'reopened' : req.body.Status.toLowerCase()}`);
});

/* ---------------- mappings ---------------- */

exports.listMappings = wrap(async (req, res) => {
  const rows = await adminModel.listMappings(req.query.type || null);
  return success(res, rows, 'Finance mappings');
});

exports.setMapping = wrap(async (req, res) => {
  await accountingService.call(() => adminModel.setMapping({
    mappingType: req.body.MappingType,
    sourceKey: req.body.SourceKey || null,
    accountId: req.body.AccountID,
  }, req.user.userId));
  res.locals.auditDetails = { mappingType: req.body.MappingType, sourceKey: req.body.SourceKey, accountId: req.body.AccountID };
  return success(res, null, 'Mapping saved');
});

exports.deleteMapping = wrap(async (req, res) => {
  await adminModel.deleteMapping(parseInt(req.params.id, 10));
  res.locals.entityId = parseInt(req.params.id, 10);
  return success(res, null, 'Mapping deleted');
});

/* ---------------- user report formats ---------------- */

exports.listFormats = wrap(async (req, res) => {
  const rows = await adminModel.listFormats(req.user.userId, req.query.reportKey || null);
  return success(res, rows, 'Report formats');
});

exports.saveFormat = wrap(async (req, res) => {
  const id = await adminModel.saveFormat({
    formatId: req.body.FormatID || null,
    userId: req.user.userId,
    reportKey: req.body.ReportKey,
    formatName: req.body.FormatName,
    columns: req.body.Columns,
    isDefault: !!req.body.IsDefault,
  });
  res.locals.entityId = id;
  res.locals.auditDetails = { reportKey: req.body.ReportKey, formatName: req.body.FormatName };
  return success(res, { formatId: id }, 'Report format saved', null, 201);
});

exports.deleteFormat = wrap(async (req, res) => {
  await adminModel.deleteFormat(parseInt(req.params.id, 10), req.user.userId);
  res.locals.entityId = parseInt(req.params.id, 10);
  return success(res, null, 'Report format deleted');
});

/* ---------------- bank reconciliation ---------------- */

exports.createReconRun = wrap(async (req, res) => {
  const branchId = req.user.isSuperAdmin ? (req.body.BranchID || null) : req.user.branchId;
  const result = await accountingService.call(() => adminModel.createReconRun({
    accountId: req.body.AccountID,
    statementDate: req.body.StatementDate,
    openingBalance: req.body.StatementOpeningBalance,
    closingBalance: req.body.StatementClosingBalance,
    branchId,
    notes: req.body.Notes || null,
    createdBy: req.user.userId,
  }));
  res.locals.entityId = result.ReconID;
  res.locals.auditDetails = { reconId: result.ReconID, statementDate: req.body.StatementDate, snapshots: result.SnapshotCount };
  return success(res, result, 'Reconciliation run created', null, 201);
});

exports.listReconRuns = wrap(async (req, res) => {
  const rows = await adminModel.listReconRuns(req.query.accountId ? parseInt(req.query.accountId, 10) : null);
  return success(res, rows, 'Reconciliation runs');
});

exports.getReconRun = wrap(async (req, res) => {
  const data = await adminModel.getReconRun(parseInt(req.params.id, 10));
  if (!data.run) return error(res, 'Reconciliation run not found', 404, 'NOT_FOUND');
  return success(res, data, 'Reconciliation run');
});

exports.setReconLine = wrap(async (req, res) => {
  await accountingService.call(() => adminModel.setReconLine(
    parseInt(req.params.id, 10), req.body.IsReconciled, req.user.userId));
  res.locals.entityId = parseInt(req.params.id, 10);
  res.locals.auditDetails = { lineId: req.params.id, isReconciled: req.body.IsReconciled };
  return success(res, null, req.body.IsReconciled ? 'Transaction marked reconciled' : 'Transaction unmarked');
});

exports.completeReconRun = wrap(async (req, res) => {
  await accountingService.call(() => adminModel.completeReconRun(parseInt(req.params.id, 10), req.user.userId));
  res.locals.entityId = parseInt(req.params.id, 10);
  return success(res, null, 'Reconciliation completed');
});

exports.deleteReconRun = wrap(async (req, res) => {
  await accountingService.call(() => adminModel.deleteReconRun(parseInt(req.params.id, 10)));
  res.locals.entityId = parseInt(req.params.id, 10);
  return success(res, null, 'Reconciliation run discarded');
});

/* ---------------- defaults ---------------- */

exports.getDefaults = wrap(async (req, res) => {
  const rows = await settingsService.getByCategory('finance');
  const map = {};
  let parsed = {};
  rows.forEach((r) => {
    map[r.Key] = r.Value;
    try { parsed[r.Key] = JSON.parse(r.Value); } catch (_) { parsed[r.Key] = r.Value; }
  });
  return success(res, { items: rows, map, parsed }, 'Finance defaults');
});

exports.setDefaults = wrap(async (req, res) => {
  const { Key, Value } = req.body;
  await settingsService.upsert(Key, JSON.stringify(Value), 'finance', req.user.userId);
  res.locals.auditDetails = { key: Key, value: Value };
  return success(res, null, 'Finance defaults saved');
});

/* ---------------- dashboard ---------------- */

exports.dashboard = wrap(async (req, res) => {
  const stats = await adminModel.dashboard({
    asOf: req.query.asOf || null,
    branchId: getBranchId(req),
  });
  return success(res, stats, 'Finance dashboard');
});
