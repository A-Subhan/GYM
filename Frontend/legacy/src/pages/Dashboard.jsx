import { useEffect, useState } from 'react';
import api from '../services/api';
import { useAuth } from '../context/AuthContext';
import { useToast } from '../context/ToastContext';
import { formatCurrency, timeAgo } from '../utils/format';
import { StatusBadge } from '../components/common/Badge';
import Spinner from '../components/common/Spinner';
import { LineChart, Line, BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Area, AreaChart } from 'recharts';

const KPIS = [
  { key: 'TotalMembers', label: 'Total Members', icon: 'M17 20h5v-2a4 4 0 00-3-3.87M9 20H4v-2a4 4 0 013-3.87m6-2a4 4 0 11-8 0 4 4 0 018 0zm6 0a4 4 0 11-8 0 4 4 0 018 0z', color: 'from-blue-500 to-blue-600' },
  { key: 'ActiveMembers', label: 'Active Members', icon: 'M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z', color: 'from-emerald-500 to-emerald-600' },
  { key: 'ExpiredMembers', label: 'Expired Members', icon: 'M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z', color: 'from-red-500 to-red-600' },
  { key: 'NewMembers', label: 'New This Month', icon: 'M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z', color: 'from-violet-500 to-violet-600' },
  { key: 'TodayAttendance', label: "Today's Attendance", icon: 'M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z', color: 'from-amber-500 to-amber-600' },
  { key: 'MonthlyIncome', label: 'Monthly Income', icon: 'M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1', color: 'from-teal-500 to-teal-600' },
  { key: 'MonthlyExpenses', label: 'Monthly Expenses', icon: 'M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2zm7-5a2 2 0 11-4 0 2 2 0 014 0z', color: 'from-rose-500 to-rose-600' },
  { key: 'PendingFees', label: 'Pending Fees', icon: 'M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z', color: 'from-orange-500 to-orange-600' },
  { key: 'SalaryDue', label: 'Salary Due', icon: 'M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2zm7-5a2 2 0 11-4 0 2 2 0 014 0z', color: 'from-cyan-500 to-cyan-600' },
  { key: 'RentDue', label: 'Rent Due', icon: 'M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6', color: 'from-pink-500 to-pink-600' },
  { key: 'EquipmentUnderMaintenance', label: 'Equipment in Maintenance', icon: 'M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z', color: 'from-indigo-500 to-indigo-600' },
  { key: 'MembershipExpiryAlerts', label: 'Expiry Alerts (7d)', icon: 'M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9', color: 'from-yellow-500 to-yellow-600' },
];

export default function Dashboard() {
  const { user } = useAuth();
  const toast = useToast();
  const [stats, setStats] = useState(null);
  const [charts, setCharts] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const [statsRes, chartsRes] = await Promise.all([
          api.get('/dashboard/stats'),
          api.get('/dashboard/charts?months=6'),
        ]);
        if (cancelled) return;
        setStats(statsRes.data.data);
        setCharts(chartsRes.data.data);
      } catch (err) {
        if (!cancelled) toast.error('Failed to load dashboard: ' + (err.response?.data?.error?.message || err.message));
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, []);

  if (loading) return <Spinner size="lg" className="mt-20" />;

  const chartTheme = {
    grid: 'rgba(148,163,184,0.15)',
    axis: '#94a3b8',
    tooltipBg: 'rgba(15,23,42,0.95)',
    tooltipBorder: 'rgba(148,163,184,0.2)',
  };

  // Merge revenue + expenses for combined chart
  const revenueByMonth = (charts?.revenue || []).map(r => ({ month: r.Month, revenue: r.Revenue }));
  const expensesByMonth = (charts?.expenses || []).map(e => ({ month: e.Month, expenses: e.Expenses }));
  const combined = revenueByMonth.map((r, i) => ({
    month: r.month,
    Revenue: r.revenue,
    Expenses: expensesByMonth[i]?.expenses || 0,
  }));

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-2xl font-bold">Welcome back, {user?.fullName?.split(' ')[0]}!</h1>
        <p className="text-sm text-slate-500 dark:text-slate-400">
          Here's what's happening at your gym today · {new Date().toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' })}
        </p>
      </div>

      {/* KPI cards */}
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 xl:grid-cols-6 gap-3">
        {KPIS.map((kpi) => (
          <div key={kpi.key} className="card p-4">
            <div className="flex items-center justify-between mb-2">
              <div className={`w-9 h-9 rounded-lg bg-gradient-to-br ${kpi.color} text-white flex items-center justify-center`}>
                <svg className="w-5 h-5" fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" d={kpi.icon} />
                </svg>
              </div>
            </div>
            <div className="text-2xl font-bold leading-tight">
              {['MonthlyIncome', 'MonthlyExpenses', 'PendingFees', 'SalaryDue', 'RentDue'].includes(kpi.key)
                ? formatCurrency(stats?.[kpi.key] || 0)
                : (stats?.[kpi.key] || 0)}
            </div>
            <div className="text-xs text-slate-500 dark:text-slate-400 mt-1">{kpi.label}</div>
          </div>
        ))}
      </div>

      {/* Charts */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
        <div className="card p-5">
          <h3 className="font-semibold mb-4">Revenue vs Expenses (6 months)</h3>
          <ResponsiveContainer width="100%" height={260}>
            <AreaChart data={combined}>
              <defs>
                <linearGradient id="rev" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="#14b8a6" stopOpacity={0.5} />
                  <stop offset="100%" stopColor="#14b8a6" stopOpacity={0} />
                </linearGradient>
                <linearGradient id="exp" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="#f43f5e" stopOpacity={0.5} />
                  <stop offset="100%" stopColor="#f43f5e" stopOpacity={0} />
                </linearGradient>
              </defs>
              <CartesianGrid strokeDasharray="3 3" stroke={chartTheme.grid} />
              <XAxis dataKey="month" stroke={chartTheme.axis} fontSize={12} />
              <YAxis stroke={chartTheme.axis} fontSize={12} tickFormatter={(v) => v >= 1000 ? `${(v/1000).toFixed(0)}k` : v} />
              <Tooltip
                contentStyle={{ background: chartTheme.tooltipBg, border: `1px solid ${chartTheme.tooltipBorder}`, borderRadius: 8, color: '#fff' }}
                formatter={(v) => formatCurrency(v)}
              />
              <Area type="monotone" dataKey="Revenue" stroke="#14b8a6" strokeWidth={2} fill="url(#rev)" />
              <Area type="monotone" dataKey="Expenses" stroke="#f43f5e" strokeWidth={2} fill="url(#exp)" />
            </AreaChart>
          </ResponsiveContainer>
        </div>

        <div className="card p-5">
          <h3 className="font-semibold mb-4">Attendance (last 14 days)</h3>
          <ResponsiveContainer width="100%" height={260}>
            <BarChart data={charts?.attendance?.map(a => ({ date: a.Date?.slice(5), count: a.Attendance })) || []}>
              <CartesianGrid strokeDasharray="3 3" stroke={chartTheme.grid} />
              <XAxis dataKey="date" stroke={chartTheme.axis} fontSize={11} />
              <YAxis stroke={chartTheme.axis} fontSize={12} />
              <Tooltip
                contentStyle={{ background: chartTheme.tooltipBg, border: `1px solid ${chartTheme.tooltipBorder}`, borderRadius: 8, color: '#fff' }}
              />
              <Bar dataKey="count" fill="#3478f6" radius={[4, 4, 0, 0]} />
            </BarChart>
          </ResponsiveContainer>
        </div>

        <div className="card p-5 lg:col-span-2">
          <h3 className="font-semibold mb-4">Membership Growth (6 months)</h3>
          <ResponsiveContainer width="100%" height={260}>
            <LineChart data={charts?.membershipGrowth?.map(m => ({ month: m.Month, members: m.TotalMembers })) || []}>
              <CartesianGrid strokeDasharray="3 3" stroke={chartTheme.grid} />
              <XAxis dataKey="month" stroke={chartTheme.axis} fontSize={12} />
              <YAxis stroke={chartTheme.axis} fontSize={12} />
              <Tooltip
                contentStyle={{ background: chartTheme.tooltipBg, border: `1px solid ${chartTheme.tooltipBorder}`, borderRadius: 8, color: '#fff' }}
              />
              <Line type="monotone" dataKey="members" stroke="#8b5cf6" strokeWidth={3} dot={{ r: 4, fill: '#8b5cf6' }} />
            </LineChart>
          </ResponsiveContainer>
        </div>
      </div>

      <div className="text-xs text-slate-400 text-center pt-2">
        Last login: {user?.lastLoginAt ? timeAgo(user.lastLoginAt) : 'just now'} ·
        Session is being audited for security.
      </div>
    </div>
  );
}
