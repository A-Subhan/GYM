const express = require('express');

const router = express.Router();

const { verifyJWT } = require('../middleware/auth');
const { requirePermission } = require('../middleware/rbac');
const { validate } = require('../middleware/validate');
const { audit } = require('../middleware/audit');

const {
  AUDIT_ACTIONS,
  MODULES
} = require('../config/constants');

const v = require('../validators/membershipValidator');
const ctrl = require('../controllers/membershipController');

router.use(verifyJWT);

/* Membership plans */

router.get(
  '/plans',
  requirePermission('memberships.view'),
  ctrl.listPlans
);

router.post(
  '/plans',
  requirePermission('memberships.add'),
  validate(v.createPlan, 'body'),
  audit(
    AUDIT_ACTIONS.CREATE,
    MODULES.MEMBERSHIPS
  ),
  ctrl.createPlan
);

router.put(
  '/plans/:id',
  requirePermission('memberships.edit'),
  validate(v.updatePlan, 'body'),
  audit(
    AUDIT_ACTIONS.UPDATE,
    MODULES.MEMBERSHIPS
  ),
  ctrl.updatePlan
);

router.delete(
  '/plans/:id',
  requirePermission('memberships.delete'),
  audit(
    AUDIT_ACTIONS.DELETE,
    MODULES.MEMBERSHIPS
  ),
  ctrl.deletePlan
);

module.exports = router;
