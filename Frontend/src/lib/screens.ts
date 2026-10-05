// The permission-gated data screens of the ERP, derived from the NAV
// entries in src/app/page.tsx. Excluded: the Dashboard and the
// purely-navigational Diet Assignment stub.
export type ScreenDef = { key: string; label: string; module: string }

export const SCREENS: ScreenDef[] = [
  // Gym Management — Operations (13)
  { key: 'gym-members', label: 'Members', module: 'Gym Management' },
  { key: 'gym-memberships', label: 'Membership Plans', module: 'Gym Management' },
  { key: 'gym-attendance', label: 'Attendance', module: 'Gym Management' },
  { key: 'gym-fees', label: 'Fees & Invoices', module: 'Gym Management' },
  { key: 'gym-status', label: 'Member Status', module: 'Gym Management' },
  { key: 'gym-freezes', label: 'Membership Freeze', module: 'Gym Management' },
  { key: 'gym-prospects', label: 'Prospects / Inquiries', module: 'Gym Management' },
  { key: 'gym-followups', label: 'Member Follow Up', module: 'Gym Management' },
  { key: 'gym-progress', label: 'Body Progress', module: 'Gym Management' },
  { key: 'gym-fitness-goals', label: 'Fitness Goals', module: 'Gym Management' },
  { key: 'gym-pt-sessions', label: 'Personal Training', module: 'Gym Management' },
  { key: 'gym-trainer-availability', label: 'Trainer Availability', module: 'Gym Management' },
  { key: 'gym-trainer-schedule', label: 'Trainer Schedule', module: 'Gym Management' },
  // Gym Management — Reports (1)
  { key: 'gym-reports', label: 'Gym Reports', module: 'Gym Management' },
  // Gym Management — Master (4)
  { key: 'gym-exercises', label: 'Exercises', module: 'Gym Management' },
  { key: 'gym-workouts', label: 'Workout Plans', module: 'Gym Management' },
  { key: 'gym-diet', label: 'Diet Plans', module: 'Gym Management' },
  { key: 'gym-master-files', label: 'Gym Master Files', module: 'Gym Management' },
  { key: 'gym-workout-assignment', label: 'Workout Assignment', module: 'Gym Management' },
  // Finance — Vouchers (7)
  { key: 'finance-voucher-bpv', label: 'Bank Payment Voucher', module: 'Finance' },
  { key: 'finance-voucher-brv', label: 'Bank Receipt Voucher', module: 'Finance' },
  { key: 'finance-voucher-cpv', label: 'Cash Payment Voucher', module: 'Finance' },
  { key: 'finance-voucher-crv', label: 'Cash Receipt Voucher', module: 'Finance' },
  { key: 'finance-voucher-jv', label: 'Journal Voucher', module: 'Finance' },
  { key: 'finance-voucher-otb', label: 'Opening Trial Balance', module: 'Finance' },
  { key: 'finance-voucher-cheques', label: 'Cheques', module: 'Finance' },
  // Finance — Reports (2)
  { key: 'finance-reports-aging', label: 'Aging Reports', module: 'Finance' },
  { key: 'finance-reports-main', label: 'Finance Reports', module: 'Finance' },
  // Finance — Master (3)
  { key: 'finance-coa', label: 'Chart of Accounts', module: 'Finance' },
  { key: 'finance-tax', label: 'Tax Heads', module: 'Finance' },
  { key: 'finance-master-files', label: 'Master Files', module: 'Finance' },
  // HR and Payroll — Transactions (7)
  { key: 'payroll-staff', label: 'Staff', module: 'HR and Payroll' },
  { key: 'payroll-leaves', label: 'Leave', module: 'HR and Payroll' },
  { key: 'payroll-overtime', label: 'Overtime', module: 'HR and Payroll' },
  { key: 'payroll-payroll', label: 'Payroll', module: 'HR and Payroll' },
  { key: 'payroll-shifts', label: 'Shifts', module: 'HR and Payroll' },
  { key: 'payroll-calendar', label: 'Calendar', module: 'HR and Payroll' },
  // HR and Payroll — Reports (1)
  { key: 'hr-reports', label: 'HR Reports', module: 'HR and Payroll' },
  // HR and Payroll — Master (1)
  { key: 'payroll-master-files', label: 'Payroll Master File', module: 'HR and Payroll' },
  // Inventory — Transactions (3)
  { key: 'inv-purchases', label: 'Purchases', module: 'Inventory' },
  { key: 'inv-stock-movements', label: 'Stock Movements', module: 'Inventory' },
  { key: 'inv-equipment', label: 'Equipment', module: 'Inventory' },
  // Inventory — Reports (1)
  { key: 'inv-reports', label: 'Inventory Reports', module: 'Inventory' },
  // Inventory — Master (2)
  { key: 'inv-items', label: 'Items', module: 'Inventory' },
  { key: 'inv-suppliers', label: 'Suppliers', module: 'Inventory' },
  // Admin & Security — Management (1 — consolidated)
  { key: 'admin-management', label: 'Management', module: 'Admin & Security' },
  // Admin & Security — Reports (1)
  { key: 'admin-audit', label: 'Administrative Reports', module: 'Admin & Security' },
  // Admin & Security — Master (2)
  { key: 'admin-branches', label: 'Branches', module: 'Admin & Security' },
  { key: 'admin-users', label: 'Users & Permissions', module: 'Admin & Security' },
]

export const SCREEN_ACTIONS = ['view', 'add', 'edit', 'delete', 'print'] as const
export type ScreenAction = (typeof SCREEN_ACTIONS)[number]
