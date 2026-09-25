const express = require('express');
const router = express.Router();
const { verifyJWT } = require('../middleware/auth');
const { requirePermission } = require('../middleware/rbac');
const { audit } = require('../middleware/audit');
const { AUDIT_ACTIONS, MODULES } = require('../config/constants');
const ctrl = require('../controllers/workoutController');

router.use(verifyJWT);

router.get('/', requirePermission('workouts.view'), ctrl.list);
router.get('/:id', requirePermission('workouts.view'), ctrl.get);
router.post('/', requirePermission('workouts.add'), audit(AUDIT_ACTIONS.CREATE, MODULES.WORKOUTS), ctrl.create);
router.put('/:id', requirePermission('workouts.edit'), audit(AUDIT_ACTIONS.UPDATE, MODULES.WORKOUTS), ctrl.update);
router.delete('/:id', requirePermission('workouts.delete'), audit(AUDIT_ACTIONS.DELETE, MODULES.WORKOUTS), ctrl.remove);

router.post('/:id/items', requirePermission('workouts.edit'), audit(AUDIT_ACTIONS.CREATE, MODULES.WORKOUTS), ctrl.addItem);
router.put('/:id/items/:itemId', requirePermission('workouts.edit'), audit(AUDIT_ACTIONS.UPDATE, MODULES.WORKOUTS), ctrl.updateItem);
router.delete('/:id/items/:itemId', requirePermission('workouts.delete'), audit(AUDIT_ACTIONS.DELETE, MODULES.WORKOUTS), ctrl.removeItem);

module.exports = router;
