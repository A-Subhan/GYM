import { useCallback, useEffect, useState } from 'react';
import api from '../../../services/api';
import { useToast } from '../../../context/ToastContext';
import PageHeader from '../../../components/common/PageHeader';
import Button from '../../../components/common/Button';
import Modal from '../../../components/common/Modal';
import Can from '../../../components/common/Can';
import Badge from '../../../components/common/Badge';
import Spinner from '../../../components/common/Spinner';
import ConfirmDialog from '../../../components/common/ConfirmDialog';

const TAX_TYPES = ['Withholding', 'SalesTax', 'Other'];
const EMPTY = { Code: '', Name: '', Description: '', RatePercent: '', TaxType: '' };

/** Tax Heads master — voucher tax selections load from here (never hard-coded). */
export default function TaxHeadsPage() {
  const toast = useToast();
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(true);
  const [includeInactive, setIncludeInactive] = useState(true);

  const [addOpen, setAddOpen] = useState(false);
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(EMPTY);
  const [saving, setSaving] = useState(false);
  const [statusTarget, setStatusTarget] = useState(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await api.get('/finance/tax-heads', { params: { includeInactive } });
      setRows(res.data.data || []);
    } catch (err) { toast.error('Failed to load tax heads'); }
    finally { setLoading(false); }
  }, [includeInactive, toast]);

  useEffect(() => { load(); }, [load]);

  const openAdd = () => { setEditing(null); setForm(EMPTY); setAddOpen(true); };
  const openEdit = (r) => {
    setEditing(r);
    setForm({
      Code: r.Code, Name: r.Name, Description: r.Description || '',
      RatePercent: r.RatePercent ?? '', TaxType: r.TaxType || '',
    });
    setAddOpen(true);
  };

  const save = async (e) => {
    e.preventDefault();
    if (!form.Code.trim() || !form.Name.trim()) return toast.error('Code and name are required');
    setSaving(true);
    try {
      if (editing) {
        await api.put(`/finance/tax-heads/${editing.TaxHeadID}`, {
          Name: form.Name.trim(),
          Description: form.Description || null,
          RatePercent: form.RatePercent === '' ? null : Number(form.RatePercent),
          TaxType: form.TaxType || null,
        });
        toast.success('Tax head updated');
      } else {
        await api.post('/finance/tax-heads', {
          Code: form.Code.trim(),
          Name: form.Name.trim(),
          Description: form.Description || null,
          RatePercent: form.RatePercent === '' ? null : Number(form.RatePercent),
          TaxType: form.TaxType || null,
        });
        toast.success('Tax head created');
      }
      setAddOpen(false);
      load();
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Save failed'); }
    finally { setSaving(false); }
  };

  const doToggleStatus = async () => {
    if (!statusTarget) return;
    try {
      await api.patch(`/finance/tax-heads/${statusTarget.TaxHeadID}/status`, { IsActive: !statusTarget.IsActive });
      toast.success(statusTarget.IsActive ? 'Tax head deactivated' : 'Tax head activated');
      setStatusTarget(null);
      load();
    } catch (err) { toast.error('Failed'); setStatusTarget(null); }
  };

  return (
    <div className="space-y-4">
      <PageHeader
        title="Tax Heads"
        subtitle="Master data for taxes selectable on voucher lines (e.g. withholding and sales tax heads)."
        actions={
          <div className="flex gap-3 items-center">
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={includeInactive} onChange={(e) => setIncludeInactive(e.target.checked)} />
              Show inactive
            </label>
            <Can perm="finance.coa"><Button onClick={openAdd}>+ Add Tax Head</Button></Can>
          </div>
        }
      />

      <div className="card overflow-hidden">
        {loading ? <div className="p-8"><Spinner /></div> : (
          <div className="table-wrap">
            <table className="table">
              <thead><tr><th>Code</th><th>Name</th><th>Type</th><th>Rate %</th><th>Status</th><th className="no-print">Actions</th></tr></thead>
              <tbody>
                {rows.length === 0 && <tr><td colSpan={6} className="text-center text-slate-400 py-8">No tax heads yet</td></tr>}
                {rows.map((r) => (
                  <tr key={r.TaxHeadID}>
                    <td className="font-mono text-xs">{r.Code}</td>
                    <td className="font-medium">{r.Name}{r.Description && <div className="text-xs text-slate-400">{r.Description}</div>}</td>
                    <td><Badge variant={r.TaxType === 'Withholding' ? 'warning' : r.TaxType === 'SalesTax' ? 'info' : 'neutral'}>{r.TaxType || '—'}</Badge></td>
                    <td>{r.RatePercent != null ? `${r.RatePercent}%` : '—'}</td>
                    <td>{r.IsActive ? <Badge variant="success">Active</Badge> : <Badge variant="neutral">Inactive</Badge>}</td>
                    <td className="no-print">
                      <div className="flex gap-2 text-sm">
                        <Can perm="finance.coa"><button className="text-brand-600 hover:underline" onClick={() => openEdit(r)}>Edit</button></Can>
                        <Can perm="finance.coa"><button className="text-amber-600 hover:underline" onClick={() => setStatusTarget(r)}>
                          {r.IsActive ? 'Deactivate' : 'Activate'}
                        </button></Can>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <Modal open={addOpen} onClose={() => setAddOpen(false)} title={editing ? `Edit tax head ${editing.Code}` : 'Add tax head'} size="sm">
        <form onSubmit={save} className="space-y-3">
          <div><label className="label">Code *</label>
            <input className="input font-mono" value={form.Code} disabled={!!editing}
              onChange={(e) => setForm({ ...form, Code: e.target.value })} placeholder="e.g. WHT-153" />
          </div>
          <div><label className="label">Name *</label>
            <input className="input" value={form.Name} onChange={(e) => setForm({ ...form, Name: e.target.value })} />
          </div>
          <div><label className="label">Description</label>
            <textarea className="input" rows="2" value={form.Description} onChange={(e) => setForm({ ...form, Description: e.target.value })} />
          </div>
          <div className="grid grid-cols-2 gap-3">
            <div><label className="label">Rate % (if applicable)</label>
              <input type="number" min="0" max="100" step="0.01" className="input no-spinner" value={form.RatePercent}
                onChange={(e) => setForm({ ...form, RatePercent: e.target.value })} />
            </div>
            <div><label className="label">Tax Type</label>
              <select className="input" value={form.TaxType} onChange={(e) => setForm({ ...form, TaxType: e.target.value })}>
                <option value="">—</option>
                {TAX_TYPES.map((t) => <option key={t} value={t}>{t === 'SalesTax' ? 'Sales Tax' : t}</option>)}
              </select>
            </div>
          </div>
          <div className="flex justify-end gap-2 pt-2">
            <Button type="button" variant="secondary" onClick={() => setAddOpen(false)}>Cancel</Button>
            <Button type="submit" disabled={saving}>{saving ? 'Saving…' : 'Save'}</Button>
          </div>
        </form>
      </Modal>

      <ConfirmDialog
        open={!!statusTarget}
        onClose={() => setStatusTarget(null)}
        onConfirm={doToggleStatus}
        title={statusTarget?.IsActive ? 'Deactivate tax head' : 'Activate tax head'}
        message={`${statusTarget?.IsActive ? 'Deactivate' : 'Activate'} ${statusTarget?.Name}? ${statusTarget?.IsActive ? 'It will no longer be selectable on new voucher lines.' : ''}`}
        confirmLabel={statusTarget?.IsActive ? 'Deactivate' : 'Activate'}
      />
    </div>
  );
}
