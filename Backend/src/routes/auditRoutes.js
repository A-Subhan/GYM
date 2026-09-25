const express = require('express');
const router = express.Router();
const { verifyJWT } = require('../middleware/auth');
const { requirePermission } = require('../middleware/rbac');
const ctrl = require('../controllers/auditController');

router.use(verifyJWT);

router.get('/', requirePermission('audit.view'), ctrl.list);

module.exports = router;
