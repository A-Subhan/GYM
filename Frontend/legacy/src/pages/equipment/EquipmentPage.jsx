import { useEffect, useState, useCallback } from 'react';
import api from '../../services/api';
import { useToast } from '../../context/ToastContext';
import { useAuth } from '../../context/AuthContext';
import PageHeader from '../../components/common/PageHeader';
import Button from '../../components/common/Button';
import Modal from '../../components/common/Modal';
import DataTable from '../../components/common/DataTable';
import { formatDate, formatCurrency } from '../../utils/format';
import { StatusBadge } from '../../components/common/Badge';
import Can from '../../components/common/Can';

export default function EquipmentPage() {
  const toast = useToast();
  const { hasPermission } = useAuth();
  const [rows, setRows] = useState([]);
  const [branches, setBranches] = useState([]);
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [total, setTotal] = useState(0);
  const [meta, setMeta] = useState({});
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [tab, setTab] = useState('equipment');
  const [maintenance, setMaintenance] = useState([]);
  const [modalOpen, setModalOpen] = useState(false);
  const [maintModal, setMaintModal] = useState(false);
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState({});
  const [maintForm, setMaintForm] = useState({ EquipmentID: '', Type: 'Routine', Cost: 0, StartDate: new Date().toISOString().slice(0,10), EndDate: '', Notes: '' });

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [e, b, m] = await Promise.all([
        api.get('/equipment', { params: { page, pageSize: 50, search: search || undefined, status: statusFilter || undefined } }),
        api.get('/branches').catch(() => ({ data: { data: [] } })),
        api.get('/equipment/maintenance/all'),
      ]);
      setRows(e.data.data);
      setTotal(e.data.meta.total);
      setTotalPages(Math.ceil((e.data.meta.total || 0) / 50));
      setMeta(e.data.meta);
      setBranches(b.data.data);
      setMaintenance(m.data.data);
    } catch (err) { toast.error('Failed to load equipment'); }
    finally { setLoading(false); }
  }, [page, search, statusFilter]);

  useEffect(() => { load(); }, [load]);

  const openNew = () => {
    setEditing(null);
    setForm({ BranchID: '', Name: '', Brand: '', SerialNo: '', PurchaseDate: '', PurchasePrice: '', WarrantyExpiry: '', Status: 'Active', Notes: '' });
    setModalOpen(true);
  };
  const openEdit = (e) => {
    setEditing(e.EquipmentID);
    setForm({ BranchID: e.BranchID || '', Name: e.Name, Brand: e.Brand || '', SerialNo: e.SerialNo || '', PurchaseDate: e.PurchaseDate ? e.PurchaseDate.slice(0,10) : '', PurchasePrice: e.PurchasePrice || '', WarrantyExpiry: e.WarrantyExpiry ? e.WarrantyExpiry.slice(0,10) : '', Status: e.Status, Notes: e.Notes || '' });
    setModalOpen(true);
  };

  const save = async (e) => {
    e.preventDefault();
    try {
      const payload = { ...form, BranchID: form.BranchID ? Number(form.BranchID) : null, PurchasePrice: form.PurchasePrice ? Number(form.PurchasePrice) : null };
      if (editing) await api.put(`/equipment/${editing}`, payload);
      else await api.post('/equipment', payload);
      toast.success('Saved'); setModalOpen(false); load();
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Save failed'); }
  };

  const remove = async (id) => {
    if (!confirm('Delete this equipment?')) return;
    try { await api.delete(`/equipment/${id}`); toast.success('Deleted'); load(); }
    catch (err) { toast.error('Failed'); }
  };

  const openMaint = () => { setMaintForm({ EquipmentID: rows[0]?.EquipmentID || '', Type: 'Routine', Cost: 0, StartDate: new Date().toISOString().slice(0,10), EndDate: '', Notes: '' }); setMaintModal(true); };

  const saveMaint = async (e) => {
    e.preventDefault();
    try {
      await api.post('/equipment/maintenance', { ...maintForm, EquipmentID: Number(maintForm.EquipmentID), Cost: Number(maintForm.Cost) });
      toast.success('Maintenance logged'); setMaintModal(false); load();
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Failed'); }
  };

  const completeMaint = async (id) => {
    if (!confirm('Mark this maintenance as completed?')) return;
    try { await api.post(`/equipment/maintenance/${id}/complete`); toast.success('Completed'); load(); }
    catch (err) { toast.error('Failed'); }
  };

  const columns = [
    { key: 'Name', label: 'Equipment', render: (e) => <div><div className="font-medium">{e.Name}</div><div className="text-xs text-slate-400">{e.Brand}</div></div> },
    { key: 'SerialNo', label: 'Serial #', render: (e) => e.SerialNo || '—' },
    { key: 'PurchaseDate', label: 'Purchased', render: (e) => formatDate(e.PurchaseDate) },
    { key: 'PurchasePrice', label: 'Price', render: (e) => formatCurrency(e.PurchasePrice) },
    { key: 'WarrantyExpiry', label: 'Warranty', render: (e) => formatDate(e.WarrantyExpiry) },
    { key: 'Status', label: 'Status', render: (e) => <StatusBadge status={e.Status} /> },
    { key: 'actions', label: '', render: (e) => (
      <div className="flex gap-2 text-sm">
        <Can perm="equipment.edit"><button onClick={() => openEdit(e)} className="text-brand-600 hover:underline">Edit</button></Can>
        <Can perm="equipment.delete"><button onClick={() => remove(e.EquipmentID)} className="text-red-600 hover:underline">Delete</button></Can>
      </div>
    ) },
  ];

  return (
    <div className="space-y-4">
      <PageHeader title="Equipment" subtitle={`${total} items · ${meta.ActiveCount || 0} active · ${meta.MaintenanceCount || 0} in maintenance · ${meta.BrokenCount || 0} broken`}
        actions={
          <Can perm="equipment.add">
            <div className="flex gap-2">
              <Button variant="secondary" onClick={openMaint}>+ Log Maintenance</Button>
              <Button onClick={openNew}>+ Add Equipment</Button>
            </div>
          </Can>
        } />

      <div className="card overflow-hidden">
        <div className="flex border-b border-slate-200 dark:border-slate-800">
          {['equipment','maintenance'].map((t) => (
            <button key={t} onClick={() => setTab(t)} className={`px-5 py-3 text-sm font-medium border-b-2 capitalize ${tab === t ? 'border-brand-600 text-brand-600' : 'border-transparent text-slate-500 hover:text-slate-700'}`}>{t}</button>
          ))}
        </div>

        {tab === 'equipment' && (
          <>
            <div className="p-4 flex flex-wrap gap-3 items-end">
              <div className="flex-1 min-w-[200px]"><input placeholder="Search name, brand, serial…" value={search} onChange={(e) => { setSearch(e.target.value); setPage(1); }} className="input" /></div>
              <select value={statusFilter} onChange={(e) => { setStatusFilter(e.target.value); setPage(1); }} className="input w-40"><option value="">All Status</option><option>Active</option><option>Maintenance</option><option>Broken</option><option>Sold</option></select>
            </div>
            <DataTable columns={columns} rows={rows} loading={loading} pagination={{ page, totalPages, total }} onPageChange={setPage} />
          </>
        )}

        {tab === 'maintenance' && (
          <div className="table-wrap">
            <table className="table">
              <thead><tr><th>Equipment</th><th>Type</th><th>Cost</th><th>Start</th><th>End</th><th>Notes</th><th></th></tr></thead>
              <tbody>
                {maintenance.length === 0 && <tr><td colSpan={7} className="text-center text-slate-400 py-8">No maintenance records</td></tr>}
                {maintenance.map((m) => (
                  <tr key={m.MaintID}>
                    <td className="font-medium">{m.EquipmentName}<div className="text-xs text-slate-400">{m.Brand}</div></td>
                    <td><span className="badge-info">{m.Type}</span></td>
                    <td>{formatCurrency(m.Cost)}</td>
                    <td>{formatDate(m.StartDate)}</td>
                    <td>{m.EndDate ? formatDate(m.EndDate) : <span className="text-amber-600">In progress</span>}</td>
                    <td className="max-w-xs truncate">{m.Notes || '—'}</td>
                    <td>{!m.EndDate && <button onClick={() => completeMaint(m.MaintID)} className="text-emerald-600 hover:underline text-sm">Complete</button>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editing ? 'Edit Equipment' : 'New Equipment'} size="lg">
        <form onSubmit={save} className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div className="col-span-2"><label className="label">Name *</label><input className="input" value={form.Name} onChange={(e) => setForm({...form, Name: e.target.value})} required /></div>
            <div><label className="label">Brand</label><input className="input" value={form.Brand} onChange={(e) => setForm({...form, Brand: e.target.value})} /></div>
            <div><label className="label">Serial No</label><input className="input" value={form.SerialNo} onChange={(e) => setForm({...form, SerialNo: e.target.value})} /></div>
            <div><label className="label">Branch</label><select className="input" value={form.BranchID} onChange={(e) => setForm({...form, BranchID: e.target.value})}><option value="">— None —</option>{branches.map((b) => <option key={b.BranchID} value={b.BranchID}>{b.Name}</option>)}</select></div>
            <div><label className="label">Status</label><select className="input" value={form.Status} onChange={(e) => setForm({...form, Status: e.target.value})}><option>Active</option><option>Maintenance</option><option>Broken</option><option>Sold</option></select></div>
            <div><label className="label">Purchase Date</label><input type="date" className="input" value={form.PurchaseDate} onChange={(e) => setForm({...form, PurchaseDate: e.target.value})} /></div>
            <div><label className="label">Purchase Price</label><input type="number" step="0.01" className="input" value={form.PurchasePrice} onChange={(e) => setForm({...form, PurchasePrice: e.target.value})} /></div>
            <div><label className="label">Warranty Expiry</label><input type="date" className="input" value={form.WarrantyExpiry} onChange={(e) => setForm({...form, WarrantyExpiry: e.target.value})} /></div>
            <div className="col-span-2"><label className="label">Notes</label><textarea className="input" rows="2" value={form.Notes} onChange={(e) => setForm({...form, Notes: e.target.value})} /></div>
          </div>
          <div className="flex justify-end gap-2 pt-2"><Button type="button" variant="secondary" onClick={() => setModalOpen(false)}>Cancel</Button><Button type="submit">{editing ? 'Update' : 'Create'}</Button></div>
        </form>
      </Modal>

      <Modal open={maintModal} onClose={() => setMaintModal(false)} title="Log Maintenance">
        <form onSubmit={saveMaint} className="space-y-3">
          <div><label className="label">Equipment *</label><select className="input" value={maintForm.EquipmentID} onChange={(e) => setMaintForm({...maintForm, EquipmentID: e.target.value})} required>{rows.map((e) => <option key={e.EquipmentID} value={e.EquipmentID}>{e.Name}</option>)}</select></div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="label">Type</label><select className="input" value={maintForm.Type} onChange={(e) => setMaintForm({...maintForm, Type: e.target.value})}><option>Routine</option><option>Repair</option><option>Inspection</option></select></div>
            <div><label className="label">Cost</label><input type="number" step="0.01" className="input" value={maintForm.Cost} onChange={(e) => setMaintForm({...maintForm, Cost: e.target.value})} /></div>
            <div><label className="label">Start Date *</label><input type="date" className="input" value={maintForm.StartDate} onChange={(e) => setMaintForm({...maintForm, StartDate: e.target.value})} required /></div>
            <div><label className="label">End Date</label><input type="date" className="input" value={maintForm.EndDate} onChange={(e) => setMaintForm({...maintForm, EndDate: e.target.value})} /></div>
          </div>
          <div><label className="label">Notes</label><textarea className="input" rows="2" value={maintForm.Notes} onChange={(e) => setMaintForm({...maintForm, Notes: e.target.value})} /></div>
          <div className="flex justify-end gap-2 pt-2"><Button type="button" variant="secondary" onClick={() => setMaintModal(false)}>Cancel</Button><Button type="submit">Log</Button></div>
        </form>
      </Modal>
    </div>
  );
}
