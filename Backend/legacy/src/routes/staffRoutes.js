const express = require('express');
const router = express.Router();
const { verifyJWT } = require('../middleware/auth');
const { requirePermission, requireAnyPermission } = require('../middleware/rbac');
const { validate } = require('../middleware/validate');
const { audit } = require('../middleware/audit');
const { AUDIT_ACTIONS, MODULES } = require('../config/constants');
const v = require('../validators/staffValidator');
const ctrl = require('../controllers/staffController');

router.use(verifyJWT);

/* Static sub-resources (must be declared before /:id) */
router.get('/departments', ctrl.departments);

/*
 * Staff tagged as trainers (designation-based).
 * Used by member form / workout / diet trainer dropdowns.
 * Master files (designations, educations, ...) live in /masters.
 */
router.get(
  '/trainers',
  requireAnyPermission(['staff.view', 'members.view', 'workouts.view', 'diet.view']),
  ctrl.listTrainers
);

router.get('/', requirePermission('staff.view'), ctrl.list);
router.get('/:id', requirePermission('staff.view'), ctrl.get);
router.post('/', requirePermission('staff.add'), validate(v.create, 'body'), audit(AUDIT_ACTIONS.CREATE, MODULES.STAFF), ctrl.create);
router.put('/:id', requirePermission('staff.edit'), validate(v.update, 'body'), audit(AUDIT_ACTIONS.UPDATE, MODULES.STAFF), ctrl.update);
router.delete('/:id', requirePermission('staff.delete'), audit(AUDIT_ACTIONS.DELETE, MODULES.STAFF), ctrl.remove);

/* Attendance sub-resource */
router.get('/attendance/all', requirePermission('staff.view'), ctrl.listAttendance);
router.post('/attendance', requirePermission('staff.add'), audit(AUDIT_ACTIONS.CREATE, MODULES.STAFF), ctrl.markAttendance);

/* Leaves sub-resource */
router.get('/leaves/all', requirePermission('staff.view'), ctrl.listLeaves);
router.post('/leaves', requirePermission('staff.add'), audit(AUDIT_ACTIONS.CREATE, MODULES.STAFF), ctrl.createLeave);
router.put('/leaves/:id/status', requirePermission('staff.edit'), audit(AUDIT_ACTIONS.UPDATE, MODULES.STAFF), ctrl.updateLeaveStatus);

module.exports = router;
