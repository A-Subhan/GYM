const express = require('express');
const router = express.Router();
const { verifyJWT } = require('../middleware/auth');
const { requirePermission } = require('../middleware/rbac');
const { validate } = require('../middleware/validate');
const { audit } = require('../middleware/audit');
const { AUDIT_ACTIONS, MODULES } = require('../config/constants');
const Joi = require('joi');
const ctrl = require('../controllers/feeController');

router.use(verifyJWT);

router.get('/payment-methods', ctrl.paymentMethods);

router.get('/invoices', requirePermission('fees.view'), ctrl.listInvoices);
router.post('/invoices', requirePermission('fees.add'), audit(AUDIT_ACTIONS.CREATE, MODULES.FEES), ctrl.createInvoice);

router.get('/collections', requirePermission('fees.view'), ctrl.listCollections);
router.post(
  '/collections',
  requirePermission('fees.add'),
  validate(Joi.object({
    MemberID: Joi.number().integer().required(),
    InvoiceID: Joi.number().integer().allow(null).optional(),
    Amount: Joi.number().precision(2).min(0).required(),
    MethodID: Joi.number().integer().required(),
    TransactionRef: Joi.string().max(100).allow('', null).optional(),
    BranchID: Joi.number().integer().allow(null).optional(),
    Notes: Joi.string().max(500).allow('', null).optional(),
  }), 'body'),
  audit(AUDIT_ACTIONS.CREATE, MODULES.FEES),
  ctrl.collectFee
);

module.exports = router;
