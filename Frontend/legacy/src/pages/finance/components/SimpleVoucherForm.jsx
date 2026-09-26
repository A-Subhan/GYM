import { useEffect, useState } from 'react';
import api from '../../../services/api';
import { useToast } from '../../../context/ToastContext';
import { useAuth } from '../../../context/AuthContext';
import Modal from '../../../components/common/Modal';
import Button from '../../../components/common/Button';
import AccountSelector from './AccountSelector';
import AccountTreePicker from './AccountTreePicker';
import KnockOffModal from './KnockOffModal';

const CHEQUE_STATUSES = ['Hold', 'Pending', 'Cleared', 'Bounced', 'Cancelled'];
const emptyLine = () => ({
  AccountID: '', AccountLabel: '', AccountKnockOff: false, Description: '', Amount: '',
  TaxAccountID: '', TaxPercent: '', TaxAmount: '',
  ChequeNo: '', ChequeStatus: '', ChequeTitle: '', ReferenceNo: '',
  KnockOff: false, BillRef: '', BillDate: '', DueDate: '',
  PartyMemberID: '', PartySupplierID: '', PartyStaffID: '', LineID: null,
});

/**
 * Cash / Bank voucher entry (CRV / CPV / BRV / BPV).
 * The user enters amounts only — Dr/Cr sides are derived from the voucher
 * type in the backend. Lines carry Tax, Cheque, Reference and Knock Off.
 */
export default function SimpleVoucherForm({ open, onClose, onSaved, meta, editing }) {
  const toast = useToast();
  const { user } = useAuth();
  const isSuperAdmin = user?.isSuperAdmin === true;
  const isEdit = !!editing;
  const posted = isEdit && editing.header.Status === 'Posted';

  const [date, setDate] = useState('');
  const [moneyAccountId, setMoneyAccountId] = useState('');
  const [narrative, setNarrative] = useState('');
  const [branchId, setBranchId] = useState('');
  const [status, setStatus] = useState('Posted');
  const [branches, setBranches] = useState([]);
  const [taxHeads, setTaxHeads] = useState([]);
  const [lines, setLines] = useState([emptyLine()]);
  const [pickerRow, setPickerRow] = useState(null);
  const [pickerForHeader, setPickerForHeader] = useState(false);
  const [knockOffLine, setKnockOffLine] = useState(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!open) return;
    api.get('/finance/tax-heads').then((r) => setTaxHeads(r.data.data || [])).catch(() => {});
    if (isSuperAdmin) api.get('/branches').then((r) => setBranches(r.data.data || [])).catch(() => {});
  }, [open, isSuperAdmin]);

  useEffect(() => {
    if (!open) return;
    if (editing) {
      const h = editing.header;
      setDate(String(h.VoucherDate).slice(0, 10));
      setMoneyAccountId(h.MoneyAccountID);
      setNarrative(h.Narrative || '');
      setBranchId(h.BranchID || '');
      setStatus(h.Status);
      setLines((editing.lines || []).map((l) => ({
        LineID: l.LineID, AccountID: l.AccountID,
        AccountLabel: `${l.AccountCode} · ${l.AccountTitle}`, AccountKnockOff: false,
        Description: l.Description || '', Amount: Number(l.Amount),
        TaxAccountID: l.TaxAccountID || '', TaxPercent: l.TaxPercent ?? '',
        TaxAmount: l.TaxAmount ?? '',
        ChequeNo: l.ChequeNo || '', ChequeStatus: l.ChequeStatus || '', ChequeTitle: l.ChequeTitle || '',
        ReferenceNo: l.ReferenceNo || '',
        KnockOff: !!l.KnockOff, BillRef: l.BillRef || '',
        BillDate: l.BillDate ? String(l.BillDate).slice(0, 10) : '',
        DueDate: l.DueDate ? String(l.DueDate).slice(0, 10) : '',
        PartyMemberID: l.PartyMemberID || '', PartySupplierID: l.PartySupplierID || '',
        PartyStaffID: l.PartyStaffID || '',
      })));
    } else {
      setDate(new Date().toISOString().slice(0, 10));
      setMoneyAccountId('');
      setNarrative('');
      setBranchId(user?.branchId || '');
      setStatus('Posted');
      setLines([emptyLine()]);
    }
  }, [open, editing, user]);

  const setLine = (i, patch) => setLines((ls) => ls.map((l, idx) => (idx === i ? { ...l, ...patch } : l)));

  const recalcTax = (i, patch) => {
    const amount = Number(patch.Amount ?? lines[i].Amount) || 0;
    const pct = Number(patch.TaxPercent ?? lines[i].TaxPercent) || 0;
    const next = { ...patch };
    if (patch.TaxPercent !== undefined || patch.Amount !== undefined) {
      next.TaxAmount = pct > 0 ? Number((amount * pct / 100).toFixed(2)) : '';
    }
    setLine(i, next);
  };

  const total = lines.reduce((s, l) => s + (Number(l.Amount) || 0), 0);
  const canSave = date && moneyAccountId && lines.length > 0
    && lines.every((l) => l.AccountID && Number(l.Amount) > 0
      && ((Number(l.TaxPercent) > 0 || Number(l.TaxAmount) > 0) ? l.TaxAccountID : true));

  const buildPayload = () => ({
    Family: meta.family,
    Direction: meta.direction,
    VoucherDate: date,
    MoneyAccountID: Number(moneyAccountId),
    Narrative: narrative || null,
    Lines: lines
      .filter((l) => l.AccountID && Number(l.Amount) > 0)
      .map((l) => ({
        AccountID: Number(l.AccountID),
        Description: l.Description || null,
        Amount: Number(l.Amount),
        TaxHeadID: l.TaxHeadID ? Number(l.TaxHeadID) : null,
        TaxAccountID: l.TaxAccountID ? Number(l.TaxAccountID) : null,
        TaxPercent: l.TaxPercent !== '' && l.TaxPercent !== null ? Number(l.TaxPercent) : null,
        TaxAmount: l.TaxAmount !== '' && l.TaxAmount !== null ? Number(l.TaxAmount) : null,
        ChequeNo: l.ChequeNo || null,
        ChequeStatus: l.ChequeStatus || null,
        ChequeTitle: l.ChequeTitle || null,
        ReferenceNo: l.ReferenceNo || null,
        KnockOff: !!l.KnockOff,
        BillRef: l.KnockOff ? (l.BillRef || null) : null,
        BillDate: l.KnockOff && l.BillDate ? l.BillDate : null,
        DueDate: l.KnockOff && l.DueDate ? l.DueDate : null,
        PartyMemberID: l.KnockOff && l.PartyMemberID ? Number(l.PartyMemberID) : null,
        PartySupplierID: l.KnockOff && l.PartySupplierID ? Number(l.PartySupplierID) : null,
        PartyStaffID: l.KnockOff && l.PartyStaffID ? Number(l.PartyStaffID) : null,
      })),
  });

  const save = async () => {
    if (!canSave) return toast.error('Complete the header and every line (account + amount) first.');
    setSaving(true);
    try {
      const payload = buildPayload();
      payload.Status = status;
      if (isSuperAdmin && branchId) payload.BranchID = Number(branchId);
      if (isEdit) await api.put(`/finance/${meta.path}/${editing.header.ID}`, payload);
      else await api.post(`/finance/${meta.path}`, payload);
      toast.success(isEdit ? 'Voucher saved' : 'Voucher saved and posted');
      onSaved();
    } catch (err) {
      toast.error(err.response?.data?.error?.message || 'Save failed');
    } finally { setSaving(false); }
  };

  const trashIcon = (
    <svg className="w-4 h-4" fill="none" stroke="currentColor" strokeWidth="1.8" viewBox="0 0 24 24">
      <path strokeLinecap="round" strokeLinejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
    </svg>
  );

  return (
    <Modal open={open} onClose={onClose} title={`${isEdit ? 'Edit' : 'New'} ${meta.title}`} size="xl">
      <div className="space-y-4">
        {/* header */}
        <div className="grid grid-cols-1 md:grid-cols-4 gap-3">
          <div>
            <label className="label">Voucher Number</label>
            <input className="input font-mono bg-slate-100 dark:bg-slate-800"
              value={isEdit ? (editing.header.VoucherNo || '—') : 'Auto-generated'} disabled />
          </div>
          <div>
            <label className="label">Date *</label>
            <input type="date" className="input" value={date}
              disabled={isEdit}
              onChange={(e) => setDate(e.target.value)} />
            {isEdit && <p className="text-[11px] text-slate-400 mt-1">Locked after saving.</p>}
          </div>
          <div>
            <label className="label">Branch</label>
            {isEdit ? (
              <input className="input bg-slate-100 dark:bg-slate-800" disabled
                value={editing.header.BranchName || branchId} />
            ) : isSuperAdmin ? (
              <select className="input" value={branchId} onChange={(e) => setBranchId(e.target.value)}>
                <option value="">My branch</option>
                {branches.map((b) => <option key={b.BranchID} value={b.BranchID}>{b.Name}</option>)}
              </select>
            ) : (
              <input className="input bg-slate-100 dark:bg-slate-800" disabled value="My branch" />
            )}
          </div>
          <div>
            <label className="label">Voucher Status</label>
            {posted ? (
              <input className="input bg-slate-100 dark:bg-slate-800 font-medium" value="Posted" disabled />
            ) : (
              <select className="input" value={status} onChange={(e) => setStatus(e.target.value)}>
                <option value="Posted">Posted</option>
                <option value="Draft">Draft</option>
                <option value="Hold">Hold</option>
              </select>
            )}
          </div>
          <div className="md:col-span-2">
            <label className="label">{meta.moneyLabel} *</label>
            <div className="flex gap-1">
              <AccountSelector bookType={meta.bookType} value={moneyAccountId} onChange={setMoneyAccountId} disabled={posted} />
              <button type="button" className="btn-secondary text-xs px-2 flex-shrink-0" disabled={posted}
                onClick={() => setPickerForHeader(true)}>Browse</button>
            </div>
          </div>
          <div className="md:col-span-2">
            <label className="label">Description</label>
            <input className="input" maxLength={200} value={narrative}
              onChange={(e) => setNarrative(e.target.value)} />
          </div>
        </div>

        {/* lines */}
        <div className="table-wrap">
          <table className="table text-sm">
            <thead>
              <tr>
                <th style={{ width: 36 }}></th>
                <th style={{ width: '22%' }}>Account</th>
                <th>Description</th>
                <th style={{ width: '11%' }}>Amount</th>
                <th style={{ width: '15%' }}>Tax Account</th>
                <th style={{ width: 80 }}>Tax %</th>
                <th style={{ width: 100 }}>Tax Amount</th>
                <th style={{ width: 110 }}>Cheque No</th>
                <th style={{ width: 100 }}>Cheque Status</th>
                <th style={{ width: 110 }}>Cheque Title</th>
                <th style={{ width: 100 }}>Reference No</th>
                <th style={{ width: 70 }}>Knock Off</th>
              </tr>
            </thead>
            <tbody>
              {lines.map((l, i) => (
                <tr key={i}>
                  <td>
                    {lines.length > 1 && (
                      <button type="button" className="text-red-500 hover:text-red-700" title="Delete line"
                        onClick={() => setLines((ls) => ls.filter((_, idx) => idx !== i))}>
                        {trashIcon}
                      </button>
                    )}
                  </td>
                  <td>
                    <button type="button" className={`input text-left text-sm truncate ${l.AccountID ? '' : 'text-slate-400'}`}
                      onClick={() => setPickerRow(i)}>
                      {l.AccountID ? l.AccountLabel : 'Choose account…'}
                    </button>
                  </td>
                  <td><input className="input" value={l.Description} onChange={(e) => setLine(i, { Description: e.target.value })} /></td>
                  <td><input type="number" min="0" step="0.01" className="input no-spinner" value={l.Amount}
                    onChange={(e) => recalcTax(i, { Amount: e.target.value })} /></td>
                  <td>
                    <select className="input" value={l.TaxAccountID} onChange={(e) => setLine(i, { TaxAccountID: e.target.value })}>
                      <option value="">— none —</option>
                      {taxHeads.map((t) => <option key={t.TaxHeadID} value={t.TaxHeadID}>{t.Code}{t.RatePercent ? ` (${t.RatePercent}%)` : ''}</option>)}
                    </select>
                  </td>
                  <td><input type="number" min="0" max="100" step="0.01" className="input no-spinner" value={l.TaxPercent}
                    onChange={(e) => recalcTax(i, { TaxPercent: e.target.value })} /></td>
                  <td><input type="number" min="0" step="0.01" className="input no-spinner" value={l.TaxAmount}
                    onChange={(e) => setLine(i, { TaxAmount: e.target.value })} /></td>
                  <td><input className="input" value={l.ChequeNo} onChange={(e) => setLine(i, { ChequeNo: e.target.value })} /></td>
                  <td>
                    <select className="input" value={l.ChequeStatus} onChange={(e) => setLine(i, { ChequeStatus: e.target.value })}>
                      <option value="">—</option>
                      {CHEQUE_STATUSES.map((c) => <option key={c} value={c}>{c}</option>)}
                    </select>
                  </td>
                  <td><input className="input" value={l.ChequeTitle} onChange={(e) => setLine(i, { ChequeTitle: e.target.value })} /></td>
                  <td><input className="input" value={l.ReferenceNo} onChange={(e) => setLine(i, { ReferenceNo: e.target.value })} /></td>
                  <td>
                    <button type="button" className="text-xs text-brand-600 hover:underline disabled:opacity-40"
                      disabled={!isEdit}
                      title={isEdit ? 'Allocate against outstanding bills' : 'Save the voucher first, then allocate'}
                      onClick={() => setKnockOffLine(l)}>
                      Knock Off
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
            <tfoot>
              <tr className="font-semibold border-t-2 border-slate-300">
                <td colSpan={3}>Total</td>
                <td className="text-right pr-2">{total.toFixed(2)}</td>
                <td colSpan={8}>
                  <span className="text-xs text-slate-400 font-normal">
                    {meta.direction === 'Receipt'
                      ? `Dr ${meta.moneyLabel} ${total.toFixed(2)} / Cr lines ${total.toFixed(2)}`
                      : `Dr lines ${total.toFixed(2)} / Cr ${meta.moneyLabel} ${total.toFixed(2)}`}
                  </span>
                </td>
              </tr>
            </tfoot>
          </table>
        </div>

        <div className="flex items-center justify-between">
          <button type="button" className="btn-secondary text-sm px-3 py-1.5"
            onClick={() => setLines((ls) => [...ls, emptyLine()])}>+ Add Line</button>
          <div className="text-xs text-slate-400">Dr/Cr sides are generated automatically from the voucher type.</div>
        </div>

        <div className="flex justify-end gap-2 pt-2 border-t border-slate-200 dark:border-slate-800">
          <Button variant="secondary" onClick={onClose}>Cancel</Button>
          <Button onClick={save} disabled={saving || !canSave}>{saving ? 'Saving…' : 'Save Voucher'}</Button>
        </div>
      </div>

      <AccountTreePicker
        open={pickerForHeader}
        onClose={() => setPickerForHeader(false)}
        onSelect={(acc) => { setPickerForHeader(false); if (acc) setMoneyAccountId(acc.AccountID); }}
        restrictBookType={meta.bookType}
        title={`Select ${meta.moneyLabel} (${meta.bookType})`}
      />
      <AccountTreePicker
        open={pickerRow !== null}
        onClose={() => setPickerRow(null)}
        onSelect={(acc) => {
          setPickerRow(null);
          if (acc) setLine(pickerRow, {
            AccountID: acc.AccountID, AccountLabel: `${acc.Code} · ${acc.Title}`, AccountKnockOff: acc.KnockOff === 1,
          });
        }}
        title="Select Detail Account"
      />
      {knockOffLine && (
        <KnockOffModal
          open onClose={() => setKnockOffLine(null)}
          meta={meta} documentId={editing.header.ID} line={knockOffLine}
          onSaved={() => {
            api.get(`/finance/${meta.path}/${editing.header.ID}`).then((res) => {
              setEditing((prev) => ({ ...prev, lines: res.data.data.lines }));
              setLines((ls) => ls.map((l) => {
                const fresh = res.data.data.lines.find((fl) => fl.LineID === l.LineID);
                return fresh ? { ...l, KnockOff: !!fresh.KnockOff, BillRef: fresh.BillRef || '' } : l;
              }));
            }).catch(() => {});
          }}
        />
      )}
    </Modal>
  );
}
