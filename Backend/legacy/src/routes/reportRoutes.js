const express = require('express');
const router = express.Router();
const { verifyJWT } = require('../middleware/auth');
const { requirePermission } = require('../middleware/rbac');
const ctrl = require('../controllers/reportController');

router.use(verifyJWT);

router.get('/members', requirePermission('reports.view'), ctrl.members);
router.get('/attendance', requirePermission('reports.view'), ctrl.attendance);
router.get('/payments', requirePermission('reports.view'), ctrl.payments);
router.get('/salary', requirePermission('reports.view'), ctrl.salary);
router.get('/equipment', requirePermission('reports.view'), ctrl.equipment);
router.get('/inventory', requirePermission('reports.view'), ctrl.inventory);

module.exports = router;
