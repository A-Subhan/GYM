const express = require('express');
const router = express.Router();
const { verifyJWT } = require('../middleware/auth');
const { requirePermission } = require('../middleware/rbac');
const { audit } = require('../middleware/audit');
const { AUDIT_ACTIONS, MODULES } = require('../config/constants');
const ctrl = require('../controllers/dietController');

router.use(verifyJWT);

router.get('/', requirePermission('diet.view'), ctrl.list);
router.get('/:id', requirePermission('diet.view'), ctrl.get);
router.post('/', requirePermission('diet.add'), audit(AUDIT_ACTIONS.CREATE, MODULES.DIET), ctrl.create);
router.put('/:id', requirePermission('diet.edit'), audit(AUDIT_ACTIONS.UPDATE, MODULES.DIET), ctrl.update);
router.delete('/:id', requirePermission('diet.delete'), audit(AUDIT_ACTIONS.DELETE, MODULES.DIET), ctrl.remove);

router.post('/:id/items', requirePermission('diet.edit'), audit(AUDIT_ACTIONS.CREATE, MODULES.DIET), ctrl.addItem);
router.delete('/:id/items/:itemId', requirePermission('diet.delete'), audit(AUDIT_ACTIONS.DELETE, MODULES.DIET), ctrl.removeItem);

module.exports = router;
