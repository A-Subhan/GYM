import { useEffect, useState, useCallback } from 'react';
import api from '../../services/api';
import { useToast } from '../../context/ToastContext';
import PageHeader from '../../components/common/PageHeader';
import Button from '../../components/common/Button';
import Spinner from '../../components/common/Spinner';
import DataTable from '../../components/common/DataTable';
import { formatCurrency, formatDate, formatDateTime } from '../../utils/format';
import { exportToCSV, printPage } from '../../utils/export';

const REPORTS = [
  { key: 'members', label: 'Members', endpoint: '/reports/members', columns: [
    { key: 'Code', label: 'Code' }, { key: 'FullName', label: 'Name' }, { key: 'Gender', label: 'Gender' },
    { key: 'Mobile', label: 'Mobile' }, { key: 'JoiningDate', label: 'Joined', render: (r) => formatDate(r.JoiningDate) },
    { key: 'Status', label: 'Status' }, { key: 'BranchName', label: 'Branch' },
  ]},
  { key: 'attendance', label: 'Attendance', endpoint: '/reports/attendance', columns: [
    { key: 'Date', label: 'Date', render: (r) => formatDate(r.Date) }, { key: 'BranchName', label: 'Branch' },
    { key: 'UniqueMembers', label: 'Unique Members' }, { key: 'TotalCheckIns', label: 'Total Check-Ins' },
  ]},
  { key: 'payments', label: 'Payments', endpoint: '/reports/payments', columns: [
    { key: 'MemberCode', label: 'Code' }, { key: 'MemberName', label: 'Member' },
    { key: 'Amount', label: 'Amount', render: (r) => formatCurrency(r.Amount) },
    { key: 'Method', label: 'Method' }, { key: 'TransactionRef', label: 'Ref' },
    { key: 'CollectedAt', label: 'Date', render: (r) => formatDateTime(r.CollectedAt) },
    { key: 'CollectedBy', label: 'Collected By' },
  ]},
  { key: 'salary', label: 'Salary', endpoint: '/reports/salary', columns: [
    { key: 'StaffName', label: 'Staff' }, { key: 'Designation', label: 'Designation' },
    { key: 'Department', label: 'Dept' }, { key: 'Month', label: 'Month' }, { key: 'Year', label: 'Year' },
    { key: 'BaseSalary', label: 'Base', render: (r) => formatCurrency(r.BaseSalary) },
    { key: 'NetSalary', label: 'Net', render: (r) => formatCurrency(r.NetSalary) },
    { key: 'Status', label: 'Status' },
  ]},
  { key: 'equipment', label: 'Equipment', endpoint: '/reports/equipment', columns: [
    { key: 'Name', label: 'Name' }, { key: 'Brand', label: 'Brand' }, { key: 'SerialNo', label: 'Serial' },
    { key: 'PurchaseDate', label: 'Purchased', render: (r) => formatDate(r.PurchaseDate) },
    { key: 'PurchasePrice', label: 'Price', render: (r) => formatCurrency(r.PurchasePrice) },
    { key: 'Status', label: 'Status' },
    { key: 'MaintenanceCount', label: 'Maint. Count' },
    { key: 'TotalMaintenanceCost', label: 'Maint. Cost', render: (r) => formatCurrency(r.TotalMaintenanceCost) },
  ]},
  { key: 'inventory', label: 'Inventory', endpoint: '/reports/inventory', columns: [
    { key: 'Name', label: 'Item' }, { key: 'Category', label: 'Category' }, { key: 'SKU', label: 'SKU' },
    { key: 'StockQty', label: 'Stock' }, { key: 'ReorderLevel', label: 'Reorder At' },
    { key: 'SalePrice', label: 'Sale', render: (r) => formatCurrency(r.SalePrice) },
    { key: 'StockValue', label: 'Stock Value', render: (r) => formatCurrency(r.StockValue) },
    { key: 'RetailValue', label: 'Retail Value', render: (r) => formatCurrency(r.RetailValue) },
    { key: 'StockStatus', label: 'Status' },
  ]},
];

export default function ReportsPage() {
  const toast = useToast();
  const [activeReport, setActiveReport] = useState('members');
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(true);
  const [filters, setFilters] = useState({ fromDate: '', toDate: '', status: '', category: '', month: '', year: new Date().getFullYear() });

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const report = REPORTS.find((r) => r.key === activeReport);
      if (!report) { setRows([]); setLoading(false); return; }
      const params = {};
      if (filters.fromDate) params.fromDate = filters.fromDate;
      if (filters.toDate) params.toDate = filters.toDate;
      if (filters.status) params.status = filters.status;
      if (filters.category) params.category = filters.category;
      if (filters.month) params.month = filters.month;
      if (filters.year) params.year = filters.year;

      const res = await api.get(report.endpoint, { params });
      setRows(res.data.data);
    } catch (err) { toast.error('Failed to load report'); }
    finally { setLoading(false); }
  }, [activeReport, filters]);

  useEffect(() => { load(); }, [load]);

  const report = REPORTS.find((r) => r.key === activeReport);

  return (
    <div className="space-y-4">
      <PageHeader title="Reports" subtitle="Generate and export reports across all modules"
        actions={
          rows.length > 0 ? (
            <div className="flex gap-2">
              <Button variant="ghost" onClick={() => exportToCSV(rows, `${activeReport}-report.csv`, report.columns.map(c => ({ key: c.key, label: c.label })))}>Export CSV</Button>
              <Button variant="secondary" onClick={printPage}>Print</Button>
            </div>
          ) : null
        } />

      <div className="card p-4 flex flex-wrap gap-2">
        {REPORTS.map((r) => (
          <button key={r.key} onClick={() => setActiveReport(r.key)}
            className={`px-3 py-1.5 rounded-lg text-sm font-medium transition-colors ${activeReport === r.key ? 'bg-brand-600 text-white' : 'bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300 hover:bg-slate-200 dark:hover:bg-slate-700'}`}>
            {r.label}
          </button>
        ))}
      </div>

      <div className="card p-4 flex flex-wrap gap-3 items-end">
          {(activeReport === 'members' || activeReport === 'equipment' || activeReport === 'inventory') && (
            <>
              {activeReport === 'members' && (
                <div><label className="label">Status</label><select value={filters.status} onChange={(e) => setFilters({...filters, status: e.target.value})} className="input w-40"><option value="">All</option><option>Active</option><option>Inactive</option><option>Frozen</option><option>Expired</option></select></div>
              )}
              {activeReport === 'equipment' && (
                <div><label className="label">Status</label><select value={filters.status} onChange={(e) => setFilters({...filters, status: e.target.value})} className="input w-40"><option value="">All</option><option>Active</option><option>Maintenance</option><option>Broken</option></select></div>
              )}
              {activeReport === 'inventory' && (
                <div><label className="label">Category</label><select value={filters.category} onChange={(e) => setFilters({...filters, category: e.target.value})} className="input w-40"><option value="">All</option><option>Supplement</option><option>Drink</option><option>Accessory</option></select></div>
              )}
            </>
          )}
          {activeReport === 'salary' && (
            <>
              <div><label className="label">Month</label><select value={filters.month} onChange={(e) => setFilters({...filters, month: e.target.value})} className="input w-32"><option value="">All</option>{Array.from({length: 12}, (_, i) => i+1).map((m) => <option key={m} value={m}>{new Date(2000, m-1).toLocaleString('en', { month: 'long' })}</option>)}</select></div>
              <div><label className="label">Year</label><input type="number" value={filters.year} onChange={(e) => setFilters({...filters, year: e.target.value})} className="input w-24" /></div>
            </>
          )}
          {['members','attendance','payments'].includes(activeReport) && (
            <>
              <div><label className="label">From</label><input type="date" value={filters.fromDate} onChange={(e) => setFilters({...filters, fromDate: e.target.value})} className="input w-40" /></div>
              <div><label className="label">To</label><input type="date" value={filters.toDate} onChange={(e) => setFilters({...filters, toDate: e.target.value})} className="input w-40" /></div>
            </>
          )}
          <Button variant="secondary" onClick={() => setFilters({ fromDate: '', toDate: '', status: '', category: '', month: '', year: new Date().getFullYear() })}>Reset</Button>
      </div>

      <DataTable columns={report.columns} rows={rows} loading={loading} emptyMessage="No records for the selected filters" />
    </div>
  );
}

function Row({ label, value }) {
  return (
    <div className="flex items-center justify-between">
      <span className="text-slate-600 dark:text-slate-400">{label}</span>
      <span className="font-medium">{value}</span>
    </div>
  );
}
