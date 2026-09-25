const express = require('express');
const router = express.Router();
const { verifyJWT } = require('../middleware/auth');
const { validate } = require('../middleware/validate');
const { audit } = require('../middleware/audit');
const { AUDIT_ACTIONS, MODULES } = require('../config/constants');
const authValidator = require('../validators/authValidator');
const ctrl = require('../controllers/authController');

router.post('/login', validate(authValidator.login, 'body'), ctrl.login);
router.post('/logout', verifyJWT, ctrl.logout);
router.post('/refresh', validate(authValidator.refresh, 'body'), ctrl.refresh);
router.post('/heartbeat', verifyJWT, validate(authValidator.refresh, 'body'), ctrl.heartbeat);
router.post(
  '/change-password',
  verifyJWT,
  validate(authValidator.changePassword, 'body'),
  audit(AUDIT_ACTIONS.UPDATE, MODULES.AUTH),
  ctrl.changePassword
);
router.get('/me', verifyJWT, ctrl.me);
router.get('/my-sessions', verifyJWT, ctrl.mySessions);

module.exports = router;
