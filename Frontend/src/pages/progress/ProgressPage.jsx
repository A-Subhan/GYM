import { useEffect, useState, useCallback } from 'react';
import { Link } from 'react-router-dom';
import api from '../../services/api';
import { useToast } from '../../context/ToastContext';
import PageHeader from '../../components/common/PageHeader';
import Button from '../../components/common/Button';
import Modal from '../../components/common/Modal';
import DataTable from '../../components/common/DataTable';
import { LineChart, Line, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer, Legend } from 'recharts';
import { formatDate } from '../../utils/format';
import Can from '../../components/common/Can';

export default function ProgressPage() {
  const toast = useToast();
  const [rows, setRows] = useState([]);
  const [members, setMembers] = useState([]);
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [memberFilter, setMemberFilter] = useState('');
  const [modalOpen, setModalOpen] = useState(false);
  const [chartModal, setChartModal] = useState(null);
  const [chartData, setChartData] = useState([]);
  const [chartLoading, setChartLoading] = useState(false);
  const [form, setForm] = useState({ MemberID: '', Date: new Date().toISOString().slice(0,10), Weight: '', BMI: '', BodyFat: '', Waist: '', Chest: '', Arms: '', Legs: '', Notes: '' });

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [p, m] = await Promise.all([
        api.get('/progress', { params: { page, pageSize: 20, memberId: memberFilter || undefined } }),
        api.get('/members', { params: { pageSize: 200 } }),
      ]);
      setRows(p.data.data);
      setTotal(p.data.meta.total);
      setTotalPages(p.data.meta.totalPages);
      setMembers(m.data.data);
    } catch (err) { toast.error('Failed to load progress'); }
    finally { setLoading(false); }
  }, [page, memberFilter]);

  useEffect(() => { load(); }, [load]);

  const openNew = () => { setForm({ MemberID: members[0]?.MemberID || '', Date: new Date().toISOString().slice(0,10), Weight: '', BMI: '', BodyFat: '', Waist: '', Chest: '', Arms: '', Legs: '', Notes: '' }); setModalOpen(true); };

  const save = async (e) => {
    e.preventDefault();
    try {
      const payload = { ...form, MemberID: Number(form.MemberID) };
      ['Weight','BMI','BodyFat','Waist','Chest','Arms','Legs'].forEach(k => { if (payload[k] === '') payload[k] = null; else payload[k] = Number(payload[k]); });
      await api.post('/progress', payload);
      toast.success('Progress entry created'); setModalOpen(false); load();
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Save failed'); }
  };

  const remove = async (id) => {
    if (!confirm('Delete this entry?')) return;
    try { await api.delete(`/progress/${id}`); toast.success('Deleted'); load(); }
    catch (err) { toast.error('Failed'); }
  };

  const viewChart = async (member) => {
    setChartModal(member);
    setChartLoading(true);
    try {
      const res = await api.get(`/progress/chart/${member.MemberID}`);
      setChartData(res.data.data.map(d => ({ ...d, Date: formatDate(d.Date) })));
    } catch (err) { toast.error('Failed to load chart'); }
    finally { setChartLoading(false); }
  };

  const columns = [
    { key: 'MemberName', label: 'Member', render: (p) => <Link to={`/members/${p.MemberID}`} className="text-brand-600 hover:underline">{p.MemberName}</Link> },
    { key: 'Date', label: 'Date', render: (p) => formatDate(p.Date) },
    { key: 'Weight', label: 'Weight', render: (p) => p.Weight ? `${p.Weight} kg` : '—' },
    { key: 'BMI', label: 'BMI', render: (p) => p.BMI || '—' },
    { key: 'BodyFat', label: 'Body Fat', render: (p) => p.BodyFat ? `${p.BodyFat}%` : '—' },
    { key: 'Waist', label: 'Waist', render: (p) => p.Waist || '—' },
    { key: 'actions', label: '', render: (p) => (
      <div className="flex gap-2 text-sm">
        <button onClick={() => viewChart(p)} className="text-brand-600 hover:underline">Chart</button>
        <Can perm="progress.delete"><button onClick={() => remove(p.ProgressID)} className="text-red-600 hover:underline">Delete</button></Can>
      </div>
    ) },
  ];

  return (
    <div className="space-y-4">
      <PageHeader title="Progress Tracking" subtitle={`${total} entries`}
        actions={<Can perm="progress.add"><Button onClick={openNew}>+ Add Entry</Button></Can>} />

      <div className="card p-4 flex gap-3 items-end">
        <div><label className="label">Member</label><select value={memberFilter} onChange={(e) => { setMemberFilter(e.target.value); setPage(1); }} className="input w-64"><option value="">All</option>{members.map((m) => <option key={m.MemberID} value={m.MemberID}>{m.FullName} ({m.Code})</option>)}</select></div>
      </div>

      <DataTable columns={columns} rows={rows} loading={loading} pagination={{ page, totalPages, total }} onPageChange={setPage} />

      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title="Add Progress Entry">
        <form onSubmit={save} className="space-y-3">
          <div><label className="label">Member *</label><select className="input" value={form.MemberID} onChange={(e) => setForm({...form, MemberID: e.target.value})} required>{members.map((m) => <option key={m.MemberID} value={m.MemberID}>{m.FullName} ({m.Code})</option>)}</select></div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="label">Date *</label><input type="date" className="input" value={form.Date} onChange={(e) => setForm({...form, Date: e.target.value})} required /></div>
            <div><label className="label">Weight (kg)</label><input type="number" step="0.01" className="input" value={form.Weight} onChange={(e) => setForm({...form, Weight: e.target.value})} /></div>
            <div><label className="label">BMI</label><input type="number" step="0.01" className="input" value={form.BMI} onChange={(e) => setForm({...form, BMI: e.target.value})} /></div>
            <div><label className="label">Body Fat %</label><input type="number" step="0.01" className="input" value={form.BodyFat} onChange={(e) => setForm({...form, BodyFat: e.target.value})} /></div>
            <div><label className="label">Waist (cm)</label><input type="number" step="0.01" className="input" value={form.Waist} onChange={(e) => setForm({...form, Waist: e.target.value})} /></div>
            <div><label className="label">Chest (cm)</label><input type="number" step="0.01" className="input" value={form.Chest} onChange={(e) => setForm({...form, Chest: e.target.value})} /></div>
            <div><label className="label">Arms (cm)</label><input type="number" step="0.01" className="input" value={form.Arms} onChange={(e) => setForm({...form, Arms: e.target.value})} /></div>
            <div><label className="label">Legs (cm)</label><input type="number" step="0.01" className="input" value={form.Legs} onChange={(e) => setForm({...form, Legs: e.target.value})} /></div>
          </div>
          <div><label className="label">Notes</label><textarea className="input" rows="2" value={form.Notes} onChange={(e) => setForm({...form, Notes: e.target.value})} /></div>
          <div className="flex justify-end gap-2 pt-2"><Button type="button" variant="secondary" onClick={() => setModalOpen(false)}>Cancel</Button><Button type="submit">Save</Button></div>
        </form>
      </Modal>

      <Modal open={!!chartModal} onClose={() => setChartModal(null)} title={`Progress Chart — ${chartModal?.MemberName}`} size="xl">
        {chartLoading ? <div className="p-8 flex justify-center"><div className="w-8 h-8 border-4 border-brand-500 border-t-transparent rounded-full animate-spin" /></div> : (
          chartData.length === 0 ? <p className="text-center text-slate-400 py-8">No data points</p> : (
            <div className="space-y-4">
              <ResponsiveContainer width="100%" height={300}>
                <LineChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" stroke="rgba(148,163,184,0.15)" />
                  <XAxis dataKey="Date" stroke="#94a3b8" fontSize={11} />
                  <YAxis stroke="#94a3b8" fontSize={11} />
                  <Tooltip contentStyle={{ background: 'rgba(15,23,42,0.95)', border: '1px solid rgba(148,163,184,0.2)', borderRadius: 8, color: '#fff' }} />
                  <Legend />
                  <Line type="monotone" dataKey="Weight" stroke="#3478f6" strokeWidth={2} dot={{ r: 3 }} />
                  <Line type="monotone" dataKey="BodyFat" stroke="#14b8a6" strokeWidth={2} dot={{ r: 3 }} />
                  <Line type="monotone" dataKey="Waist" stroke="#f59e0b" strokeWidth={2} dot={{ r: 3 }} />
                </LineChart>
              </ResponsiveContainer>
              <ResponsiveContainer width="100%" height={300}>
                <LineChart data={chartData}>
                  <CartesianGrid strokeDasharray="3 3" stroke="rgba(148,163,184,0.15)" />
                  <XAxis dataKey="Date" stroke="#94a3b8" fontSize={11} />
                  <YAxis stroke="#94a3b8" fontSize={11} />
                  <Tooltip contentStyle={{ background: 'rgba(15,23,42,0.95)', border: '1px solid rgba(148,163,184,0.2)', borderRadius: 8, color: '#fff' }} />
                  <Legend />
                  <Line type="monotone" dataKey="Chest" stroke="#8b5cf6" strokeWidth={2} dot={{ r: 3 }} />
                  <Line type="monotone" dataKey="Arms" stroke="#ec4899" strokeWidth={2} dot={{ r: 3 }} />
                  <Line type="monotone" dataKey="Legs" stroke="#10b981" strokeWidth={2} dot={{ r: 3 }} />
                </LineChart>
              </ResponsiveContainer>
            </div>
          )
        )}
      </Modal>
    </div>
  );
}
