const express = require('express');
const router = express.Router();

const { verifyJWT } = require('../middleware/auth');
const { requirePermission } = require('../middleware/rbac');
const { validate } = require('../middleware/validate');
const { audit } = require('../middleware/audit');
const { AUDIT_ACTIONS, MODULES } = require('../config/constants');

const v = require('../validators/mastersValidator');
const ctrl = require('../controllers/mastersController');

router.use(verifyJWT);

/* ----------- Master definitions (the list in the dropdown) ----------- */

router.get(
  '/definitions',
  requirePermission('masters.view'),
  ctrl.listDefinitions
);

router.post(
  '/definitions',
  requirePermission('masters.add'),
  validate(v.createDefinition, 'body'),
  audit(AUDIT_ACTIONS.CREATE, MODULES.MASTERS),
  ctrl.createDefinition
);

router.put(
  '/definitions/:id',
  requirePermission('masters.edit'),
  validate(v.updateDefinition, 'body'),
  audit(AUDIT_ACTIONS.UPDATE, MODULES.MASTERS),
  ctrl.updateDefinition
);

router.delete(
  '/definitions/:id',
  requirePermission('masters.delete'),
  audit(AUDIT_ACTIONS.DELETE, MODULES.MASTERS),
  ctrl.deleteDefinition
);

/* ----------- Master items (the grid rows) ----------- */

router.get(
  '/:definitionId/items',
  requirePermission('masters.view'),
  validate(v.listItems, 'query'),
  ctrl.listItems
);

router.post(
  '/:definitionId/items',
  requirePermission('masters.add'),
  validate(v.createItem, 'body'),
  audit(AUDIT_ACTIONS.CREATE, MODULES.MASTERS),
  ctrl.createItem
);

/* Static ':id' routes for items are namespaced under /items to avoid
   clashing with /definitions/:id */
router.put(
  '/items/:id',
  requirePermission('masters.edit'),
  validate(v.updateItem, 'body'),
  audit(AUDIT_ACTIONS.UPDATE, MODULES.MASTERS),
  ctrl.updateItem
);

router.patch(
  '/items/:id/status',
  requirePermission('masters.status'),
  validate(v.setStatus, 'body'),
  audit(AUDIT_ACTIONS.UPDATE, MODULES.MASTERS),
  ctrl.setItemStatus
);

router.delete(
  '/items/:id',
  requirePermission('masters.delete'),
  audit(AUDIT_ACTIONS.DELETE, MODULES.MASTERS),
  ctrl.deleteItem
);

module.exports = router;
