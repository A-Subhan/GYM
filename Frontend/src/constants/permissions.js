/**
 * Permission codes — must match backend permission table.
 * Used by routes/nav to gate UI elements.
 */
export const PERMISSIONS = {
  // Dashboard
  DASHBOARD_VIEW: 'dashboard.view',
  // Members
  MEMBERS_VIEW: 'members.view', MEMBERS_ADD: 'members.add', MEMBERS_EDIT: 'members.edit',
  MEMBERS_DELETE: 'members.delete', MEMBERS_PRINT: 'members.print', MEMBERS_EXPORT: 'members.export',
  // Memberships
  MEMBERSHIPS_VIEW: 'memberships.view', MEMBERSHIPS_ADD: 'memberships.add',
  MEMBERSHIPS_EDIT: 'memberships.edit', MEMBERSHIPS_DELETE: 'memberships.delete',
  MEMBERSHIPS_EXPORT: 'memberships.export',
  // Master Files
  MASTERS_VIEW: 'masters.view', MASTERS_ADD: 'masters.add',
  MASTERS_EDIT: 'masters.edit', MASTERS_DELETE: 'masters.delete',
  MASTERS_STATUS: 'masters.status',
  // Attendance
  ATTENDANCE_VIEW: 'attendance.view', ATTENDANCE_ADD: 'attendance.add',
  ATTENDANCE_EDIT: 'attendance.edit', ATTENDANCE_DELETE: 'attendance.delete', ATTENDANCE_EXPORT: 'attendance.export',
  // Fees
  FEES_VIEW: 'fees.view', FEES_ADD: 'fees.add', FEES_EDIT: 'fees.edit',
  FEES_DELETE: 'fees.delete', FEES_PRINT: 'fees.print', FEES_EXPORT: 'fees.export',
  // Finance
  FINANCE_VIEW: 'finance.view', FINANCE_ADD: 'finance.add',
  FINANCE_EDIT: 'finance.edit', FINANCE_DELETE: 'finance.delete', FINANCE_EXPORT: 'finance.export',
  // Finance & Accounting module
  FINANCE_POST: 'finance.post', FINANCE_REVERSE: 'finance.reverse',
  FINANCE_PERIODS: 'finance.periods', FINANCE_RECONCILE: 'finance.reconcile',
  FINANCE_SETTINGS: 'finance.settings', FINANCE_COA: 'finance.coa', FINANCE_REPORTS: 'finance.reports',
  // Settings
  SETTINGS_VIEW: 'settings.view', SETTINGS_EDIT: 'settings.edit',
  BRANCHES_VIEW: 'branches.view', BRANCHES_ADD: 'branches.add', BRANCHES_EDIT: 'branches.edit', BRANCHES_DELETE: 'branches.delete',
  USERS_VIEW: 'users.view', USERS_ADD: 'users.add', USERS_EDIT: 'users.edit', USERS_DELETE: 'users.delete',
  AUDIT_VIEW: 'audit.view', AUDIT_EXPORT: 'audit.export',
};

export const ROLES = {
  SUPER_ADMIN: 'Super Admin',
  OWNER: 'Owner',
  MANAGER: 'Manager',
  RECEPTIONIST: 'Receptionist',
  TRAINER: 'Trainer',
  ACCOUNTANT: 'Accountant',
  STAFF: 'Staff',
};
