import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import api from '../../services/api';
import { formatCurrency } from '../../utils/format';
import PageHeader from '../../components/common/PageHeader';
import Spinner from '../../components/common/Spinner';
import { useAuth } from '../../context/AuthContext';

function StatCard({ label, value, tone = 'slate', to }) {
  const tones = {
    slate: 'text-slate-800 dark:text-slate-100',
    green: 'text-emerald-600',
    red: 'text-red-600',
    blue: 'text-brand-600',
  };
  const body = (
    <div className="card p-5 h-full">
      <div className="text-xs uppercase tracking-wide text-slate-400 mb-1">{label}</div>
      <div className={`text-2xl font-bold ${tones[tone]}`}>{value}</div>
    </div>
  );
  return to ? <Link to={to} className="hover:shadow-md transition-shadow">{body}</Link> : body;
}

/** Finance dashboard — every figure comes from actual posted accounting data. */
export default function FinanceDashboardPage() {
  const { user } = useAuth();
  const [stats, setStats] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    api.get('/finance/dashboard')
      .then((res) => setStats(res.data.data))
      .catch(() => {})
      .finally(() => setLoading(false));
  }, []);

  if (loading) return <Spinner size="lg" className="mt-20" />;
  if (!stats) return <div className="text-center text-slate-400 mt-20">Finance data unavailable.</div>;

  return (
    <div className="space-y-4">
      <PageHeader title="Finance Dashboard" subtitle={`Real accounting positions as of ${new Date(stats.AsOf).toLocaleDateString('en-GB')}`} />

      <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-4 gap-3">
        <StatCard label="Cash on Hand" value={formatCurrency(stats.CashBalance)} tone="green" to="/finance/reports/bank-statement" />
        <StatCard label="Bank Balances" value={formatCurrency(stats.BankBalance)} tone="green" to="/finance/reports/bank-statement" />
        <StatCard label="Receivables" value={formatCurrency(stats.Receivables)} tone="red" to="/finance/reports/customer-aging" />
        <StatCard label="Payables" value={formatCurrency(stats.Payables)} tone="red" to="/finance/reports/vendor-aging" />
        <StatCard label="Revenue (This Month)" value={formatCurrency(stats.MonthRevenue)} tone="blue" to="/finance/reports/profit-loss" />
        <StatCard label="Expenses (This Month)" value={formatCurrency(stats.MonthExpense)} tone="blue" to="/finance/reports/profit-loss" />
        <StatCard label="Net Profit (This Month)" value={formatCurrency(stats.MonthNetProfit)} tone={stats.MonthNetProfit >= 0 ? 'green' : 'red'} to="/finance/reports/profit-loss" />
        <StatCard label="Net Profit (Year to Date)" value={formatCurrency(stats.YearNetProfit)} tone={stats.YearNetProfit >= 0 ? 'green' : 'red'} to="/finance/reports/profit-loss" />
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
        <div className="card p-5">
          <div className="text-xs uppercase tracking-wide text-slate-400 mb-1">Pending customer balances</div>
          <div className="text-3xl font-bold text-slate-800 dark:text-slate-100">{stats.PendingCustomerBills}</div>
          <Link to="/finance/reports/customer-aging" className="text-sm text-brand-600 hover:underline">Open customer aging →</Link>
        </div>
        <div className="card p-5">
          <div className="text-xs uppercase tracking-wide text-slate-400 mb-1">Pending vendor balances</div>
          <div className="text-3xl font-bold text-slate-800 dark:text-slate-100">{stats.PendingVendorBills}</div>
          <Link to="/finance/reports/vendor-aging" className="text-sm text-brand-600 hover:underline">Open vendor aging →</Link>
        </div>
      </div>
    </div>
  );
}
