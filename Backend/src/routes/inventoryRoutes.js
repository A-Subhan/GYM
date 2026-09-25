const express = require('express');
const router = express.Router();
const { verifyJWT } = require('../middleware/auth');
const { requirePermission } = require('../middleware/rbac');
const { audit } = require('../middleware/audit');
const { AUDIT_ACTIONS, MODULES } = require('../config/constants');
const ctrl = require('../controllers/inventoryController');

router.use(verifyJWT);

/* Suppliers */
router.get('/suppliers', ctrl.listSuppliers);
router.post('/suppliers', requirePermission('inventory.add'), audit(AUDIT_ACTIONS.CREATE, MODULES.INVENTORY), ctrl.createSupplier);
router.put('/suppliers/:id', requirePermission('inventory.edit'), audit(AUDIT_ACTIONS.UPDATE, MODULES.INVENTORY), ctrl.updateSupplier);
router.delete('/suppliers/:id', requirePermission('inventory.delete'), audit(AUDIT_ACTIONS.DELETE, MODULES.INVENTORY), ctrl.deleteSupplier);

/* Items */
router.get('/', requirePermission('inventory.view'), ctrl.list);
router.post('/', requirePermission('inventory.add'), audit(AUDIT_ACTIONS.CREATE, MODULES.INVENTORY), ctrl.createItem);
router.put('/:id', requirePermission('inventory.edit'), audit(AUDIT_ACTIONS.UPDATE, MODULES.INVENTORY), ctrl.updateItem);
router.delete('/:id', requirePermission('inventory.delete'), audit(AUDIT_ACTIONS.DELETE, MODULES.INVENTORY), ctrl.deleteItem);

/* Transactions */
router.get('/transactions/all', requirePermission('inventory.view'), ctrl.listTransactions);
router.post('/transactions', requirePermission('inventory.add'), audit(AUDIT_ACTIONS.CREATE, MODULES.INVENTORY), ctrl.createTransaction);

module.exports = router;
