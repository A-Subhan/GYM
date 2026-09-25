/**
 * Centralized constants — role names, permission codes, audit actions, etc.
 */
const ROLES = {
  SUPER_ADMIN: 'Super Admin',
  OWNER: 'Owner',
  MANAGER: 'Manager',
  RECEPTIONIST: 'Receptionist',
  TRAINER: 'Trainer',
  ACCOUNTANT: 'Accountant',
  STAFF: 'Staff',
};

const ROLE_IDS = {
  SUPER_ADMIN: 1,
  OWNER: 2,
  MANAGER: 3,
  RECEPTIONIST: 4,
  TRAINER: 5,
  ACCOUNTANT: 6,
  STAFF: 7,
};

const AUDIT_ACTIONS = {
  LOGIN: 'LOGIN',
  LOGOUT: 'LOGOUT',
  LOGIN_FAILED: 'LOGIN_FAILED',
  CREATE: 'CREATE',
  UPDATE: 'UPDATE',
  DELETE: 'DELETE',
  PRINT: 'PRINT',
  EXPORT: 'EXPORT',
  SETTINGS_CHANGE: 'SETTINGS_CHANGE',
  HEARTBEAT: 'HEARTBEAT',
  // Finance module actions
  POST: 'POST',
  REVERSE: 'REVERSE',
  CLOSE: 'CLOSE',
  REOPEN: 'REOPEN',
  LOCK: 'LOCK',
  RECONCILE: 'RECONCILE',
};

const MODULES = {
  AUTH: 'auth',
  USERS: 'users',
  ROLES: 'roles',
  BRANCHES: 'branches',
  MEMBERS: 'members',
  MEMBERSHIPS: 'memberships',
  ATTENDANCE: 'attendance',
  FEES: 'fees',
  FINANCE: 'finance',
  PAYROLL: 'payroll',
  STAFF: 'staff',
  MASTERS: 'masters',
  WORKOUTS: 'workouts',
  DIET: 'diet',
  PROGRESS: 'progress',
  EQUIPMENT: 'equipment',
  INVENTORY: 'inventory',
  REPORTS: 'reports',
  SETTINGS: 'settings',
  AUDIT: 'audit',
  DASHBOARD: 'dashboard',
};

module.exports = { ROLES, ROLE_IDS, AUDIT_ACTIONS, MODULES };
