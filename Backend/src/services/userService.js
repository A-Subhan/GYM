const userModel = require('../models/userModel');
const { hashPassword } = require('../utils/hash');

async function listUsers(params) {
  return userModel.listUsers(params);
}

async function getUser(id) {
  return userModel.getUserById(id);
}

async function createUser(data, createdBy) {
  const rawPassword = hashPassword(data.Password);
  const userId = await userModel.createUser({ ...data, PasswordHash: rawPassword, CreatedBy: createdBy });
  return userId;
}

async function updateUser(id, data, updatedBy) {
  await userModel.updateUser(id, data, updatedBy);
}

async function deleteUser(id, deletedBy) {
  await userModel.softDeleteUser(id, deletedBy);
}

async function listRoles() {
  return userModel.listRoles();
}

async function listPermissions() {
  return userModel.listPermissions();
}

async function getRolePermissions(roleId) {
  return userModel.getRolePermissions(roleId);
}

async function setRolePermissions(roleId, permissionIds) {
  await userModel.setRolePermissions(roleId, permissionIds);
  return getRolePermissions(roleId);
}

module.exports = {
  listUsers,
  getUser,
  createUser,
  updateUser,
  deleteUser,
  listRoles,
  listPermissions,
  getRolePermissions,
  setRolePermissions,
};
