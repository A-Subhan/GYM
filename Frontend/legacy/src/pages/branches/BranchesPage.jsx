import { useEffect, useState, useCallback } from 'react';
import api from '../../services/api';
import { useToast } from '../../context/ToastContext';
import { formatDate } from '../../utils/format';
import Pagination from '../../components/common/Pagination';
import Spinner from '../../components/common/Spinner';
import Button from '../../components/common/Button';
import Modal from '../../components/common/Modal';
import { StatusBadge } from '../../components/common/Badge';

export default function BranchesPage() {
  const toast = useToast();
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState({ Code: '', Name: '', Address: '', City: '', Phone: '', Email: '', ManagerName: '' });

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await api.get('/branches');
      setRows(res.data.data);
    } catch (err) { toast.error('Failed to load branches'); }
    finally { setLoading(false); }
  }, []);

  useEffect(() => { load(); }, [load]);

  const openNew = () => { setEditing(null); setForm({ Code: '', Name: '', Address: '', City: '', Phone: '', Email: '', ManagerName: '' }); setModalOpen(true); };
  const openEdit = (b) => { setEditing(b.BranchID); setForm({ Code: b.Code, Name: b.Name, Address: b.Address || '', City: b.City || '', Phone: b.Phone || '', Email: b.Email || '', ManagerName: b.ManagerName || '' }); setModalOpen(true); };

  const save = async (e) => {
    e.preventDefault();
    try {
      if (editing) await api.put(`/branches/${editing}`, form);
      else await api.post('/branches', form);
      toast.success('Saved');
      setModalOpen(false); load();
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Save failed'); }
  };

  if (loading) return <Spinner size="lg" className="mt-20" />;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Branches</h1>
        <Button onClick={openNew}>+ New Branch</Button>
      </div>
      <div className="card overflow-hidden">
        <div className="table-wrap">
          <table className="table">
            <thead><tr><th>Code</th><th>Name</th><th>City</th><th>Phone</th><th>Manager</th><th>Status</th><th></th></tr></thead>
            <tbody>
              {rows.map((b) => (
                <tr key={b.BranchID}>
                  <td className="font-mono text-xs">{b.Code}</td>
                  <td className="font-medium">{b.Name}</td>
                  <td>{b.City || '—'}</td>
                  <td>{b.Phone || '—'}</td>
                  <td>{b.ManagerName || '—'}</td>
                  <td><StatusBadge status={b.IsActive ? 'Active' : 'Inactive'} /></td>
                  <td><button onClick={() => openEdit(b)} className="text-brand-600 hover:underline text-sm">Edit</button></td>
                </tr>
              ))}
              {rows.length === 0 && <tr><td colSpan={7} className="text-center text-slate-400 py-8">No branches yet.</td></tr>}
            </tbody>
          </table>
        </div>
      </div>

      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editing ? 'Edit Branch' : 'New Branch'}>
        <form onSubmit={save} className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div><label className="label">Code *</label><input className="input" value={form.Code} onChange={(e) => setForm({...form, Code: e.target.value})} required /></div>
            <div><label className="label">Name *</label><input className="input" value={form.Name} onChange={(e) => setForm({...form, Name: e.target.value})} required /></div>
            <div className="col-span-2"><label className="label">Address</label><input className="input" value={form.Address} onChange={(e) => setForm({...form, Address: e.target.value})} /></div>
            <div><label className="label">City</label><input className="input" value={form.City} onChange={(e) => setForm({...form, City: e.target.value})} /></div>
            <div><label className="label">Phone</label><input className="input" value={form.Phone} onChange={(e) => setForm({...form, Phone: e.target.value})} /></div>
            <div><label className="label">Email</label><input type="email" className="input" value={form.Email} onChange={(e) => setForm({...form, Email: e.target.value})} /></div>
            <div><label className="label">Manager</label><input className="input" value={form.ManagerName} onChange={(e) => setForm({...form, ManagerName: e.target.value})} /></div>
          </div>
          <div className="flex justify-end gap-2 pt-2"><Button type="button" variant="secondary" onClick={() => setModalOpen(false)}>Cancel</Button><Button type="submit">Save</Button></div>
        </form>
      </Modal>
    </div>
  );
}
