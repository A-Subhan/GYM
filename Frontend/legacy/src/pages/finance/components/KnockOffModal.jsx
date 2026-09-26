import { useEffect, useState } from 'react';
import api from '../../../services/api';
import { useToast } from '../../../context/ToastContext';
import { formatCurrency, formatDate } from '../../../utils/format';
import Modal from '../../../components/common/Modal';
import Button from '../../../components/common/Button';
import Spinner from '../../../components/common/Spinner';

/**
 * Bill-wise Knock Off allocation interface.
 * Shows the party's outstanding bills; the user distributes the voucher
 * line amount across bills (partial + multi-bill supported). Saved
 * transactionally via the allocations endpoint.
 */
export default function KnockOffModal({ open, onClose, meta, documentId, line, onSaved }) {
  const toast = useToast();
  const [bills, setBills] = useState([]);
  const [existing, setExisting] = useState({});
  const [loading, setLoading] = useState(false);
  const [alloc, setAlloc] = useState({});
  const [saving, setSaving] = useState(false);

  const partyId = line?.PartyMemberID || line?.PartySupplierID || null;

  useEffect(() => {
    if (!open || !partyId) return;
    setLoading(true);
    const agingUrl = meta.partyKind === 'member' ? '/finance/aging/customer' : '/finance/aging/vendor';
    const partyParam = meta.partyKind === 'member' ? 'memberId' : 'supplierId';
    Promise.all([
      api.get(agingUrl, { params: { asOf: new Date().toISOString().slice(0, 10), [partyParam]: partyId } }),
      api.get(`/finance/${meta.path}/${documentId}/allocations`).catch(() => null),
    ]).then(([aging, allocs]) => {
      setBills(aging.data.data || []);
      const map = {};
      for (const a of allocs?.data?.data || []) {
        if (String(a.LineID) === String(line.LineID) && !a.IsReversed) {
          map[a.BillRef] = Number(a.Amount);
        }
      }
      setExisting(map);
      setAlloc({ ...map });
    }).catch(() => toast.error('Failed to load outstanding bills'))
      .finally(() => setLoading(false));
  }, [open, partyId, meta, documentId, line?.LineID]);

  const lineAmount = Number(line?.Amount || 0);
  const alreadyAllocated = Object.values(existing).reduce((s, v) => s + Number(v || 0), 0);
  const available = lineAmount - alreadyAllocated;
  const allocated = Object.values(alloc).reduce((s, v) => s + Number(v || 0), 0);
  const remaining = available - allocated;

  const setAllocAmount = (ref, value, outstanding) => {
    const v = value === '' ? '' : Math.min(Number(value), outstanding);
    setAlloc((a) => ({ ...a, [ref]: v === '' ? '' : Number(v) }));
  };

  const save = async () => {
    const rows = Object.entries(alloc)
      .filter(([, v]) => Number(v) > 0)
      .map(([ref, v]) => ({ billRef: ref, amount: Number(v) }));
    if (!rows.length) return toast.error('Enter at least one allocation');
    if (allocated > available) return toast.error('Allocation exceeds the available voucher line amount');
    setSaving(true);
    try {
      await api.put(`/finance/${meta.path}/${documentId}/lines/${line.LineID}/allocations`, { Allocations: rows });
      toast.success('Knock Off allocations saved');
      onSaved();
      onClose();
    } catch (err) {
      toast.error(err.response?.data?.error?.message || 'Failed to save allocations');
    } finally { setSaving(false); }
  };

  return (
    <Modal open={open} onClose={onClose} title="Knock Off — allocate against outstanding bills" size="lg">
      {loading ? <Spinner /> : (
        <div className="space-y-3">
          <div className="grid grid-cols-3 gap-3 text-sm">
            <div className="card p-2 text-center"><div className="text-xs text-slate-400">Line Amount</div><div className="font-bold">{formatCurrency(lineAmount)}</div></div>
            <div className="card p-2 text-center"><div className="text-xs text-slate-400">Available</div><div className="font-bold">{formatCurrency(available)}</div></div>
            <div className="card p-2 text-center"><div className="text-xs text-slate-400">Allocated / Remaining</div>
              <div className={`font-bold ${remaining < 0 ? 'text-red-600' : 'text-emerald-600'}`}>{formatCurrency(allocated)} / {formatCurrency(remaining)}</div></div>
          </div>

          {bills.length === 0 && <div className="text-center text-slate-400 py-6 text-sm">No outstanding bills for this party.</div>}

          <div className="table-wrap max-h-72 overflow-y-auto">
            <table className="table text-sm">
              <thead><tr><th>Bill Ref</th><th>Bill Date</th><th>Due Date</th><th className="text-right">Outstanding</th><th style={{ width: 140 }}>Allocate</th></tr></thead>
              <tbody>
                {bills.map((b) => {
                  const prev = existing[b.BillRef] || 0;
                  const outstanding = Number(b.RemainingAmount) + prev; // restore prior allocation of this line for editing
                  return (
                    <tr key={b.BillRef}>
                      <td className="font-mono text-xs">{b.BillRef}</td>
                      <td>{formatDate(b.BillDate)}</td>
                      <td>{formatDate(b.DueDate)}</td>
                      <td className="text-right">{formatCurrency(outstanding)}</td>
                      <td>
                        <input type="number" min="0" max={outstanding} step="0.01" className="input no-spinner"
                          value={alloc[b.BillRef] ?? ''}
                          onChange={(e) => setAllocAmount(b.BillRef, e.target.value, outstanding)} />
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>

          <div className="flex justify-end gap-2">
            <Button variant="secondary" onClick={onClose}>Cancel</Button>
            <Button onClick={save} disabled={saving}>Save Allocations</Button>
          </div>
        </div>
      )}
    </Modal>
  );
}
