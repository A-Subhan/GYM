const model = require('../models/notificationModel');
const { success, error } = require('../utils/response');

exports.list = async (req, res, next) => {
  try {
    const { unreadOnly, page, pageSize } = req.query;
    // Non-super-admins see only their notifications + broadcasts
    const userId = req.user.isSuperAdmin ? null : req.user.userId;
    const { rows, meta } = await model.list({
      userId,
      unreadOnly: unreadOnly === 'true',
      page: parseInt(page, 10) || 1,
      pageSize: parseInt(pageSize, 10) || 50,
    });
    return res.status(200).json({ success: true, data: rows, message: 'Notifications', meta: { ...meta, page: parseInt(page, 10) || 1, pageSize: parseInt(pageSize, 10) || 50 } });
  } catch (err) { return error(res, err.message, 500); }
};

exports.markRead = async (req, res, next) => {
  try {
    await model.markRead(parseInt(req.params.id, 10), req.user.userId);
    return success(res, null, 'Marked as read');
  } catch (err) { return error(res, err.message, 500); }
};

exports.markAllRead = async (req, res, next) => {
  try {
    await model.markAllRead(req.user.userId);
    return success(res, null, 'All marked as read');
  } catch (err) { return error(res, err.message, 500); }
};

exports.create = async (req, res, next) => {
  try {
    const id = await model.create(req.body);
    res.locals.entityId = id;
    return success(res, { notificationId: id }, 'Notification created', null, 201);
  } catch (err) { return error(res, err.message, 500); }
};

exports.remove = async (req, res, next) => {
  try {
    await model.remove(parseInt(req.params.id, 10));
    return success(res, null, 'Notification deleted');
  } catch (err) { return error(res, err.message, 500); }
};
