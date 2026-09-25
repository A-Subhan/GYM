import { useEffect, useState, useCallback } from 'react';
import api from '../../services/api';
import { useToast } from '../../context/ToastContext';
import PageHeader from '../../components/common/PageHeader';
import Button from '../../components/common/Button';
import Modal from '../../components/common/Modal';
import DataTable from '../../components/common/DataTable';
import { formatCurrency, formatDate } from '../../utils/format';
import { StatusBadge } from '../../components/common/Badge';
import Can from '../../components/common/Can';
import { exportToCSV } from '../../utils/export';

export default function PayrollPage() {
  const toast = useToast();
  const [rows, setRows] = useState([]);
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [total, setTotal] = useState(0);
  const [totalNet, setTotalNet] = useState(0);
  const [loading, setLoading] = useState(true);
  const [month, setMonth] = useState(new Date().getMonth() + 1);
  const [year, setYear] = useState(new Date().getFullYear());
  const [statusFilter, setStatusFilter] = useState('');
  const [genModal, setGenModal] = useState(false);
  const [genAllModal, setGenAllModal] = useState(false);
  const [staffList, setStaffList] = useState([]);
  const [genForm, setGenForm] = useState({ StaffID: '', Month: month, Year: year, Bonus: 0, Overtime: 0, LeaveDeduction: 0, Commission: 0 });
  const [genAllForm, setGenAllForm] = useState({ Month: month, Year: year, Bonus: 0, Overtime: 0, LeaveDeduction: 0, Commission: 0 });

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await api.get('/payroll', { params: { page, pageSize: 20, month, year, status: statusFilter || undefined } });
      setRows(res.data.data);
      setTotal(res.data.meta.total);
      setTotalPages(res.data.meta.totalPages);
      setTotalNet(res.data.meta.totalNet || 0);
    } catch (err) { toast.error('Failed to load payroll'); }
    finally { setLoading(false); }
  }, [page, month, year, statusFilter]);

  useEffect(() => { load(); }, [load]);

  const openGen = async () => {
    try {
      const res = await api.get('/staff', { params: { pageSize: 200 } });
      setStaffList(res.data.data);
      setGenForm({ StaffID: res.data.data[0]?.StaffID || '', Month: month, Year: year, Bonus: 0, Overtime: 0, LeaveDeduction: 0, Commission: 0 });
      setGenModal(true);
    } catch (err) { toast.error('Failed to load staff'); }
  };

  const generate = async (e) => {
    e.preventDefault();
    try {
      const payload = { ...genForm, StaffID: Number(genForm.StaffID), Month: Number(genForm.Month), Year: Number(genForm.Year), Bonus: Number(genForm.Bonus), Overtime: Number(genForm.Overtime), LeaveDeduction: Number(genForm.LeaveDeduction), Commission: Number(genForm.Commission) };
      await api.post('/payroll/generate', payload);
      toast.success('Payroll generated'); setGenModal(false); load();
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Failed'); }
  };

  const generateAll = async (e) => {
    e.preventDefault();
    try {
      const payload = { ...genAllForm, Month: Number(genAllForm.Month), Year: Number(genAllForm.Year), Bonus: Number(genAllForm.Bonus), Overtime: Number(genAllForm.Overtime), LeaveDeduction: Number(genAllForm.LeaveDeduction), Commission: Number(genAllForm.Commission) };
      const res = await api.post('/payroll/generate-all', payload);
      toast.success(`${res.data.data.insertedCount} payroll records generated`);
      setGenAllModal(false); load();
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Failed'); }
  };

  const markPaid = async (id) => {
    if (!confirm('Mark this payroll as paid?')) return;
    try { await api.post(`/payroll/${id}/mark-paid`); toast.success('Marked as paid'); load(); }
    catch (err) { toast.error('Failed'); }
  };

  const columns = [
    { key: 'StaffName', label: 'Staff', render: (p) => <div><div className="font-medium">{p.StaffName}</div><div className="text-xs text-slate-400">{p.Designation} · {p.DepartmentName}</div></div> },
    { key: 'Period', label: 'Period', render: (p) => `${p.Month}/${p.Year}` },
    { key: 'BaseSalary', label: 'Base', render: (p) => formatCurrency(p.BaseSalary) },
    { key: 'Bonus', label: 'Bonus', render: (p) => p.Bonus ? formatCurrency(p.Bonus) : '—' },
    { key: 'Overtime', label: 'OT', render: (p) => p.Overtime ? formatCurrency(p.Overtime) : '—' },
    { key: 'NetSalary', label: 'Net', render: (p) => <span className="font-semibold">{formatCurrency(p.NetSalary)}</span> },
    { key: 'Status', label: 'Status', render: (p) => <StatusBadge status={p.Status} /> },
    { key: 'actions', label: '', render: (p) => p.Status === 'Generated' ? <button onClick={() => markPaid(p.PayrollID)} className="text-emerald-600 hover:underline text-sm">Mark Paid</button> : null },
  ];

  return (
    <div className="space-y-4">
      <PageHeader title="Payroll" subtitle={`${total} records · Total: ${formatCurrency(totalNet)}`}
        actions={
          <Can perm="payroll.add">
            <div className="flex gap-2">
              <Button variant="secondary" onClick={() => setGenAllModal(true)}>Generate All</Button>
              <Button onClick={openGen}>+ Generate Single</Button>
            </div>
          </Can>
        } />

      <div className="card p-4 flex flex-wrap gap-3 items-end">
        <div><label className="label">Month</label><select value={month} onChange={(e) => { setMonth(Number(e.target.value)); setPage(1); }} className="input w-32">{Array.from({length: 12}, (_, i) => i+1).map((m) => <option key={m} value={m}>{new Date(2000, m-1).toLocaleString('en', { month: 'long' })}</option>)}</select></div>
        <div><label className="label">Year</label><input type="number" value={year} onChange={(e) => { setYear(Number(e.target.value)); setPage(1); }} className="input w-24" /></div>
        <div><label className="label">Status</label><select value={statusFilter} onChange={(e) => { setStatusFilter(e.target.value); setPage(1); }} className="input w-40"><option value="">All</option><option>Generated</option><option>Paid</option></select></div>
        <Button variant="ghost" onClick={() => exportToCSV(rows, `payroll-${year}-${month}.csv`)}>Export CSV</Button>
      </div>

      <DataTable columns={columns} rows={rows} loading={loading} pagination={{ page, totalPages, total }} onPageChange={setPage} />

      <Modal open={genModal} onClose={() => setGenModal(false)} title="Generate Payroll (Single Staff)">
        <form onSubmit={generate} className="space-y-3">
          <div><label className="label">Staff *</label><select className="input" value={genForm.StaffID} onChange={(e) => setGenForm({...genForm, StaffID: e.target.value})} required>{staffList.map((s) => <option key={s.StaffID} value={s.StaffID}>{s.FullName} — {formatCurrency(s.BaseSalary)}</option>)}</select></div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="label">Month</label><select className="input" value={genForm.Month} onChange={(e) => setGenForm({...genForm, Month: e.target.value})}>{Array.from({length: 12}, (_, i) => i+1).map((m) => <option key={m} value={m}>{new Date(2000, m-1).toLocaleString('en', { month: 'long' })}</option>)}</select></div>
            <div><label className="label">Year</label><input type="number" className="input" value={genForm.Year} onChange={(e) => setGenForm({...genForm, Year: e.target.value})} /></div>
            <div><label className="label">Bonus</label><input type="number" step="0.01" className="input" value={genForm.Bonus} onChange={(e) => setGenForm({...genForm, Bonus: e.target.value})} /></div>
            <div><label className="label">Overtime</label><input type="number" step="0.01" className="input" value={genForm.Overtime} onChange={(e) => setGenForm({...genForm, Overtime: e.target.value})} /></div>
            <div><label className="label">Leave Deduction</label><input type="number" step="0.01" className="input" value={genForm.LeaveDeduction} onChange={(e) => setGenForm({...genForm, LeaveDeduction: e.target.value})} /></div>
            <div><label className="label">Commission</label><input type="number" step="0.01" className="input" value={genForm.Commission} onChange={(e) => setGenForm({...genForm, Commission: e.target.value})} /></div>
          </div>
          <div className="flex justify-end gap-2 pt-2"><Button type="button" variant="secondary" onClick={() => setGenModal(false)}>Cancel</Button><Button type="submit">Generate</Button></div>
        </form>
      </Modal>

      <Modal open={genAllModal} onClose={() => setGenAllModal(false)} title="Generate Payroll (All Active Staff)">
        <form onSubmit={generateAll} className="space-y-3">
          <p className="text-sm text-slate-500">Generates payroll for all active staff for the selected period, using each staff member's BaseSalary plus the same Bonus/Overtime/Deduction/Commission for everyone.</p>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="label">Month</label><select className="input" value={genAllForm.Month} onChange={(e) => setGenAllForm({...genAllForm, Month: e.target.value})}>{Array.from({length: 12}, (_, i) => i+1).map((m) => <option key={m} value={m}>{new Date(2000, m-1).toLocaleString('en', { month: 'long' })}</option>)}</select></div>
            <div><label className="label">Year</label><input type="number" className="input" value={genAllForm.Year} onChange={(e) => setGenAllForm({...genAllForm, Year: e.target.value})} /></div>
            <div><label className="label">Bonus (per staff)</label><input type="number" step="0.01" className="input" value={genAllForm.Bonus} onChange={(e) => setGenAllForm({...genAllForm, Bonus: e.target.value})} /></div>
            <div><label className="label">Overtime</label><input type="number" step="0.01" className="input" value={genAllForm.Overtime} onChange={(e) => setGenAllForm({...genAllForm, Overtime: e.target.value})} /></div>
            <div><label className="label">Leave Deduction</label><input type="number" step="0.01" className="input" value={genAllForm.LeaveDeduction} onChange={(e) => setGenAllForm({...genAllForm, LeaveDeduction: e.target.value})} /></div>
            <div><label className="label">Commission</label><input type="number" step="0.01" className="input" value={genAllForm.Commission} onChange={(e) => setGenAllForm({...genAllForm, Commission: e.target.value})} /></div>
          </div>
          <div className="flex justify-end gap-2 pt-2"><Button type="button" variant="secondary" onClick={() => setGenAllModal(false)}>Cancel</Button><Button type="submit">Generate All</Button></div>
        </form>
      </Modal>
    </div>
  );
}
