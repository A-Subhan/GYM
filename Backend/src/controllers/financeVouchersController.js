/**
 * Ledger read-only controller.
 * Voucher creation/editing/deletion happens through the family document
 * endpoints (financeDocumentsController) — this exposes the unified ledger
 * for the voucher register and voucher view.
 */
const vouchersModel = require('../models/financeVouchersModel');
const accountingService = require('../services/accountingService');
const { success, error } = require('../utils/response');
const { wrap } = require('../utils/helpers');

/* ---------------- voucher types ---------------- */

exports.listTypes = wrap(async (req, res) => {
  const rows = await vouchersModel.listTypes();
  return success(res, rows, 'Voucher types');
});

exports.updateType = wrap(async (req, res) => {
  await accountingService.call(() => vouchersModel.updateType(
    parseInt(req.params.id, 10),
    { title: req.body.Title, prefix: req.body.Prefix, isActive: req.body.IsActive },
    req.user.userId));
  res.locals.entityId = parseInt(req.params.id, 10);
  res.locals.auditDetails = { title: req.body.Title, prefix: req.body.Prefix, isActive: req.body.IsActive };
  return success(res, null, 'Voucher type updated');
});

/* ---------------- ledger (read-only) ---------------- */

exports.list = wrap(async (req, res) => {
  const page = parseInt(req.query.page, 10) || 1;
  const pageSize = Math.min(200, parseInt(req.query.pageSize, 10) || 20);
  const branchId = req.user.isSuperAdmin
    ? (req.query.branchId ? parseInt(req.query.branchId, 10) : null)
    : req.user.branchId;
  const { rows, total } = await vouchersModel.list({
    page, pageSize,
    voucherTypeId: req.query.voucherTypeId ? parseInt(req.query.voucherTypeId, 10) : null,
    status: req.query.status || null,
    branchId,
    fromDate: req.query.fromDate || null,
    toDate: req.query.toDate || null,
    accountId: req.query.accountId ? parseInt(req.query.accountId, 10) : null,
    search: req.query.search || null,
    createdBy: req.query.createdBy ? parseInt(req.query.createdBy, 10) : null,
  });
  return res.status(200).json({
    success: true, data: rows, message: 'Vouchers',
    meta: {
      page, pageSize,
      total: total.Total || 0,
      totalPages: Math.ceil((total.Total || 0) / pageSize),
      totalDebit: total.TotalDebit || 0,
      totalCredit: total.TotalCredit || 0,
    },
  });
});

exports.get = wrap(async (req, res) => {
  const data = await vouchersModel.get(parseInt(req.params.id, 10));
  if (!data.voucher) return error(res, 'Voucher not found', 404, 'NOT_FOUND');
  // branch guard: a non-super-admin cannot read another branch's voucher
  if (!req.user.isSuperAdmin && data.voucher.BranchID !== req.user.branchId) {
    return error(res, 'You do not have access to this voucher', 403, 'FORBIDDEN');
  }
  return success(res, data, 'Voucher');
});
