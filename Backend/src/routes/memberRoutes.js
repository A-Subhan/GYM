const express = require('express');
const router = express.Router();

const {
  verifyJWT
} = require('../middleware/auth');

const {
  requirePermission
} = require('../middleware/rbac');

const {
  validate
} = require('../middleware/validate');

const {
  audit
} = require('../middleware/audit');

const {
  AUDIT_ACTIONS,
  MODULES
} = require('../config/constants');

const upload = require('../middleware/upload');

const v = require('../validators/memberValidator');
const ctrl = require('../controllers/memberController');

router.use(verifyJWT);

router.get(
  '/',
  requirePermission('members.view'),
  ctrl.list
);

router.get(
  '/:id/profile',
  requirePermission('members.view'),
  ctrl.getProfile
);

router.get(
  '/:id/photo',
  requirePermission('members.view'),
  ctrl.photo
);

router.get(
  '/:id/payments',
  requirePermission('members.view'),
  ctrl.payments
);

router.get(
  '/:id/attendance',
  requirePermission('members.view'),
  ctrl.attendance
);

router.get(
  '/:id/memberships',
  requirePermission('members.view'),
  ctrl.memberships
);

router.get(
  '/:id/progress',
  requirePermission('members.view'),
  ctrl.progress
);

router.get(
  '/:id',
  requirePermission('members.view'),
  ctrl.get
);

router.post(
  '/',
  requirePermission('members.add'),
  upload.single('Photo'),
  validate(v.create, 'body'),
  audit(
    AUDIT_ACTIONS.CREATE,
    MODULES.MEMBERS
  ),
  ctrl.create
);

router.put(
  '/:id',
  requirePermission('members.edit'),
  upload.single('Photo'),
  validate(v.update, 'body'),
  audit(
    AUDIT_ACTIONS.UPDATE,
    MODULES.MEMBERS
  ),
  ctrl.update
);

router.delete(
  '/:id',
  requirePermission('members.delete'),
  audit(
    AUDIT_ACTIONS.DELETE,
    MODULES.MEMBERS
  ),
  ctrl.remove
);

module.exports = router;