const express = require('express');
const router = express.Router();
const { verifyJWT } = require('../middleware/auth');
const { requirePermission } = require('../middleware/rbac');
const { audit } = require('../middleware/audit');
const { AUDIT_ACTIONS, MODULES } = require('../config/constants');
const ctrl = require('../controllers/payrollController');

router.use(verifyJWT);

router.get('/', requirePermission('payroll.view'), ctrl.list);
router.get('/:id', requirePermission('payroll.view'), ctrl.get);
router.post('/generate', requirePermission('payroll.add'), audit(AUDIT_ACTIONS.CREATE, MODULES.PAYROLL), ctrl.generate);
router.post('/generate-all', requirePermission('payroll.add'), audit(AUDIT_ACTIONS.CREATE, MODULES.PAYROLL), ctrl.generateAll);
router.put('/:id', requirePermission('payroll.edit'), audit(AUDIT_ACTIONS.UPDATE, MODULES.PAYROLL), ctrl.update);
router.post('/:id/mark-paid', requirePermission('payroll.edit'), audit(AUDIT_ACTIONS.UPDATE, MODULES.PAYROLL), ctrl.markPaid);

module.exports = router;
