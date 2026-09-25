import { useEffect, useState } from 'react';
import api from '../../../services/api';
import { useToast } from '../../../context/ToastContext';
import { useAuth } from '../../../context/AuthContext';
import Modal from '../../../components/common/Modal';
import Button from '../../../components/common/Button';
import AccountTreePicker from './AccountTreePicker';

const emptyLine = () => ({ AccountID: '', AccountLabel: '', Debit: '', Credit: '', Description: '' });

/**
 * Journal Voucher / Opening Trial Balance entry.
 * The user explicitly enters Debit and Credit per line; the voucher must be
 * balanced before it can be saved (enforced here AND in the backend).
 */
export default function JournalVoucherForm({ open, onClose, onSaved, meta, editing }) {
  const toast = useToast();
  const { user } = useAuth();
  const isSuperAdmin = user?.isSuperAdmin === true;
  const isEdit = !!editing;

  const [date, setDate] = useState('');
  const [narrative, setNarrative] = useState('');
  const [branchId, setBranchId] = useState('');
  const [branches, setBranches] = useState([]);
  const [lines, setLines] = useState([emptyLine(), emptyLine()]);
  const [pickerRow, setPickerRow] = useState(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) return;
    if (isSuperAdmin) api.get('/branches').then((r) => setBranches(r.data.data || [])).catch(() => {});
  }, [open, isSuperAdmin]);

  useEffect(() => {
    if (!open) return;
    if (editing) {
      const h = editing.header;
      setDate(String(h.VoucherDate).slice(0, 10));
      setNarrative(h.Narrative || '');
      setBranchId(h.BranchID || '');
      setLines((editing.lines || []).map((l) => ({
        AccountID: l.AccountID, AccountLabel: `${l.AccountCode} · ${l.AccountTitle}`,
        Debit: Number(l.Debit) > 0 ? Number(l.Debit) : '', Credit: Number(l.Credit) > 0 ? Number(l.Credit) : '',
        Description: l.Description || '',
      })));
    } else {
      setDate(new Date().toISOString().slice(0, 10));
      setNarrative('');
      setBranchId(user?.branchId || '');
      setLines([emptyLine(), emptyLine()]);
    }
  }, [open, editing, user]);

  const setLine = (i, patch) => setLines((ls) => ls.map((l, idx) => (idx === i ? { ...l, ...patch } : l)));

  const totalDr = lines.reduce((s, l) => s + (Number(l.Debit) || 0), 0);
  const totalCr = lines.reduce((s, l) => s + (Number(l.Credit) || 0), 0);
  const diff = Number((totalDr - totalCr).toFixed(2));
  const balanced = totalDr > 0 && diff === 0;
  const linesValid = lines.every((l) => l.AccountID && (Number(l.Debit) > 0 || Number(l.Credit) > 0));
  const canSave = date && balanced && linesValid;

  const submit = async () => {
    if (!canSave) {
      if (!balanced) return toast.error(`The ${meta.short} is not balanced — Debit and Credit totals must be equal and greater than zero.`);
      return toast.error('Every line needs an account and exactly one of Debit or Credit.');
    }
    setSaving(true);
    try {
      const payload = {
        Family: meta.family,
        VoucherDate: date,
        Narrative: narrative || null,
        Lines: lines.map((l) => ({
          AccountID: Number(l.AccountID),
          Debit: Number(l.Debit) || 0,
          Credit: Number(l.Credit) || 0,
          Description: l.Description || null,
        })),
      };
      if (isSuperAdmin && branchId) payload.BranchID = Number(branchId);
      if (isEdit) await api.put(`/finance/${meta.path}/${editing.header.ID}`, payload);
      else await api.post(`/finance/${meta.path}`, payload);
      toast.success(isEdit ? 'Voucher updated and re-posted' : 'Voucher saved and posted');
      onSaved();
    } catch (err) {
      toast.error(err.response?.data?.error?.message || 'Save failed');
    } finally { setSaving(false); }
  };

  return (
    <Modal open={open} onClose={onClose} title={`${isEdit ? 'Edit' : 'New'} ${meta.title}`} size="xl">
      <div className="space-y-4">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
          <div>
            <label className="label">Voucher Type</label>
            <div className="input bg-slate-100 dark:bg-slate-800 font-medium">{meta.title}</div>
          </div>
          <div>
            <label className="label">Date *</label>
            <input type="date" className="input" value={date} disabled={isEdit} onChange={(e) => setDate(e.target.value)} />
            {isEdit && <p className="text-[11px] text-slate-400 mt-1">Locked after saving.</p>}
          </div>
          {isSuperAdmin && (
            <div>
              <label className="label">Branch</label>
              <select className="input" value={branchId} onChange={(e) => setBranchId(e.target.value)}>
                <option value="">My branch</option>
                {branches.map((b) => <option key={b.BranchID} value={b.BranchID}>{b.Name}</option>)}
              </select>
            </div>
          )}
          <div className={isSuperAdmin ? '' : 'md:col-span-2'}>
            <label className="label">Voucher Description</label>
            <input className="input" value={narrative} onChange={(e) => setNarrative(e.target.value)} />
          </div>
        </div>

        <div className="table-wrap">
          <table className="table text-sm">
            <thead>
              <tr>
                <th style={{ width: '34%' }}>Account</th>
                <th style={{ width: '15%' }}>Debit</th>
                <th style={{ width: '15%' }}>Credit</th>
                <th>Description</th>
                <th style={{ width: 36 }}></th>
              </tr>
            </thead>
            <tbody>
              {lines.map((l, i) => (
                <tr key={i}>
                  <td>
                    <button type="button" className={`input text-left text-sm truncate ${l.AccountID ? '' : 'text-slate-400'}`}
                      onClick={() => setPickerRow(i)}>
                      {l.AccountID ? l.AccountLabel : 'Choose account…'}
                    </button>
                  </td>
                  <td>
                    <input type="number" min="0" step="0.01" className="input no-spinner" value={l.Debit}
                      onChange={(e) => setLine(i, { Debit: e.target.value, Credit: e.target.value !== '' ? '' : l.Credit })} />
                  </td>
                  <td>
                    <input type="number" min="0" step="0.01" className="input no-spinner" value={l.Credit}
                      onChange={(e) => setLine(i, { Credit: e.target.value, Debit: e.target.value !== '' ? '' : l.Debit })} />
                  </td>
                  <td><input className="input" value={l.Description} onChange={(e) => setLine(i, { Description: e.target.value })} /></td>
                  <td>
                    {lines.length > 2 && (
                      <button type="button" className="text-red-500 hover:text-red-700 font-bold"
                        onClick={() => setLines((ls) => ls.filter((_, idx) => idx !== i))}>×</button>
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
            <tfoot>
              <tr className="font-semibold border-t-2 border-slate-300">
                <td>Totals</td>
                <td className="text-right pr-2 text-emerald-700">{totalDr.toFixed(2)}</td>
                <td className="text-right pr-2 text-red-700">{totalCr.toFixed(2)}</td>
                <td colSpan={2}>
                  Difference: <span className={balanced ? 'text-emerald-700 font-bold' : 'text-red-600 font-bold'}>{diff.toFixed(2)}</span>
                </td>
              </tr>
            </tfoot>
          </table>
        </div>

        <div className="flex items-center justify-between">
          <button type="button" className="btn-secondary text-sm px-3 py-1.5"
            onClick={() => setLines((ls) => [...ls, emptyLine()])}>+ Add Line</button>
          {!balanced && (
            <div className="text-xs text-red-600 font-medium">
              {totalDr <= 0
                ? 'The journal voucher is not balanced — debit and credit totals must be greater than zero.'
                : `The journal voucher is not balanced — difference of ${diff.toFixed(2)} must be zero before saving.`}
            </div>
          )}
        </div>

        <div className="flex justify-end gap-2 pt-2 border-t border-slate-200 dark:border-slate-800">
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button onClick={submit} disabled={saving || !canSave}
            title={!balanced ? 'The journal voucher must be balanced before saving' : ''}>
            {saving ? 'Saving…' : 'Save Voucher'}
          </Button>
        </div>
      </div>

      <AccountTreePicker
        open={pickerRow !== null}
        onClose={() => setPickerRow(null)}
        onSelect={(acc) => {
          setPickerRow(null);
          if (acc) setLine(pickerRow, { AccountID: acc.AccountID, AccountLabel: `${acc.Code} · ${acc.Title}` });
        }}
        title="Select Detail Account"
      />
    </Modal>
  );
}
