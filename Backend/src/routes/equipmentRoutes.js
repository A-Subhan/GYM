const express = require('express');
const router = express.Router();
const { verifyJWT } = require('../middleware/auth');
const { requirePermission } = require('../middleware/rbac');
const { audit } = require('../middleware/audit');
const { AUDIT_ACTIONS, MODULES } = require('../config/constants');
const ctrl = require('../controllers/equipmentController');

router.use(verifyJWT);

router.get('/', requirePermission('equipment.view'), ctrl.list);
router.get('/:id', requirePermission('equipment.view'), ctrl.get);
router.post('/', requirePermission('equipment.add'), audit(AUDIT_ACTIONS.CREATE, MODULES.EQUIPMENT), ctrl.create);
router.put('/:id', requirePermission('equipment.edit'), audit(AUDIT_ACTIONS.UPDATE, MODULES.EQUIPMENT), ctrl.update);
router.delete('/:id', requirePermission('equipment.delete'), audit(AUDIT_ACTIONS.DELETE, MODULES.EQUIPMENT), ctrl.remove);

router.get('/maintenance/all', requirePermission('equipment.view'), ctrl.listMaintenance);
router.post('/maintenance', requirePermission('equipment.add'), audit(AUDIT_ACTIONS.CREATE, MODULES.EQUIPMENT), ctrl.createMaintenance);
router.post('/maintenance/:id/complete', requirePermission('equipment.edit'), audit(AUDIT_ACTIONS.UPDATE, MODULES.EQUIPMENT), ctrl.completeMaintenance);

module.exports = router;
