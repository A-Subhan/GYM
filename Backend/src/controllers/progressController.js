const model = require('../models/progressModel');
const { success, error, paginate } = require('../utils/response');

exports.list = async (req, res, next) => {
  try {
    const { memberId, page, pageSize } = req.query;
    const { rows, total } = await model.list({
      memberId: memberId ? parseInt(memberId, 10) : null,
      page: parseInt(page, 10) || 1,
      pageSize: parseInt(pageSize, 10) || 50,
    });
    return paginate(res, rows, total, page || 1, pageSize || 50, 'Progress entries');
  } catch (err) { return error(res, err.message, 500); }
};

exports.create = async (req, res, next) => {
  try {
    const id = await model.create(req.body, req.user.userId);
    res.locals.entityId = id;
    return success(res, { progressId: id }, 'Progress entry created', null, 201);
  } catch (err) { return error(res, err.message, 500); }
};

exports.update = async (req, res, next) => {
  try {
    await model.update(parseInt(req.params.id, 10), req.body);
    return success(res, null, 'Progress entry updated');
  } catch (err) { return error(res, err.message, 500); }
};

exports.remove = async (req, res, next) => {
  try {
    await model.remove(parseInt(req.params.id, 10));
    return success(res, null, 'Progress entry deleted');
  } catch (err) { return error(res, err.message, 500); }
};

exports.chart = async (req, res, next) => {
  try {
    const rows = await model.chart(parseInt(req.params.memberId, 10));
    return success(res, rows, 'Progress chart data');
  } catch (err) { return error(res, err.message, 500); }
};

exports.addPhoto = async (req, res, next) => {
  try {
    const id = await model.addPhoto(parseInt(req.params.id, 10), req.body.FilePath);
    return success(res, { photoId: id }, 'Photo added', null, 201);
  } catch (err) { return error(res, err.message, 500); }
};

exports.listPhotos = async (req, res, next) => {
  try {
    const rows = await model.listPhotos(parseInt(req.params.id, 10));
    return success(res, rows, 'Progress photos');
  } catch (err) { return error(res, err.message, 500); }
};
