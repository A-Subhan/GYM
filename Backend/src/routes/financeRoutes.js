const express = require('express');
const router = express.Router();
const { verifyJWT } = require('../middleware/auth');
const { requirePermission, requireAnyPermission } = require('../middleware/rbac');
const { validate } = require('../middleware/validate');
const { audit } = require('../middleware/audit');
const { AUDIT_ACTIONS, MODULES } = require('../config/constants');
const upload = require('../middleware/upload');
const ctrl = require('../controllers/financeVouchersController');
const coaCtrl = require('../controllers/financeCoaController');
const adminCtrl = require('../controllers/financeAdminController');
const reportsCtrl = require('../controllers/financeReportsController');
const docsCtrl = require('../controllers/financeDocumentsController');
const V = require('../validators/financeValidator');

router.use(verifyJWT);

/* ================================================================
   LEDGER READ-ONLY (voucher register + voucher view)
   All voucher mutations happen through the family document endpoints
   below — the generic ledger API is intentionally read-only so the
   accounting rules cannot be bypassed through direct requests.
   ================================================================ */

router.get('/vouchers', requirePermission('finance.view'), ctrl.list);
router.get('/vouchers/:id', requirePermission('finance.view'), ctrl.get);

/* ---------------- chart of accounts ---------------- */

router.get('/coa', requirePermission('finance.coa'), coaCtrl.list);
// full hierarchy for the voucher account picker (visible tree, detail-only selection)
router.get('/accounts-tree', requireAnyPermission(['finance.view', 'finance.add', 'finance.coa']), coaCtrl.list);
router.get('/coa/structure', requireAnyPermission(['finance.coa', 'finance.settings', 'finance.view']), coaCtrl.getStructure);
router.put('/coa/structure', requirePermission('finance.settings'), validate(V.coaStructureSchema, 'body'), audit(AUDIT_ACTIONS.SETTINGS_CHANGE, MODULES.FINANCE), coaCtrl.setStructure);
router.get('/coa/selectors', requireAnyPermission(['finance.view', 'finance.add']), coaCtrl.selector);
router.get('/coa/next-code', requireAnyPermission(['finance.coa', 'finance.view']), coaCtrl.nextCode);
router.get('/coa/:id', requirePermission('finance.coa'), coaCtrl.get);
router.post('/coa', requirePermission('finance.coa'), validate(V.accountCreateSchema, 'body'), audit(AUDIT_ACTIONS.CREATE, MODULES.FINANCE), coaCtrl.create);
router.put('/coa/:id', requirePermission('finance.coa'), validate(V.accountUpdateSchema, 'body'), audit(AUDIT_ACTIONS.UPDATE, MODULES.FINANCE), coaCtrl.update);
router.patch('/coa/:id/status', requirePermission('finance.coa'), validate(V.accountStatusSchema, 'body'), audit(AUDIT_ACTIONS.UPDATE, MODULES.FINANCE), coaCtrl.setStatus);
router.post('/coa/:id/photo', requirePermission('finance.coa'), upload.single('Photo'), audit(AUDIT_ACTIONS.UPDATE, MODULES.FINANCE), coaCtrl.setPhoto);
router.delete('/coa/:id', requirePermission('finance.coa'), audit(AUDIT_ACTIONS.DELETE, MODULES.FINANCE), coaCtrl.remove);

/* ---------------- voucher types (numbering / prefixes) ---------------- */

router.get('/voucher-types', requireAnyPermission(['finance.view', 'finance.add', 'finance.settings']), ctrl.listTypes);
router.put('/voucher-types/:id', requirePermission('finance.settings'), validate(V.voucherTypeUpdateSchema, 'body'), audit(AUDIT_ACTIONS.SETTINGS_CHANGE, MODULES.FINANCE), ctrl.updateType);

/* ================================================================
   VOUCHER DOCUMENTS — one family per storage table
   Cash (CRV/CPV), Bank (BRV/BPV), Journal, Opening Trial Balance.
   Save posts through the central engine atomically; edit keeps the
   date immutable; delete soft-deletes and reverses the ledger.
   ================================================================ */

const FAMILIES = [
  { path: 'cash-vouchers', family: 'CASH', permView: 'finance.view' },
  { path: 'bank-vouchers', family: 'BANK', permView: 'finance.view' },
  { path: 'journal-vouchers', family: 'JOURNAL', permView: 'finance.view' },
  { path: 'opening-trial-balances', family: 'OTB', permView: 'finance.view' },
];

for (const f of FAMILIES) {
  router.get(`/${f.path}`, requirePermission(f.permView), docsCtrl.list(f.family));
  router.post(`/${f.path}`, requirePermission('finance.add'), validate(V.documentSchema, 'body'), audit(AUDIT_ACTIONS.CREATE, MODULES.FINANCE), docsCtrl.save(f.family));
  router.get(`/${f.path}/:id`, requirePermission(f.permView), docsCtrl.get(f.family));
  router.put(`/${f.path}/:id`, requirePermission('finance.edit'), validate(V.documentSchema, 'body'), audit(AUDIT_ACTIONS.UPDATE, MODULES.FINANCE), docsCtrl.save(f.family));
  router.post(`/${f.path}/:id/post`, requirePermission('finance.post'), audit(AUDIT_ACTIONS.POST, MODULES.FINANCE), docsCtrl.post(f.family));
  router.get(`/${f.path}/:id/allocations`, requirePermission(f.permView), docsCtrl.getAllocations(f.family));
  router.put(`/${f.path}/:id/lines/:lineId/allocations`, requirePermission('finance.edit'), audit(AUDIT_ACTIONS.UPDATE, MODULES.FINANCE), docsCtrl.saveAllocations(f.family));
  router.delete(`/${f.path}/:id`, requirePermission('finance.delete'), audit(AUDIT_ACTIONS.DELETE, MODULES.FINANCE), docsCtrl.remove(f.family));
}

/* ---------------- tax heads master ---------------- */

router.get('/tax-heads', requireAnyPermission(['finance.view', 'finance.coa']), docsCtrl.listTaxHeads);
router.post('/tax-heads', requirePermission('finance.coa'), validate(V.taxHeadCreateSchema, 'body'), audit(AUDIT_ACTIONS.CREATE, MODULES.FINANCE), docsCtrl.createTaxHead);
router.put('/tax-heads/:id', requirePermission('finance.coa'), validate(V.taxHeadUpdateSchema, 'body'), audit(AUDIT_ACTIONS.UPDATE, MODULES.FINANCE), docsCtrl.updateTaxHead);
router.patch('/tax-heads/:id/status', requirePermission('finance.coa'), validate(V.accountStatusSchema, 'body'), audit(AUDIT_ACTIONS.UPDATE, MODULES.FINANCE), docsCtrl.setTaxHeadStatus);

/* ---------------- financial years + periods ---------------- */

router.get('/years', requireAnyPermission(['finance.view', 'finance.periods', 'finance.reports']), adminCtrl.listYears);
router.post('/years', requirePermission('finance.periods'), validate(V.yearCreateSchema, 'body'), audit(AUDIT_ACTIONS.CREATE, MODULES.FINANCE), adminCtrl.createYear);
router.post('/years/:id/close', requirePermission('finance.periods'), validate(V.yearCloseSchema, 'body'), audit(AUDIT_ACTIONS.CLOSE, MODULES.FINANCE), adminCtrl.closeYear);
router.patch('/years/:id/status', requirePermission('finance.periods'), validate(V.yearStatusSchema, 'body'), audit(AUDIT_ACTIONS.UPDATE, MODULES.FINANCE), adminCtrl.setYearStatus);
router.get('/years/:id/periods', requireAnyPermission(['finance.view', 'finance.periods', 'finance.reports']), adminCtrl.listPeriods);
router.patch('/periods/:id/status', requirePermission('finance.periods'), validate(V.periodStatusSchema, 'body'), audit(AUDIT_ACTIONS.UPDATE, MODULES.FINANCE), adminCtrl.setPeriodStatus);

/* ---------------- defaults + mappings ---------------- */

router.get('/defaults', requirePermission('finance.settings'), adminCtrl.getDefaults);
router.put('/defaults', requirePermission('finance.settings'), validate(V.defaultsSchema, 'body'), audit(AUDIT_ACTIONS.SETTINGS_CHANGE, MODULES.FINANCE), adminCtrl.setDefaults);
router.get('/mappings', requireAnyPermission(['finance.settings', 'finance.view']), adminCtrl.listMappings);
router.put('/mappings', requirePermission('finance.settings'), validate(V.mappingSchema, 'body'), audit(AUDIT_ACTIONS.SETTINGS_CHANGE, MODULES.FINANCE), adminCtrl.setMapping);
router.delete('/mappings/:id', requirePermission('finance.settings'), audit(AUDIT_ACTIONS.DELETE, MODULES.FINANCE), adminCtrl.deleteMapping);

/* ---------------- user report formats ---------------- */

router.get('/report-formats', requireAnyPermission(['finance.view', 'finance.reports']), adminCtrl.listFormats);
router.post('/report-formats', requireAnyPermission(['finance.view', 'finance.reports']), validate(V.formatSaveSchema, 'body'), audit(AUDIT_ACTIONS.CREATE, MODULES.FINANCE), adminCtrl.saveFormat);
router.delete('/report-formats/:id', requireAnyPermission(['finance.view', 'finance.reports']), audit(AUDIT_ACTIONS.DELETE, MODULES.FINANCE), adminCtrl.deleteFormat);

/* ---------------- bank reconciliation ---------------- */

router.get('/recon/runs', requirePermission('finance.reconcile'), adminCtrl.listReconRuns);
router.post('/recon/runs', requirePermission('finance.reconcile'), validate(V.reconCreateSchema, 'body'), audit(AUDIT_ACTIONS.RECONCILE, MODULES.FINANCE), adminCtrl.createReconRun);
router.get('/recon/runs/:id', requirePermission('finance.reconcile'), adminCtrl.getReconRun);
router.patch('/recon/lines/:id', requirePermission('finance.reconcile'), validate(V.reconLineSchema, 'body'), audit(AUDIT_ACTIONS.UPDATE, MODULES.FINANCE), adminCtrl.setReconLine);
router.post('/recon/runs/:id/complete', requirePermission('finance.reconcile'), audit(AUDIT_ACTIONS.RECONCILE, MODULES.FINANCE), adminCtrl.completeReconRun);
router.delete('/recon/runs/:id', requirePermission('finance.reconcile'), audit(AUDIT_ACTIONS.DELETE, MODULES.FINANCE), adminCtrl.deleteReconRun);

/* ---------------- reports ---------------- */

router.get('/dashboard', requirePermission('finance.view'), adminCtrl.dashboard);
router.get('/ledger', requirePermission('finance.reports'), reportsCtrl.ledger);
router.get('/trial-balance', requirePermission('finance.reports'), reportsCtrl.trialBalance);
router.get('/opening-tb', requirePermission('finance.reports'), reportsCtrl.openingTB);
router.get('/balance-sheet', requirePermission('finance.reports'), reportsCtrl.balanceSheet);
router.get('/profit-loss', requirePermission('finance.reports'), reportsCtrl.profitLoss);
router.get('/aging/customer', requirePermission('finance.reports'), reportsCtrl.customerAging);
router.get('/aging/vendor', requirePermission('finance.reports'), reportsCtrl.vendorAging);
router.get('/bank-statement', requirePermission('finance.reports'), reportsCtrl.bankStatement);

module.exports = router;
