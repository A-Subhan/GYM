// Permission catalog — granular per spec §42
// Modules: dashboard, members, memberships, attendance, fees, finance, vouchers,
// coa, tax, cheques, financeReports, prospects, freeze, followups, workouts, diet,
// progress, equipment, inventory, pos, staff, shifts, calendar, leaves, overtime,
// payroll, branches, users, roles, audit, company, accountMappings, adminDefaults

export const PERMISSIONS = [
  // Dashboard
  { code: 'dashboard.view', module: 'dashboard', action: 'view', description: 'View dashboard' },

  // Members
  { code: 'members.view', module: 'members', action: 'view' },
  { code: 'members.add', module: 'members', action: 'add' },
  { code: 'members.edit', module: 'members', action: 'edit' },
  { code: 'members.delete', module: 'members', action: 'delete' },
  { code: 'members.print', module: 'members', action: 'print' },
  { code: 'members.export', module: 'members', action: 'export' },
  { code: 'members.status', module: 'members', action: 'status', description: 'Change member status (bulk)' },

  // Memberships
  { code: 'memberships.view', module: 'memberships', action: 'view' },
  { code: 'memberships.add', module: 'memberships', action: 'add' },
  { code: 'memberships.edit', module: 'memberships', action: 'edit' },
  { code: 'memberships.delete', module: 'memberships', action: 'delete' },
  { code: 'memberships.export', module: 'memberships', action: 'export' },

  // Attendance
  { code: 'attendance.view', module: 'attendance', action: 'view' },
  { code: 'attendance.add', module: 'attendance', action: 'add' },
  { code: 'attendance.edit', module: 'attendance', action: 'edit' },
  { code: 'attendance.delete', module: 'attendance', action: 'delete' },
  { code: 'attendance.export', module: 'attendance', action: 'export' },

  // Fees
  { code: 'fees.view', module: 'fees', action: 'view' },
  { code: 'fees.add', module: 'fees', action: 'add' },
  { code: 'fees.edit', module: 'fees', action: 'edit' },
  { code: 'fees.delete', module: 'fees', action: 'delete' },
  { code: 'fees.print', module: 'fees', action: 'print' },
  { code: 'fees.export', module: 'fees', action: 'export' },
  { code: 'fees.post', module: 'fees', action: 'post', description: 'Post fee payment (auto-voucher)' },

  // Finance
  { code: 'finance.view', module: 'finance', action: 'view' },
  { code: 'finance.add', module: 'finance', action: 'add' },
  { code: 'finance.edit', module: 'finance', action: 'edit' },
  { code: 'finance.delete', module: 'finance', action: 'delete' },
  { code: 'finance.export', module: 'finance', action: 'export' },
  { code: 'finance.post', module: 'finance', action: 'post', description: 'Post voucher' },
  { code: 'finance.reverse', module: 'finance', action: 'reverse', description: 'Reverse voucher' },
  { code: 'finance.periods', module: 'finance', action: 'periods', description: 'Manage accounting periods' },
  { code: 'finance.reconcile', module: 'finance', action: 'reconcile', description: 'Bank reconciliation' },
  { code: 'finance.settings', module: 'finance', action: 'settings', description: 'Finance defaults' },
  { code: 'finance.coa', module: 'finance', action: 'coa', description: 'Chart of Accounts' },
  { code: 'finance.reports', module: 'finance', action: 'reports', description: 'Finance reports' },
  { code: 'finance.config', module: 'finance', action: 'configure', description: 'Configure finance mappings' },

  // Vouchers
  { code: 'vouchers.view', module: 'vouchers', action: 'view' },
  { code: 'vouchers.add', module: 'vouchers', action: 'add' },
  { code: 'vouchers.edit', module: 'vouchers', action: 'edit' },
  { code: 'vouchers.delete', module: 'vouchers', action: 'delete' },
  { code: 'vouchers.print', module: 'vouchers', action: 'print' },
  { code: 'vouchers.post', module: 'vouchers', action: 'post' },
  { code: 'vouchers.reverse', module: 'vouchers', action: 'reverse' },
  { code: 'vouchers.export', module: 'vouchers', action: 'export' },

  // Cheques
  { code: 'cheques.view', module: 'cheques', action: 'view' },
  { code: 'cheques.status', module: 'cheques', action: 'status', description: 'Update cheque status (bulk)' },
  { code: 'cheques.export', module: 'cheques', action: 'export' },

  // Tax Heads
  { code: 'tax.view', module: 'tax', action: 'view' },
  { code: 'tax.add', module: 'tax', action: 'add' },
  { code: 'tax.edit', module: 'tax', action: 'edit' },
  { code: 'tax.delete', module: 'tax', action: 'delete' },

  // Prospects
  { code: 'prospects.view', module: 'prospects', action: 'view' },
  { code: 'prospects.add', module: 'prospects', action: 'add' },
  { code: 'prospects.edit', module: 'prospects', action: 'edit' },
  { code: 'prospects.delete', module: 'prospects', action: 'delete' },
  { code: 'prospects.convert', module: 'prospects', action: 'convert', description: 'Convert prospect to member' },
  { code: 'prospects.export', module: 'prospects', action: 'export' },

  // Membership Freeze
  { code: 'freeze.view', module: 'freeze', action: 'view' },
  { code: 'freeze.add', module: 'freeze', action: 'add' },
  { code: 'freeze.edit', module: 'freeze', action: 'edit' },
  { code: 'freeze.delete', module: 'freeze', action: 'delete' },

  // Follow-ups
  { code: 'followups.view', module: 'followups', action: 'view' },
  { code: 'followups.add', module: 'followups', action: 'add' },
  { code: 'followups.delete', module: 'followups', action: 'delete' },

  // Workouts
  { code: 'workouts.view', module: 'workouts', action: 'view' },
  { code: 'workouts.add', module: 'workouts', action: 'add' },
  { code: 'workouts.edit', module: 'workouts', action: 'edit' },
  { code: 'workouts.delete', module: 'workouts', action: 'delete' },
  { code: 'workouts.assign', module: 'workouts', action: 'assign' },

  // Diet
  { code: 'diet.view', module: 'diet', action: 'view' },
  { code: 'diet.add', module: 'diet', action: 'add' },
  { code: 'diet.edit', module: 'diet', action: 'edit' },
  { code: 'diet.delete', module: 'diet', action: 'delete' },
  { code: 'diet.assign', module: 'diet', action: 'assign' },

  // Progress
  { code: 'progress.view', module: 'progress', action: 'view' },
  { code: 'progress.add', module: 'progress', action: 'add' },
  { code: 'progress.edit', module: 'progress', action: 'edit' },
  { code: 'progress.delete', module: 'progress', action: 'delete' },

  // Equipment
  { code: 'equipment.view', module: 'equipment', action: 'view' },
  { code: 'equipment.add', module: 'equipment', action: 'add' },
  { code: 'equipment.edit', module: 'equipment', action: 'edit' },
  { code: 'equipment.delete', module: 'equipment', action: 'delete' },
  { code: 'equipment.status', module: 'equipment', action: 'status' },
  { code: 'equipment.maintenance', module: 'equipment', action: 'maintenance' },

  // Inventory
  { code: 'inventory.view', module: 'inventory', action: 'view' },
  { code: 'inventory.add', module: 'inventory', action: 'add' },
  { code: 'inventory.edit', module: 'inventory', action: 'edit' },
  { code: 'inventory.delete', module: 'inventory', action: 'delete' },
  { code: 'inventory.export', module: 'inventory', action: 'export' },

  // POS
  { code: 'pos.view', module: 'pos', action: 'view' },
  { code: 'pos.add', module: 'pos', action: 'add' },
  { code: 'pos.edit', module: 'pos', action: 'edit' },
  { code: 'pos.delete', module: 'pos', action: 'delete' },
  { code: 'pos.export', module: 'pos', action: 'export' },

  // Staff
  { code: 'staff.view', module: 'staff', action: 'view' },
  { code: 'staff.add', module: 'staff', action: 'add' },
  { code: 'staff.edit', module: 'staff', action: 'edit' },
  { code: 'staff.delete', module: 'staff', action: 'delete' },
  { code: 'staff.export', module: 'staff', action: 'export' },

  // Shifts
  { code: 'shifts.view', module: 'shifts', action: 'view' },
  { code: 'shifts.add', module: 'shifts', action: 'add' },
  { code: 'shifts.edit', module: 'shifts', action: 'edit' },
  { code: 'shifts.delete', module: 'shifts', action: 'delete' },

  // Calendar
  { code: 'calendar.view', module: 'calendar', action: 'view' },
  { code: 'calendar.edit', module: 'calendar', action: 'edit' },

  // Leaves
  { code: 'leaves.view', module: 'leaves', action: 'view' },
  { code: 'leaves.add', module: 'leaves', action: 'add' },
  { code: 'leaves.approve', module: 'leaves', action: 'approve' },
  { code: 'leaves.delete', module: 'leaves', action: 'delete' },

  // Overtime
  { code: 'overtime.view', module: 'overtime', action: 'view' },
  { code: 'overtime.add', module: 'overtime', action: 'add' },
  { code: 'overtime.approve', module: 'overtime', action: 'approve' },

  // Payroll
  { code: 'payroll.view', module: 'payroll', action: 'view' },
  { code: 'payroll.add', module: 'payroll', action: 'add' },
  { code: 'payroll.edit', module: 'payroll', action: 'edit' },
  { code: 'payroll.post', module: 'payroll', action: 'post', description: 'Post payroll payment' },
  { code: 'payroll.export', module: 'payroll', action: 'export' },

  // Branches
  { code: 'branches.view', module: 'branches', action: 'view' },
  { code: 'branches.add', module: 'branches', action: 'add' },
  { code: 'branches.edit', module: 'branches', action: 'edit' },
  { code: 'branches.delete', module: 'branches', action: 'delete' },

  // Users / Roles
  { code: 'users.view', module: 'users', action: 'view' },
  { code: 'users.add', module: 'users', action: 'add' },
  { code: 'users.edit', module: 'users', action: 'edit' },
  { code: 'users.delete', module: 'users', action: 'delete' },
  { code: 'roles.view', module: 'roles', action: 'view' },
  { code: 'roles.add', module: 'roles', action: 'add' },
  { code: 'roles.edit', module: 'roles', action: 'edit' },
  { code: 'roles.delete', module: 'roles', action: 'delete' },
  { code: 'roles.config', module: 'roles', action: 'configure', description: 'Assign permissions to role' },

  // Audit
  { code: 'audit.view', module: 'audit', action: 'view' },
  { code: 'audit.export', module: 'audit', action: 'export' },

  // Company / Admin Defaults
  { code: 'company.view', module: 'company', action: 'view' },
  { code: 'company.edit', module: 'company', action: 'edit' },

  // Account Mappings
  { code: 'accountMappings.view', module: 'accountMappings', action: 'view' },
  { code: 'accountMappings.edit', module: 'accountMappings', action: 'edit' },

  // Reports
  { code: 'reports.view', module: 'reports', action: 'view' },
  { code: 'reports.export', module: 'reports', action: 'export' },
  { code: 'reports.customize', module: 'reports', action: 'customize' },

  // Backup
  { code: 'backup.view', module: 'backup', action: 'view' },
  { code: 'backup.run', module: 'backup', action: 'add' },
] as const

export const PERMISSION_CODES = PERMISSIONS.map(p => p.code)

// Role → permission map for system roles
export const SYSTEM_ROLE_PERMISSIONS: Record<string, string[]> = {
  'Super Admin': PERMISSION_CODES, // all
  Owner: PERMISSION_CODES,
  Manager: [
    'dashboard.view',
    'members.view', 'members.add', 'members.edit', 'members.status', 'members.print', 'members.export',
    'memberships.view', 'memberships.add', 'memberships.edit',
    'attendance.view', 'attendance.add', 'attendance.edit', 'attendance.export',
    'fees.view', 'fees.add', 'fees.edit', 'fees.print', 'fees.export', 'fees.post',
    'finance.view', 'finance.add', 'finance.edit', 'finance.export', 'finance.reports',
    'vouchers.view', 'vouchers.add', 'vouchers.edit', 'vouchers.print', 'vouchers.post', 'vouchers.export',
    'cheques.view', 'cheques.status', 'cheques.export',
    'tax.view',
    'prospects.view', 'prospects.add', 'prospects.edit', 'prospects.convert', 'prospects.export',
    'freeze.view', 'freeze.add', 'freeze.edit',
    'followups.view', 'followups.add', 'followups.delete',
    'workouts.view', 'workouts.add', 'workouts.edit', 'workouts.assign',
    'diet.view', 'diet.add', 'diet.edit', 'diet.assign',
    'progress.view', 'progress.add', 'progress.edit',
    'equipment.view', 'equipment.add', 'equipment.edit', 'equipment.status', 'equipment.maintenance',
    'inventory.view', 'inventory.add', 'inventory.edit', 'inventory.export',
    'pos.view', 'pos.add', 'pos.edit', 'pos.export',
    'staff.view', 'staff.add', 'staff.edit',
    'shifts.view',
    'calendar.view', 'calendar.edit',
    'leaves.view', 'leaves.approve',
    'overtime.view', 'overtime.approve',
    'payroll.view', 'payroll.add', 'payroll.edit', 'payroll.export',
    'branches.view',
    'reports.view', 'reports.export',
  ],
  Accountant: [
    'dashboard.view',
    'finance.view', 'finance.add', 'finance.edit', 'finance.export', 'finance.reports', 'finance.post', 'finance.reverse', 'finance.periods', 'finance.reconcile', 'finance.settings', 'finance.coa',
    'vouchers.view', 'vouchers.add', 'vouchers.edit', 'vouchers.print', 'vouchers.post', 'vouchers.reverse', 'vouchers.export',
    'cheques.view', 'cheques.status', 'cheques.export',
    'tax.view', 'tax.add', 'tax.edit',
    'fees.view', 'fees.post', 'fees.export', 'fees.print',
    'payroll.view', 'payroll.export',
    'reports.view', 'reports.export',
    'pos.view', 'pos.export',
  ],
  Receptionist: [
    'dashboard.view',
    'members.view', 'members.add', 'members.edit', 'members.print',
    'memberships.view',
    'attendance.view', 'attendance.add',
    'fees.view', 'fees.add', 'fees.print', 'fees.post',
    'prospects.view', 'prospects.add', 'prospects.edit', 'prospects.convert',
    'followups.view', 'followups.add',
    'pos.view', 'pos.add',
  ],
  Trainer: [
    'dashboard.view',
    'members.view',
    'attendance.view',
    'workouts.view', 'workouts.add', 'workouts.edit', 'workouts.assign',
    'diet.view', 'diet.add', 'diet.edit', 'diet.assign',
    'progress.view', 'progress.add', 'progress.edit',
  ],
  Staff: ['dashboard.view', 'members.view', 'attendance.view'],
}
