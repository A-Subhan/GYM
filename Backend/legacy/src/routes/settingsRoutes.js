const express = require('express');
const router = express.Router();
const { verifyJWT } = require('../middleware/auth');
const { requirePermission } = require('../middleware/rbac');
const { audit } = require('../middleware/audit');
const { AUDIT_ACTIONS, MODULES } = require('../config/constants');
const ctrl = require('../controllers/settingsController');

router.use(verifyJWT);

router.get('/', requirePermission('settings.view'), ctrl.list);
router.get('/:category', requirePermission('settings.view'), ctrl.getByCategory);
router.put('/', requirePermission('settings.edit'), audit(AUDIT_ACTIONS.SETTINGS_CHANGE, MODULES.SETTINGS), ctrl.update);
router.put('/bulk', requirePermission('settings.edit'), audit(AUDIT_ACTIONS.SETTINGS_CHANGE, MODULES.SETTINGS), ctrl.bulkUpdate);

module.exports = router;
