import { useEffect, useState, useCallback } from 'react';
import api from '../../services/api';
import { useToast } from '../../context/ToastContext';
import { useAuth } from '../../context/AuthContext';
import PageHeader from '../../components/common/PageHeader';
import Button from '../../components/common/Button';
import Modal from '../../components/common/Modal';
import DataTable from '../../components/common/DataTable';
import Can from '../../components/common/Can';
import { PERMISSIONS as P } from '../../constants/permissions';

const EMPTY_ITEM_FORM = { Name: '', IsActive: true, BranchID: '' };

export default function MasterFilesPage() {
  const toast = useToast();
  const { user } = useAuth();
  const isSuperAdmin = user?.isSuperAdmin === true;

  /* master file dropdown */
  const [definitions, setDefinitions] = useState([]);
  const [definitionsLoading, setDefinitionsLoading] = useState(true);
  const [selectedDefId, setSelectedDefId] = useState('');
  const selectedDef = definitions.find((d) => String(d.MasterDefinitionID) === String(selectedDefId)) || null;

  /* grid */
  const [rows, setRows] = useState([]);
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('');

  /* modals */
  const [addOpen, setAddOpen] = useState(false);
  const [editing, setEditing] = useState(null);
  const [itemForm, setItemForm] = useState(EMPTY_ITEM_FORM);
  const [saving, setSaving] = useState(false);
  const [manageOpen, setManageOpen] = useState(false);
  const [defForm, setDefForm] = useState({ Name: '', MasterCode: '', Scope: 'Global' });
  const [branches, setBranches] = useState([]);

  useEffect(() => {
    const t = setTimeout(() => { setDebouncedSearch(search); setPage(1); }, 400);
    return () => clearTimeout(t);
  }, [search]);

  const loadDefinitions = useCallback(async () => {
    setDefinitionsLoading(true);
    try {
      const res = await api.get('/masters/definitions');
      setDefinitions(res.data.data || []);
      setSelectedDefId((current) => {
        if (current && res.data.data?.some((d) => String(d.MasterDefinitionID) === String(current))) return current;
        return res.data.data?.[0] ? String(res.data.data[0].MasterDefinitionID) : '';
      });
    } catch (err) { toast.error('Failed to load master files'); }
    finally { setDefinitionsLoading(false); }
  }, [toast]);

  const loadItems = useCallback(async () => {
    if (!selectedDefId) { setRows([]); setTotal(0); setTotalPages(1); return; }
    setLoading(true);
    try {
      const res = await api.get(`/masters/${selectedDefId}/items`, {
        params: {
          page,
          pageSize: 20,
          search: debouncedSearch || undefined,
          status: statusFilter || undefined,
        },
      });
      setRows(res.data.data || []);
      setTotal(res.data.meta?.total || 0);
      setTotalPages(res.data.meta?.totalPages || 1);
    } catch (err) { toast.error('Failed to load records'); }
    finally { setLoading(false); }
  }, [selectedDefId, page, debouncedSearch, statusFilter, toast]);

  useEffect(() => { loadDefinitions(); }, [loadDefinitions]);
  useEffect(() => { loadItems(); }, [loadItems]);

  useEffect(() => {
    if (!selectedDef?.Scope || selectedDef.Scope !== 'Branch') return;
    api.get('/branches').then((res) => setBranches(res.data.data || [])).catch(() => setBranches([]));
  }, [selectedDef?.Scope]);

  /* ----------- add / edit ----------- */

  const openAdd = () => { setEditing(null); setItemForm({ ...EMPTY_ITEM_FORM }); setAddOpen(true); };

  const openEdit = (row) => {
    setEditing(row);
    setItemForm({ Name: row.Name, IsActive: Boolean(row.IsActive), BranchID: row.BranchID || '' });
    setAddOpen(true);
  };

  const saveItem = async (e) => {
    e.preventDefault();
    if (!itemForm.Name.trim()) return toast.error('Name is required');
    setSaving(true);
    try {
      if (editing) {
        await api.put(`/masters/items/${editing.MasterItemID}`, { Name: itemForm.Name.trim() });
        if (Boolean(editing.IsActive) !== itemForm.IsActive) {
          await api.patch(`/masters/items/${editing.MasterItemID}/status`, { IsActive: itemForm.IsActive });
        }
        toast.success('Record updated');
      } else {
        await api.post(`/masters/${selectedDefId}/items`, {
          Name: itemForm.Name.trim(),
          BranchID: selectedDef?.Scope === 'Branch' && isSuperAdmin && itemForm.BranchID ? Number(itemForm.BranchID) : undefined,
        });
        toast.success('Record added');
      }
      setAddOpen(false);
      loadItems();
      loadDefinitions();
    } catch (err) {
      toast.error(err.response?.data?.error?.message || 'Save failed');
    } finally { setSaving(false); }
  };

  const toggleStatus = async (row) => {
    const next = !row.IsActive;
    /* optimistic revert on failure */
    setRows((current) => current.map((r) => (r.MasterItemID === row.MasterItemID ? { ...r, IsActive: next } : r)));
    try {
      await api.patch(`/masters/items/${row.MasterItemID}/status`, { IsActive: next });
      toast.success(next ? 'Activated' : 'Deactivated');
    } catch (err) {
      setRows((current) => current.map((r) => (r.MasterItemID === row.MasterItemID ? { ...r, IsActive: row.IsActive } : r)));
      toast.error(err.response?.data?.error?.message || 'Failed to change status');
    }
  };

  const remove = async (row) => {
    if (!confirm(`Delete ${row.Name} (${row.ItemCode})?`)) return;
    try {
      await api.delete(`/masters/items/${row.MasterItemID}`);
      toast.success('Deleted');
      loadItems();
      loadDefinitions();
    } catch (err) {
      toast.error(err.response?.data?.error?.message || `${row.Name} cannot be deleted because it is currently in use.`);
    }
  };

  /* ----------- manage master files (definitions) ----------- */

  const saveDefinition = async (e) => {
    e.preventDefault();
    if (!defForm.Name.trim()) return toast.error('Master name is required');
    setSaving(true);
    try {
      await api.post('/masters/definitions', {
        Name: defForm.Name.trim(),
        MasterCode: defForm.MasterCode.trim() || undefined,
        Scope: defForm.Scope,
      });
      toast.success('Master file created');
      setManageOpen(false);
      setDefForm({ Name: '', MasterCode: '', Scope: 'Global' });
      const res = await api.get('/masters/definitions');
      const list = res.data.data || [];
      setDefinitions(list);
      const created = list.find((d) => d.Name.toLowerCase() === defForm.Name.trim().toLowerCase());
      if (created) { setSelectedDefId(String(created.MasterDefinitionID)); setPage(1); }
    } catch (err) {
      toast.error(err.response?.data?.error?.message || 'Save failed');
    } finally { setSaving(false); }
  };

  const columns = [
    { key: 'actions', label: 'Action', render: (row) => (
      <div className="flex gap-2 whitespace-nowrap">
        <Can perm={P.MASTERS_EDIT}><button onClick={() => openEdit(row)} className="text-brand-600 hover:underline text-sm">Edit</button></Can>
        <Can perm={P.MASTERS_DELETE}><button onClick={() => remove(row)} className="text-red-600 hover:underline text-sm">Delete</button></Can>
      </div>
    ) },
    { key: 'ItemCode', label: 'Code', render: (row) => <span className="font-mono text-xs">{row.ItemCode}</span> },
    { key: 'Name', label: 'Name', render: (row) => <span className="font-medium">{row.Name}</span> },
    { key: 'IsActive', label: 'Status', render: (row) => (
      <Can perm={P.MASTERS_STATUS} fallback={
        <span className={`badge ${row.IsActive ? 'badge-success' : 'badge-neutral'}`}>{row.IsActive ? 'Active' : 'Inactive'}</span>
      }>
        <label className="inline-flex items-center gap-2 cursor-pointer select-none" title={row.IsActive ? 'Active — click to deactivate' : 'Inactive — click to activate'}>
          <input type="checkbox" checked={row.IsActive} onChange={() => toggleStatus(row)} />
          <span className={`text-sm ${row.IsActive ? 'text-emerald-600' : 'text-slate-400'}`}>{row.IsActive ? 'Active' : 'Inactive'}</span>
        </label>
      </Can>
    ) },
  ];

  return (
    <div className="space-y-4">
      <PageHeader title="Master Files" subtitle="Central lists used across the system — codes are generated automatically"
        actions={<Can perm={P.MASTERS_ADD}><Button variant="secondary" onClick={() => setManageOpen(true)}>Manage Master Files</Button></Can>} />

      <div className="card p-4 flex flex-wrap gap-3 items-end">
        <div className="w-64">
          <label className="label">Master File</label>
          <select
            className="input"
            value={selectedDefId}
            onChange={(e) => { setSelectedDefId(e.target.value); setPage(1); setSearch(''); setStatusFilter(''); }}
            disabled={definitionsLoading}
          >
            {definitions.length === 0 && <option value="">No master files</option>}
            {definitions.map((d) => (
              <option key={d.MasterDefinitionID} value={d.MasterDefinitionID}>
                {d.MasterCode} — {d.Name}
              </option>
            ))}
          </select>
        </div>

        <div className="flex-1 min-w-[200px]">
          <label className="label">Search</label>
          <input className="input" placeholder="Search by name or code…" value={search} onChange={(e) => setSearch(e.target.value)} />
        </div>

        <div className="w-40">
          <label className="label">Status</label>
          <select className="input" value={statusFilter} onChange={(e) => { setStatusFilter(e.target.value); setPage(1); }}>
            <option value="">All</option>
            <option value="active">Active</option>
            <option value="inactive">Inactive</option>
          </select>
        </div>

        <Can perm={P.MASTERS_ADD}>
          <Button onClick={openAdd} disabled={!selectedDef}>
            + Add {selectedDef ? selectedDef.Name : ''}
          </Button>
        </Can>
      </div>

      <div className="card overflow-hidden">
        {selectedDef && (
          <div className="px-4 pt-4">
            <h2 className="font-semibold">
              {selectedDef.Name}
              <span className="ml-2 text-xs font-normal text-slate-400">
                code {selectedDef.MasterCode} · {selectedDef.Scope} · {selectedDef.ItemCount} records
              </span>
            </h2>
          </div>
        )}
        <DataTable
          columns={columns}
          rows={rows}
          loading={loading || definitionsLoading}
          pagination={{ page, totalPages, total }}
          onPageChange={setPage}
        />
      </div>

      {/* Add / Edit record modal */}
      <Modal
        open={addOpen}
        onClose={() => setAddOpen(false)}
        title={editing ? `Edit — ${selectedDef?.Name}` : `Add ${selectedDef?.Name || ''}`}
        size="sm"
      >
        <form onSubmit={saveItem} className="space-y-3">
          {editing && (
            <div>
              <label className="label">Code</label>
              <input className="input bg-slate-100 dark:bg-slate-800" value={editing.ItemCode} disabled />
              <p className="text-xs text-slate-500 mt-1">Codes are system generated and cannot be changed.</p>
            </div>
          )}

          <div>
            <label className="label">Name *</label>
            <input
              className="input"
              maxLength={50}
              value={itemForm.Name}
              onChange={(e) => setItemForm({ ...itemForm, Name: e.target.value })}
              placeholder={selectedDef ? `e.g. ${selectedDef.Name === 'Education' ? 'Matric' : selectedDef.Name === 'Currency' ? 'US Dollar' : 'Manager'}` : ''}
              required
              autoFocus
            />
          </div>

          {selectedDef?.Scope === 'Branch' && (
            <div>
              <label className="label">Branch {!isSuperAdmin && '(your branch)'}</label>
              {isSuperAdmin ? (
                <select className="input" value={itemForm.BranchID} onChange={(e) => setItemForm({ ...itemForm, BranchID: e.target.value })} required>
                  <option value="">— Select branch —</option>
                  {branches.map((b) => <option key={b.BranchID} value={b.BranchID}>{b.Name}</option>)}
                </select>
              ) : (
                <input className="input bg-slate-100 dark:bg-slate-800" value={user?.branchName || 'Your branch'} disabled />
              )}
            </div>
          )}

          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={itemForm.IsActive}
              onChange={(e) => setItemForm({ ...itemForm, IsActive: e.target.checked })}
            />
            Active
          </label>

          <div className="flex justify-end gap-2 pt-1">
            <Button type="button" variant="secondary" onClick={() => setAddOpen(false)}>Cancel</Button>
            <Button type="submit" disabled={saving}>{saving ? 'Saving…' : editing ? 'Update' : 'Save'}</Button>
          </div>
        </form>
      </Modal>

      {/* Manage master files modal */}
      <Modal open={manageOpen} onClose={() => setManageOpen(false)} title="Manage Master Files">
        <form onSubmit={saveDefinition} className="space-y-3">
          <p className="text-sm text-slate-500">Create a new master file definition. It will appear in the Master File dropdown immediately.</p>
          <div>
            <label className="label">Master Name *</label>
            <input className="input" maxLength={50} value={defForm.Name} onChange={(e) => setDefForm({ ...defForm, Name: e.target.value })} placeholder="e.g. Color, Size, Religion" required autoFocus />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="label">Master Code</label>
              <input className="input" value={defForm.MasterCode} onChange={(e) => setDefForm({ ...defForm, MasterCode: e.target.value.replace(/\D/g, '').slice(0, 5) })} placeholder="Auto (e.g. 04)" inputMode="numeric" />
              <p className="text-xs text-slate-500 mt-1">Leave empty to auto-generate the next code.</p>
            </div>
            <div>
              <label className="label">Scope</label>
              <select className="input" value={defForm.Scope} onChange={(e) => setDefForm({ ...defForm, Scope: e.target.value })}>
                <option value="Global">Global (all branches)</option>
                <option value="Branch">Branch specific</option>
              </select>
            </div>
          </div>

          <div>
            <label className="label">Existing master files</label>
            <div className="border border-slate-200 dark:border-slate-700 rounded-lg max-h-40 overflow-y-auto text-sm">
              {definitions.map((d) => (
                <div key={d.MasterDefinitionID} className="flex justify-between px-3 py-2 border-b border-slate-100 dark:border-slate-800 last:border-b-0">
                  <span className="font-mono text-xs text-slate-400">{d.MasterCode}</span>
                  <span className="flex-1 px-3">{d.Name}</span>
                  <span className="text-xs text-slate-400">{d.Scope} · {d.ItemCount}</span>
                </div>
              ))}
            </div>
          </div>

          <div className="flex justify-end gap-2 pt-1">
            <Button type="button" variant="secondary" onClick={() => setManageOpen(false)}>Close</Button>
            <Button type="submit" disabled={saving}>{saving ? 'Saving…' : 'Create Master File'}</Button>
          </div>
        </form>
      </Modal>
    </div>
  );
}
