const userService = require('../services/userService');
const { success, error, paginate } = require('../utils/response');

exports.list = async (req, res, next) => {
  try {
    const { page, pageSize, search, RoleID, BranchID } = req.query;
    // Branch scoping: non-super-admins only see their own branch
    const branchId = req.user.isSuperAdmin ? BranchID : req.user.branchId;
    const { rows, total } = await userService.listUsers({
      page: parseInt(page, 10) || 1,
      pageSize: parseInt(pageSize, 10) || 20,
      search: search || null,
      roleId: RoleID ? parseInt(RoleID, 10) : null,
      branchId: branchId ? parseInt(branchId, 10) : null,
    });
    return paginate(res, rows, total, page || 1, pageSize || 20, 'Users list');
  } catch (err) {
    return error(res, err.message, 500);
  }
};

exports.get = async (req, res, next) => {
  try {
    const user = await userService.getUser(parseInt(req.params.id, 10));
    if (!user) return error(res, 'User not found', 404, 'NOT_FOUND');
    return success(res, user, 'User details');
  } catch (err) {
    return error(res, err.message, 500);
  }
};

exports.create = async (req, res, next) => {
  try {
    const userId = await userService.createUser(req.body, req.user.userId);
    res.locals.entityId = userId;
    return success(res, { userId }, 'User created', null, 201);
  } catch (err) {
    if (err.number === 2627 || /duplicate/i.test(err.message)) {
      return error(res, 'Username or email already exists', 409, 'DUPLICATE');
    }
    return error(res, err.message, 500);
  }
};

exports.update = async (req, res, next) => {
  try {
    await userService.updateUser(parseInt(req.params.id, 10), req.body, req.user.userId);
    return success(res, null, 'User updated');
  } catch (err) {
    return error(res, err.message, 500);
  }
};

exports.remove = async (req, res, next) => {
  try {
    const id = parseInt(req.params.id, 10);
    if (id === req.user.userId) return error(res, 'You cannot delete your own account', 400, 'SELF_DELETE');
    if (id === 1) return error(res, 'Super Admin account cannot be deleted', 400, 'PROTECTED_USER');
    await userService.deleteUser(id, req.user.userId);
    return success(res, null, 'User deleted');
  } catch (err) {
    return error(res, err.message, 500);
  }
};

/* ---------- Roles & Permissions ---------- */

exports.listRoles = async (req, res, next) => {
  try {
    const roles = await userService.listRoles();
    return success(res, roles, 'Roles list');
  } catch (err) {
    return error(res, err.message, 500);
  }
};

exports.listPermissions = async (req, res, next) => {
  try {
    const perms = await userService.listPermissions();
    return success(res, perms, 'Permissions list');
  } catch (err) {
    return error(res, err.message, 500);
  }
};

exports.getRolePermissions = async (req, res, next) => {
  try {
    const perms = await userService.getRolePermissions(parseInt(req.params.roleId, 10));
    return success(res, perms, 'Role permissions');
  } catch (err) {
    return error(res, err.message, 500);
  }
};

exports.setRolePermissions = async (req, res, next) => {
  try {
    const { permissionIds } = req.body;
    if (!Array.isArray(permissionIds)) return error(res, 'permissionIds must be an array', 400, 'BAD_REQUEST');
    const perms = await userService.setRolePermissions(parseInt(req.params.roleId, 10), permissionIds);
    return success(res, perms, 'Role permissions updated');
  } catch (err) {
    return error(res, err.message, 500);
  }
};
