const express = require('express');
const router = express.Router();
const { verifyJWT } = require('../middleware/auth');
const ctrl = require('../controllers/notificationController');

router.use(verifyJWT);

router.get('/', ctrl.list);
router.post('/', ctrl.create);
router.post('/:id/read', ctrl.markRead);
router.post('/read-all', ctrl.markAllRead);
router.delete('/:id', ctrl.remove);

module.exports = router;
