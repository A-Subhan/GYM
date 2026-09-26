import { PERMISSIONS as P } from './permissions';

/**
 * Main sidebar navigation — five top-level modules.
 *
 * Structure: module → (optional) category → items.
 * Every node declares the existing permission code required to see it;
 * parents with no visible children are hidden entirely (handled in Sidebar).
 * Routes are the existing ones — labels may differ from routes.
 *
 * Notes:
 *  - Staff Attendance and Leaves are tabs inside the Staff page (/staff);
 *    no separate routes exist, so no separate items are created.
 *  - Notifications is reachable from the Topbar bell icon (existing route kept).
 *  - The generic Reports page (operational reports) lives under Gym.
 */
export const NAV_MODULES = [
  {
    key: 'dashboard',
    label: 'Dashboard',
    to: '/dashboard',
    icon: 'M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6',
    perm: P.DASHBOARD_VIEW,
  },

  {
    key: 'finance',
    label: 'Finance',
    icon: 'M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z',
    children: [
      { to: '/finance', label: 'Finance Dashboard', perm: P.FINANCE_VIEW },
      {
        label: 'Vouchers',
        children: [
          { to: '/finance/vouchers/brv', label: 'Bank Receipt Voucher', perm: P.FINANCE_VIEW },
          { to: '/finance/vouchers/bpv', label: 'Bank Payment Voucher', perm: P.FINANCE_VIEW },
          { to: '/finance/vouchers/crv', label: 'Cash Receipt Voucher', perm: P.FINANCE_VIEW },
          { to: '/finance/vouchers/cpv', label: 'Cash Payment Voucher', perm: P.FINANCE_VIEW },
          { to: '/finance/vouchers/jpv', label: 'Journal Voucher', perm: P.FINANCE_VIEW },
          { to: '/finance/vouchers/opb', label: 'Opening Trial Balance', perm: P.FINANCE_VIEW },
        ],
      },
      {
        label: 'Finance Reports',
        children: [
          { to: '/finance/reports/ledger', label: 'General Ledger', perm: P.FINANCE_REPORTS },
          { to: '/finance/reports/trial-balance', label: 'Trial Balance', perm: P.FINANCE_REPORTS },
          { to: '/finance/reports/opening-tb', label: 'Opening Trial Balance', perm: P.FINANCE_REPORTS },
          { to: '/finance/reports/balance-sheet', label: 'Balance Sheet', perm: P.FINANCE_REPORTS },
          { to: '/finance/reports/profit-loss', label: 'Profit & Loss', perm: P.FINANCE_REPORTS },
          { to: '/finance/reports/bank-statement', label: 'Bank Statement', perm: P.FINANCE_REPORTS },
          { to: '/finance/reports/voucher-register', label: 'Voucher Register', perm: P.FINANCE_REPORTS },
          { to: '/finance/recon', label: 'Bank Reconciliation', perm: P.FINANCE_RECONCILE },
        ],
      },
      {
        label: 'Aging Reports',
        children: [
          { to: '/finance/reports/customer-aging', label: 'Customer Aging', perm: P.FINANCE_REPORTS },
          { to: '/finance/reports/vendor-aging', label: 'Vendor Aging', perm: P.FINANCE_REPORTS },
        ],
      },
      {
        label: 'Finance Masters',
        children: [
          { to: '/finance/coa', label: 'Chart of Accounts', perm: P.FINANCE_COA },
          { to: '/finance/coa/tag/Customer', label: 'Customers', perm: P.FINANCE_COA },
          { to: '/finance/coa/tag/Vendor', label: 'Vendors', perm: P.FINANCE_COA },
          { to: '/finance/coa/tag/Bank', label: 'Banks', perm: P.FINANCE_COA },
          { to: '/finance/coa/tag/Cash', label: 'Cash Accounts', perm: P.FINANCE_COA },
          { to: '/finance/masters/tax-heads', label: 'Tax Heads', perm: P.FINANCE_COA },
        ],
      },
    ],
  },

  {
    key: 'gym',
    label: 'Gym',
    icon: 'M13 10V3L4 14h7v7l9-11h-7z',
    children: [
      { to: '/members', label: 'Members', perm: P.MEMBERS_VIEW },
      { to: '/memberships/plans', label: 'Membership Plans', perm: P.MEMBERSHIPS_VIEW },
      { to: '/attendance', label: 'Attendance', perm: P.ATTENDANCE_VIEW },
      { to: '/fees', label: 'Fees & Invoices', perm: P.FEES_VIEW },
      { to: '/workouts', label: 'Workout Plans', perm: 'workouts.view' },
      { to: '/diet', label: 'Diet Plans', perm: 'diet.view' },
      { to: '/progress', label: 'Progress Tracking', perm: 'progress.view' },
      { to: '/reports', label: 'Reports', perm: 'reports.view' },
      { to: '/inventory', label: 'Inventory', perm: 'inventory.view' },
      { to: '/equipment', label: 'Equipment', perm: 'equipment.view' },
    ],
  },

  {
    key: 'payroll',
    label: 'Payroll',
    icon: 'M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2zm7-5a2 2 0 11-4 0 2 2 0 014 0z',
    children: [
      // Staff page includes the Staff Attendance and Leaves tabs
      { to: '/staff', label: 'Staff', perm: 'staff.view' },
      { to: '/payroll', label: 'Payroll', perm: 'payroll.view' },
    ],
  },

  {
    key: 'admin',
    label: 'Administrator',
    icon: 'M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z M15 12a3 3 0 11-6 0 3 3 0 016 0z',
    children: [
      // Defaults = the existing Finance Defaults implementation (company, accounting, numbering, COA structure, mappings)
      { to: '/finance/settings', label: 'Defaults', perm: P.FINANCE_SETTINGS },
      { to: '/branches', label: 'Branches', perm: P.BRANCHES_VIEW },
      { to: '/users', label: 'Users & Roles', perm: P.USERS_VIEW },
      { to: '/masters', label: 'Master Files', perm: 'masters.view' },
      { to: '/settings', label: 'Settings', perm: P.SETTINGS_VIEW },
      { to: '/backup', label: 'Backup & Restore', perm: null },
      { to: '/audit-logs', label: 'Audit Logs', perm: P.AUDIT_VIEW },
      { to: '/about', label: 'About Contoura Labs', perm: null },
    ],
  },
];
