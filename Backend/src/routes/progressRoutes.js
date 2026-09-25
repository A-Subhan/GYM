const express = require('express');
const router = express.Router();
const { verifyJWT } = require('../middleware/auth');
const { requirePermission } = require('../middleware/rbac');
const { audit } = require('../middleware/audit');
const { AUDIT_ACTIONS, MODULES } = require('../config/constants');
const ctrl = require('../controllers/progressController');

router.use(verifyJWT);

router.get('/', requirePermission('progress.view'), ctrl.list);
router.post('/', requirePermission('progress.add'), audit(AUDIT_ACTIONS.CREATE, MODULES.PROGRESS), ctrl.create);
router.put('/:id', requirePermission('progress.edit'), audit(AUDIT_ACTIONS.UPDATE, MODULES.PROGRESS), ctrl.update);
router.delete('/:id', requirePermission('progress.delete'), audit(AUDIT_ACTIONS.DELETE, MODULES.PROGRESS), ctrl.remove);

router.get('/chart/:memberId', requirePermission('progress.view'), ctrl.chart);
router.post('/:id/photos', requirePermission('progress.add'), audit(AUDIT_ACTIONS.CREATE, MODULES.PROGRESS), ctrl.addPhoto);
router.get('/:id/photos', requirePermission('progress.view'), ctrl.listPhotos);

module.exports = router;
