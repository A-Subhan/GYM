/**
 * Voucher documents controller — Cash / Bank / Journal / Opening TB.
 * Branch scoping: non-super-admins are forced to their own branch.
 * The SP layer enforces every accounting rule; this layer orchestrates.
 */
const docsModel = require('../models/financeDocumentsModel');
const accountingService = require('../services/accountingService');
const { success } = require('../utils/response');
const { wrap } = require('../utils/helpers');

function getBranchId(req, fallbackFromBody = true) {
  if (req.user.isSuperAdmin) {
    const passed = req.query.branchId || (fallbackFromBody ? req.body?.BranchID : undefined);
    return passed ? parseInt(passed, 10) : (req.user.branchId || null);
  }
  return req.user.branchId;
}

/** Factory: family-scoped handlers (CASH / BANK / JOURNAL / OTB). */
function list(family) {
  return wrap(async (req, res) => {
    const page = parseInt(req.query.page, 10) || 1;
    const pageSize = Math.min(200, parseInt(req.query.pageSize, 10) || 15);
    const branchId = getBranchId(req, false);
    const { rows, total } = await docsModel.list(family, {
      page, pageSize,
      direction: req.query.direction || null,
      status: req.query.status || null,
      branchId,
      fromDate: req.query.fromDate || null,
      toDate: req.query.toDate || null,
      search: req.query.search || null,
      bookAccountId: req.query.bookAccountId ? parseInt(req.query.bookAccountId, 10) : null,
      accountId: req.query.accountId ? parseInt(req.query.accountId, 10) : null,
    });
    return res.status(200).json({
      success: true, data: rows, message: 'Vouchers',
      meta: {
        page, pageSize,
        total: total.Total || 0,
        totalPages: Math.ceil((total.Total || 0) / pageSize),
        totalAmount: total.TotalAmount || 0,
      },
    });
  });
}

function buildPayload(family, req) {
  const body = req.body;
  const payload = {
    documentId: req.params.id ? parseInt(req.params.id, 10) : null,
    status: body.Status || 'Posted',
    voucherDate: body.VoucherDate,
    narrative: body.Narrative || null,
    lines: body.Lines,
    userId: req.user.userId,
    branchId: getBranchId(req),
  };
  if (family === 'CASH' || family === 'BANK') {
    payload.direction = body.Direction;
    payload.moneyAccountId = Number(body.MoneyAccountID);
  }
  return payload;
}

function save(family) {
  return wrap(async (req, res) => {
    const result = await accountingService.call(() => docsModel.save(family, buildPayload(family, req)));
    const id = result[Object.keys(result)[0]];
    res.locals.entityId = id;
    res.locals.auditDetails = {
      family, voucherId: id, voucherNo: result.VoucherNo, total: result.TotalAmount ?? result.DebitTotal,
      editing: !!req.params.id,
    };
    return success(res, result, req.params.id ? 'Voucher updated' : 'Voucher saved', null, req.params.id ? 200 : 201);
  });
}

function get(family) {
  return wrap(async (req, res) => {
    const data = await docsModel.get(family, parseInt(req.params.id, 10));
    if (!data.voucher) {
      const err = new Error('Voucher not found'); err.status = 404; err.code = 'NOT_FOUND';
      throw err;
    }
    if (!req.user.isSuperAdmin && data.voucher.BranchID !== req.user.branchId) {
      const err = new Error('You do not have access to this voucher'); err.status = 403; err.code = 'FORBIDDEN';
      throw err;
    }
    return success(res, data, 'Voucher');
  });
}

function remove(family) {
  return wrap(async (req, res) => {
    await accountingService.call(() => docsModel.remove(family, parseInt(req.params.id, 10), req.user.userId));
    res.locals.entityId = parseInt(req.params.id, 10);
    return success(res, null, 'Voucher deleted and reversed in the ledger');
  });
}

/* ---------------- tax heads master ---------------- */

const listTaxHeads = wrap(async (req, res) => {
  const rows = await docsModel.listTaxHeads(req.query.includeInactive === 'true');
  return success(res, rows, 'Tax heads');
});

const createTaxHead = wrap(async (req, res) => {
  const id = await accountingService.call(() => docsModel.createTaxHead({
    code: req.body.Code,
    name: req.body.Name,
    description: req.body.Description || null,
    ratePercent: req.body.RatePercent,
    taxType: req.body.TaxType || null,
  }, req.user.userId));
  res.locals.entityId = id;
  res.locals.auditDetails = { code: req.body.Code, name: req.body.Name };
  return success(res, { taxHeadId: id }, 'Tax head created', null, 201);
});

const updateTaxHead = wrap(async (req, res) => {
  await accountingService.call(() => docsModel.updateTaxHead(parseInt(req.params.id, 10), {
    name: req.body.Name,
    description: req.body.Description || null,
    ratePercent: req.body.RatePercent,
    taxType: req.body.TaxType || null,
  }, req.user.userId));
  res.locals.entityId = parseInt(req.params.id, 10);
  return success(res, null, 'Tax head updated');
});

const setTaxHeadStatus = wrap(async (req, res) => {
  await accountingService.call(() => docsModel.setTaxHeadStatus(
    parseInt(req.params.id, 10), req.body.IsActive, req.user.userId));
  res.locals.entityId = parseInt(req.params.id, 10);
  return success(res, null, req.body.IsActive ? 'Tax head activated' : 'Tax head deactivated');
});


/* post a Draft/Hold voucher */
function post(family) {
  return wrap(async (req, res) => {
    const id = parseInt(req.params.id, 10);
    const result = await accountingService.call(() => docsModel.post(family, id, req.user.userId));
    res.locals.entityId = id;
    res.locals.auditDetails = { family, voucherId: id, voucherNo: result.VoucherNo };
    return success(res, result, 'Voucher posted');
  });
}

/* knock-off allocations */
function getAllocations(family) {
  return wrap(async (req, res) => {
    const rows = await docsModel.getAllocations(family, parseInt(req.params.id, 10));
    return success(res, rows.filter((r) => !r.IsReversed), 'Allocations');
  });
}

function saveAllocations(family) {
  return wrap(async (req, res) => {
    const documentId = parseInt(req.params.id, 10);
    const lineId = parseInt(req.params.lineId, 10);
    await accountingService.call(() => docsModel.saveAllocations(family, documentId, lineId, req.body.Allocations || [], req.user.userId));
    res.locals.auditDetails = { family, documentId, lineId, count: (req.body.Allocations || []).length };
    return success(res, null, 'Allocations saved');
  });
}

module.exports = {
  post, getAllocations, saveAllocations,
  list, save, get, remove,
  listTaxHeads, createTaxHead, updateTaxHead, setTaxHeadStatus,
};
