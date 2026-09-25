const express = require('express');
const router = express.Router();
const { verifyJWT } = require('../middleware/auth');
const { requirePermission } = require('../middleware/rbac');
const { validate } = require('../middleware/validate');
const { audit } = require('../middleware/audit');
const { AUDIT_ACTIONS, MODULES } = require('../config/constants');
const userValidator = require('../validators/userValidator');
const ctrl = require('../controllers/userController');

router.use(verifyJWT);

router.get('/', requirePermission('users.view'), ctrl.list);
router.get('/:id', requirePermission('users.view'), ctrl.get);
router.post(
  '/',
  requirePermission('users.add'),
  validate(userValidator.create, 'body'),
  audit(AUDIT_ACTIONS.CREATE, MODULES.USERS),
  ctrl.create
);
router.put(
  '/:id',
  requirePermission('users.edit'),
  validate(userValidator.update, 'body'),
  audit(AUDIT_ACTIONS.UPDATE, MODULES.USERS),
  ctrl.update
);
router.delete(
  '/:id',
  requirePermission('users.delete'),
  audit(AUDIT_ACTIONS.DELETE, MODULES.USERS),
  ctrl.remove
);

/* Roles & Permissions */
router.get('/meta/roles', ctrl.listRoles);
router.get('/meta/permissions', ctrl.listPermissions);
router.get('/meta/roles/:roleId/permissions', ctrl.getRolePermissions);
router.put('/meta/roles/:roleId/permissions', requirePermission('users.edit'), audit(AUDIT_ACTIONS.UPDATE, MODULES.ROLES), ctrl.setRolePermissions);

module.exports = router;
