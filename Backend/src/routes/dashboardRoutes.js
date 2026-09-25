const express = require('express');
const router = express.Router();
const { verifyJWT } = require('../middleware/auth');
const { requirePermission } = require('../middleware/rbac');
const ctrl = require('../controllers/dashboardController');

router.use(verifyJWT);

router.get('/stats', requirePermission('dashboard.view'), ctrl.stats);
router.get('/charts', requirePermission('dashboard.view'), ctrl.charts);

module.exports = router;
