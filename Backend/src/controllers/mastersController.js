const model = require('../models/mastersModel');
const { success, error, paginate } = require('../utils/response');

/* Maps stored-procedure THROW/RAISERROR messages to proper HTTP responses */
function mapError(res, err) {
  if (/not found/i.test(err.message)) {
    return error(res, err.message, 404, 'NOT_FOUND');
  }
  if (/cannot be deleted because/i.test(err.message)) {
    return error(res, err.message, 409, 'DELETE_BLOCKED');
  }
  if (/already exists|already in use/i.test(err.message)) {
    return error(res, err.message, 409, 'DUPLICATE');
  }
  if (/still has records/i.test(err.message)) {
    return error(res, err.message, 409, 'DEFINITION_NOT_EMPTY');
  }
  if (/Branch is required/i.test(err.message)) {
    return error(res, err.message, 400, 'BAD_REQUEST');
  }
  if (/duplicate key/i.test(err.message)) {
    return error(res, 'This record already exists (concurrent entry).', 409, 'DUPLICATE');
  }
  return error(res, err.message, 500);
}

/* ----------- Master definitions ----------- */

exports.listDefinitions = async (req, res) => {
  try {
    const rows = await model.listDefinitions();
    return success(res, rows, 'Master files');
  } catch (err) { return mapError(res, err); }
};

exports.createDefinition = async (req, res) => {
  try {
    const result = await model.createDefinition(req.body, req.user.userId);
    res.locals.entityId = result.MasterDefinitionID;
    return success(res, result, 'Master file created', null, 201);
  } catch (err) { return mapError(res, err); }
};

exports.updateDefinition = async (req, res) => {
  try {
    await model.updateDefinition(parseInt(req.params.id, 10), req.body, req.user.userId);
    return success(res, null, 'Master file updated');
  } catch (err) { return mapError(res, err); }
};

exports.deleteDefinition = async (req, res) => {
  try {
    await model.deleteDefinition(parseInt(req.params.id, 10));
    return success(res, null, 'Master file deleted');
  } catch (err) { return mapError(res, err); }
};

/* ----------- Master items ----------- */

exports.listItems = async (req, res) => {
  try {
    const { search, status, BranchID, page, pageSize } = req.query;

    /* Branch scoping: branch-scope masters are filtered by the caller's
       branch unless a super admin explicitly passes ?BranchID= */
    let branchId = null;
    if (BranchID) branchId = parseInt(BranchID, 10);
    else if (!req.user.isSuperAdmin) branchId = req.user.branchId || null;

    const { rows, total } = await model.listItems({
      definitionId: parseInt(req.params.definitionId, 10),
      search: search || null,
      isActive: status === 'active' ? 1 : status === 'inactive' ? 0 : undefined,
      branchId,
      page: parseInt(page, 10) || 1,
      pageSize: parseInt(pageSize, 10) || 20,
    });
    return paginate(res, rows, total, parseInt(page, 10) || 1, parseInt(pageSize, 10) || 20, 'Master records');
  } catch (err) { return mapError(res, err); }
};

exports.createItem = async (req, res) => {
  try {
    const definitionId = parseInt(req.params.definitionId, 10);

    /* Branch-scope masters: non-super-admins always create in their own branch */
    let branchId = req.body.BranchID || null;
    if (!req.user.isSuperAdmin) branchId = req.user.branchId || null;

    const result = await model.createItem({
      definitionId,
      name: req.body.Name,
      branchId,
      createdBy: req.user.userId,
    });
    res.locals.entityId = result.MasterItemID;
    return success(res, result, 'Record added', null, 201);
  } catch (err) { return mapError(res, err); }
};

exports.updateItem = async (req, res) => {
  try {
    await model.updateItem(parseInt(req.params.id, 10), req.body, req.user.userId);
    return success(res, null, 'Record updated');
  } catch (err) { return mapError(res, err); }
};

exports.setItemStatus = async (req, res) => {
  try {
    await model.setItemStatus(parseInt(req.params.id, 10), req.body.IsActive === true, req.user.userId);
    return success(res, null, req.body.IsActive ? 'Record activated' : 'Record deactivated');
  } catch (err) { return mapError(res, err); }
};

exports.deleteItem = async (req, res) => {
  try {
    await model.deleteItem(parseInt(req.params.id, 10));
    return success(res, null, 'Record deleted');
  } catch (err) { return mapError(res, err); }
};
