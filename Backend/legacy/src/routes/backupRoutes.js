const express = require('express');
const router = express.Router();
const { verifyJWT } = require('../middleware/auth');
const { requireRole } = require('../middleware/rbac');
const { audit } = require('../middleware/audit');
const { AUDIT_ACTIONS, MODULES } = require('../config/constants');
const ctrl = require('../controllers/backupController');

router.use(verifyJWT, requireRole('Super Admin'));

router.get('/', ctrl.list);
router.post('/', audit(AUDIT_ACTIONS.SETTINGS_CHANGE, MODULES.SETTINGS), ctrl.create);
router.get('/download/:fileName', ctrl.download);
router.post('/restore', audit(AUDIT_ACTIONS.SETTINGS_CHANGE, MODULES.SETTINGS), ctrl.restore);
router.delete('/:fileName', audit(AUDIT_ACTIONS.DELETE, MODULES.SETTINGS), ctrl.remove);

module.exports = router;
