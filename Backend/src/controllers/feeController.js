const model = require('../models/feeModel');
const { success, error, paginate } = require('../utils/response');

exports.paymentMethods = async (req, res, next) => {
  try {
    const rows = await model.listPaymentMethods();
    return success(res, rows, 'Payment methods');
  } catch (err) { return error(res, err.message, 500); }
};

exports.listInvoices = async (req, res, next) => {
  try {
    const { page, pageSize, memberId, status, fromDate, toDate } = req.query;
    const { rows, total } = await model.listInvoices({
      page: parseInt(page, 10) || 1,
      pageSize: parseInt(pageSize, 10) || 20,
      memberId: memberId ? parseInt(memberId, 10) : null,
      status: status || null,
      fromDate: fromDate || null,
      toDate: toDate || null,
    });
    return paginate(res, rows, total, page || 1, pageSize || 20, 'Invoices');
  } catch (err) { return error(res, err.message, 500); }
};

exports.createInvoice = async (req, res, next) => {
  try {
    const result = await model.createInvoice(req.body, req.user.userId);
    res.locals.entityId = result.InvoiceID;
    return success(res, result, 'Invoice created', null, 201);
  } catch (err) { return error(res, err.message, 500); }
};

exports.listCollections = async (req, res, next) => {
  try {
    const { page, pageSize, memberId, methodId, fromDate, toDate } = req.query;
    const branchId = req.user.isSuperAdmin ? (req.query.branchId ? parseInt(req.query.branchId, 10) : null) : req.user.branchId;
    const { rows, total, totalAmount } = await model.listCollections({
      page: parseInt(page, 10) || 1,
      pageSize: parseInt(pageSize, 10) || 20,
      memberId: memberId ? parseInt(memberId, 10) : null,
      branchId,
      methodId: methodId ? parseInt(methodId, 10) : null,
      fromDate: fromDate || null,
      toDate: toDate || null,
    });
    return res.status(200).json({
      success: true,
      data: rows,
      message: 'Fee collections',
      meta: {
        page: parseInt(page, 10) || 1,
        pageSize: parseInt(pageSize, 10) || 20,
        total,
        totalAmount,
        totalPages: Math.ceil(total / (parseInt(pageSize, 10) || 20)),
      },
    });
  } catch (err) { return error(res, err.message, 500); }
};

exports.collectFee = async (req, res, next) => {
  try {
    const data = { ...req.body };
    if (!req.user.isSuperAdmin) data.BranchID = req.user.branchId;
    if (!data.BranchID) return error(res, 'BranchID is required', 400, 'BAD_REQUEST');
    const id = await model.collectFee(data, req.user.userId);
    res.locals.entityId = id;
    return success(res, { collectionId: id }, 'Fee collected', null, 201);
  } catch (err) { return error(res, err.message, 500); }
};
