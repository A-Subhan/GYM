import { Routes, Route, Navigate } from 'react-router-dom';
import Login from './pages/auth/Login';
import AppLayout from './components/layout/AppLayout';
import ProtectedRoute from './routes/ProtectedRoute';
import Dashboard from './pages/Dashboard';
import MembersList from './pages/members/MembersList';
import MemberProfile from './pages/members/MemberProfile';
import MemberForm from './pages/members/MemberForm';
import MembershipPlans from './pages/memberships/MembershipPlans';
import AttendancePage from './pages/attendance/AttendancePage';
import FeesPage from './pages/fees/FeesPage';
import FinanceDashboardPage from './pages/finance/FinanceDashboardPage';
import VouchersPage from './pages/finance/vouchers/VouchersPage';
import ChartOfAccountsPage from './pages/finance/coa/ChartOfAccountsPage';
import TaxHeadsPage from './pages/finance/masters/TaxHeadsPage';
import FinanceReportsPage from './pages/finance/reports/FinanceReportsPage';
import PeriodsPage from './pages/finance/admin/PeriodsPage';
import BankReconPage from './pages/finance/recon/BankReconPage';
import FinanceDefaultsPage from './pages/finance/settings/FinanceDefaultsPage';
import StaffPage from './pages/staff/StaffPage';
import MasterFilesPage from './pages/masters/MasterFilesPage';
import PayrollPage from './pages/payroll/PayrollPage';
import WorkoutsPage from './pages/workouts/WorkoutsPage';
import DietPage from './pages/diet/DietPage';
import ProgressPage from './pages/progress/ProgressPage';
import EquipmentPage from './pages/equipment/EquipmentPage';
import InventoryPage from './pages/inventory/InventoryPage';
import ReportsPage from './pages/reports/ReportsPage';
import NotificationsPage from './pages/notifications/NotificationsPage';
import BackupPage from './pages/backup/BackupPage';
import UsersPage from './pages/settings/UsersPage';
import BranchesPage from './pages/branches/BranchesPage';
import SettingsPage from './pages/settings/SettingsPage';
import AuditLogsPage from './pages/audit-logs/AuditLogsPage';
import AboutPage from './pages/About';
import NotFound from './pages/NotFound';

export default function App() {
  return (
    <Routes>
      <Route path="/login" element={<Login />} />

      <Route
        element={
          <ProtectedRoute>
            <AppLayout />
          </ProtectedRoute>
        }
      >
        <Route index element={<Navigate to="/dashboard" replace />} />
        <Route path="/dashboard" element={<Dashboard />} />

        <Route path="/members" element={<MembersList />} />
        <Route path="/members/new" element={<MemberForm />} />
        <Route path="/members/:id" element={<MemberProfile />} />
        <Route path="/members/:id/edit" element={<MemberForm />} />

        <Route path="/memberships/plans" element={<MembershipPlans />} />

        <Route path="/attendance" element={<AttendancePage />} />
        <Route path="/fees" element={<FeesPage />} />
        <Route path="/finance" element={<FinanceDashboardPage />} />
        <Route path="/finance/vouchers/:type" element={<VouchersPage />} />
        <Route path="/finance/coa" element={<ChartOfAccountsPage />} />
        <Route path="/finance/coa/tag/:tag" element={<ChartOfAccountsPage />} />
        <Route path="/finance/masters/tax-heads" element={<TaxHeadsPage />} />
        <Route path="/finance/reports/:key" element={<FinanceReportsPage />} />
        <Route path="/finance/periods" element={<PeriodsPage />} />
        <Route path="/finance/recon" element={<BankReconPage />} />
        <Route path="/finance/settings" element={<FinanceDefaultsPage />} />

        <Route path="/payroll" element={<PayrollPage />} />
        <Route path="/staff" element={<StaffPage />} />
        <Route path="/masters" element={<MasterFilesPage />} />
        <Route path="/workouts" element={<WorkoutsPage />} />
        <Route path="/diet" element={<DietPage />} />
        <Route path="/progress" element={<ProgressPage />} />
        <Route path="/equipment" element={<EquipmentPage />} />
        <Route path="/inventory" element={<InventoryPage />} />
        <Route path="/reports" element={<ReportsPage />} />
        <Route path="/notifications" element={<NotificationsPage />} />
        <Route path="/backup" element={<BackupPage />} />

        <Route path="/branches" element={<BranchesPage />} />
        <Route path="/audit-logs" element={<AuditLogsPage />} />
        <Route path="/settings" element={<SettingsPage />} />
        <Route path="/users" element={<UsersPage />} />
        <Route path="/about" element={<AboutPage />} />
      </Route>

      <Route path="*" element={<NotFound />} />
    </Routes>
  );
}
