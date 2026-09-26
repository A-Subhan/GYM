const express = require('express');
const router = express.Router();
const { verifyJWT } = require('../middleware/auth');
const { requirePermission } = require('../middleware/rbac');
const { validate } = require('../middleware/validate');
const { audit } = require('../middleware/audit');
const { AUDIT_ACTIONS, MODULES } = require('../config/constants');
const v = require('../validators/branchValidator');
const ctrl = require('../controllers/branchController');

router.use(verifyJWT);

router.get('/', requirePermission('branches.view'), ctrl.list);
router.get('/:id', requirePermission('branches.view'), ctrl.get);
router.post('/', requirePermission('branches.add'), validate(v.createBranch, 'body'), audit(AUDIT_ACTIONS.CREATE, MODULES.BRANCHES), ctrl.create);
router.put('/:id', requirePermission('branches.edit'), validate(v.updateBranch, 'body'), audit(AUDIT_ACTIONS.UPDATE, MODULES.BRANCHES), ctrl.update);
router.delete('/:id', requirePermission('branches.delete'), audit(AUDIT_ACTIONS.DELETE, MODULES.BRANCHES), ctrl.remove);

module.exports = router;
