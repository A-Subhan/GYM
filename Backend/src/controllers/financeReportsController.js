/**
 * Finance reports controller.
 * All reports respect branch scoping via the existing getBranchId pattern.
 */
const reportsModel = require('../models/financeReportsModel');
const accountingService = require('../services/accountingService');
const { success, error } = require('../utils/response');
const { wrap } = require('../utils/helpers');

function getBranchId(req) {
  return req.user.isSuperAdmin
    ? (req.query.branchId ? parseInt(req.query.branchId, 10) : null)
    : req.user.branchId;
}

function intOrNull(v) {
  return v ? parseInt(v, 10) : null;
}

exports.ledger = wrap(async (req, res) => {
  const accountId = intOrNull(req.query.accountId);
  const groupAccountId = intOrNull(req.query.groupAccountId);
  if (!accountId && !groupAccountId) return error(res, 'accountId or groupAccountId is required', 400, 'BAD_REQUEST');
  const data = await accountingService.call(() => reportsModel.ledger({
    accountId,
    groupAccountId,
    fromDate: req.query.fromDate || null,
    toDate: req.query.toDate || null,
    branchId: getBranchId(req),
    voucherTypeId: intOrNull(req.query.voucherTypeId),
    voucherNo: req.query.voucherNo || null,
    partyMemberId: intOrNull(req.query.partyMemberId),
    partySupplierId: intOrNull(req.query.partySupplierId),
    partyStaffId: intOrNull(req.query.partyStaffId),
  }));
  return success(res, data, 'General ledger');
});

exports.trialBalance = wrap(async (req, res) => {
  const data = await accountingService.call(() => reportsModel.trialBalance({
    fromDate: req.query.fromDate || null,
    toDate: req.query.toDate || null,
    branchId: getBranchId(req),
    rollupLevel: intOrNull(req.query.rollupLevel),
  }));
  return success(res, data, 'Trial balance');
});

exports.openingTB = wrap(async (req, res) => {
  const financialYearId = intOrNull(req.query.financialYearId);
  if (!financialYearId) return error(res, 'financialYearId is required', 400, 'BAD_REQUEST');
  const data = await accountingService.call(() => reportsModel.openingTB({
    financialYearId,
    branchId: getBranchId(req),
  }));
  return success(res, data, 'Opening trial balance');
});

exports.balanceSheet = wrap(async (req, res) => {
  const data = await accountingService.call(() => reportsModel.balanceSheet({
    asOf: req.query.asOf || null,
    branchId: getBranchId(req),
  }));
  return success(res, data, 'Balance sheet');
});

exports.profitLoss = wrap(async (req, res) => {
  const data = await accountingService.call(() => reportsModel.profitLoss({
    fromDate: req.query.fromDate || null,
    toDate: req.query.toDate || null,
    branchId: getBranchId(req),
  }));
  return success(res, data, 'Profit and loss');
});

exports.customerAging = wrap(async (req, res) => {
  const data = await accountingService.call(() => reportsModel.aging({
    partyKind: 'Customer',
    asOf: req.query.asOf || null,
    branchId: getBranchId(req),
    partyId: intOrNull(req.query.memberId),
    mode: req.query.mode || null,
  }));
  return success(res, data, 'Customer aging');
});

exports.vendorAging = wrap(async (req, res) => {
  const data = await accountingService.call(() => reportsModel.aging({
    partyKind: 'Vendor',
    asOf: req.query.asOf || null,
    branchId: getBranchId(req),
    partyId: intOrNull(req.query.supplierId),
    mode: req.query.mode || null,
  }));
  return success(res, data, 'Vendor aging');
});

exports.bankStatement = wrap(async (req, res) => {
  const accountId = intOrNull(req.query.accountId);
  if (!accountId) return error(res, 'accountId is required', 400, 'BAD_REQUEST');
  const data = await accountingService.call(() => reportsModel.bankStatement({
    accountId,
    fromDate: req.query.fromDate || null,
    toDate: req.query.toDate || null,
    branchId: getBranchId(req),
  }));
  return success(res, data, 'Bank statement');
});
