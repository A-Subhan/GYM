const express = require('express');
const router = express.Router();
const { verifyJWT } = require('../middleware/auth');
const { requirePermission } = require('../middleware/rbac');
const { audit } = require('../middleware/audit');
const { AUDIT_ACTIONS, MODULES } = require('../config/constants');
const ctrl = require('../controllers/attendanceController');
const Joi = require('joi');
const { validate } = require('../middleware/validate');

const checkInSchema = Joi.object({
  memberId: Joi.number().integer().required(),
  branchId: Joi.number().integer().optional(),
  method: Joi.string().valid('Manual', 'QR', 'Barcode', 'RFID', 'Biometric').optional(),
});

router.use(verifyJWT);

router.get('/', requirePermission('attendance.view'), ctrl.list);
router.get('/today/count', requirePermission('attendance.view'), ctrl.todayCount);
router.post('/check-in', requirePermission('attendance.add'), validate(checkInSchema, 'body'), audit(AUDIT_ACTIONS.CREATE, MODULES.ATTENDANCE), ctrl.checkIn);
router.post('/check-out/:id', requirePermission('attendance.edit'), audit(AUDIT_ACTIONS.UPDATE, MODULES.ATTENDANCE), ctrl.checkOut);

module.exports = router;
