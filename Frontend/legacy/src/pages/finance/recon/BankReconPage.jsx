import { useCallback, useEffect, useState } from 'react';
import api from '../../../services/api';
import { useToast } from '../../../context/ToastContext';
import { formatCurrency, formatDate, formatDateTime } from '../../../utils/format';
import PageHeader from '../../../components/common/PageHeader';
import Button from '../../../components/common/Button';
import Modal from '../../../components/common/Modal';
import Badge from '../../../components/common/Badge';
import Spinner from '../../../components/common/Spinner';
import ConfirmDialog from '../../../components/common/ConfirmDialog';

/** Bank reconciliation layer — marks system entries as reconciled without ever altering the ledger. */
export default function BankReconPage() {
  const toast = useToast();
  const [banks, setBanks] = useState([]);
  const [runs, setRuns] = useState([]);
  const [loading, setLoading] = useState(true);

  const [createOpen, setCreateOpen] = useState(false);
  const [form, setForm] = useState({ AccountID: '', StatementDate: '', StatementOpeningBalance: '', StatementClosingBalance: '', Notes: '' });
  const [detail, setDetail] = useState(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [bankRes, runRes] = await Promise.all([
        api.get('/finance/coa/selectors', { params: { tag: 'Bank', limit: 500 } }),
        api.get('/finance/recon/runs'),
      ]);
      setBanks(bankRes.data.data || []);
      setRuns(runRes.data.data || []);
    } catch (err) { toast.error('Failed to load reconciliations'); }
    finally { setLoading(false); }
  }, [toast]);

  useEffect(() => { load(); }, [load]);

  const openDetail = async (run) => {
    setDetail(null);
    setDetailLoading(true);
    try {
      const res = await api.get(`/finance/recon/runs/${run.ReconID}`);
      setDetail(res.data.data);
    } catch (err) { toast.error('Failed to load run'); }
    finally { setDetailLoading(false); }
  };

  const createRun = async (e) => {
    e.preventDefault();
    try {
      const res = await api.post('/finance/recon/runs', {
        AccountID: Number(form.AccountID),
        StatementDate: form.StatementDate,
        StatementOpeningBalance: Number(form.StatementOpeningBalance || 0),
        StatementClosingBalance: Number(form.StatementClosingBalance || 0),
        Notes: form.Notes || null,
      });
      toast.success(`Run created — ${res.data.data?.SnapshotCount ?? 0} system entries snapshotted`);
      setCreateOpen(false);
      setForm({ AccountID: '', StatementDate: '', StatementOpeningBalance: '', StatementClosingBalance: '', Notes: '' });
      load();
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Failed to create run'); }
  };

  const toggleLine = async (line, value) => {
    try {
      await api.patch(`/finance/recon/lines/${line.LineID}`, { IsReconciled: value });
      setDetail((d) => ({
        ...d,
        lines: d.lines.map((l) => (l.LineID === line.LineID ? { ...l, IsReconciled: value } : l)),
      }));
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Failed'); }
  };

  const completeRun = async () => {
    try {
      await api.post(`/finance/recon/runs/${detail.run.ReconID}/complete`);
      toast.success('Reconciliation completed');
      openDetail({ ReconID: detail.run.ReconID });
      load();
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Failed'); }
  };

  const doDelete = async () => {
    if (!deleteTarget) return;
    try {
      await api.delete(`/finance/recon/runs/${deleteTarget.ReconID}`);
      toast.success('Run discarded');
      setDeleteTarget(null);
      setDetail(null);
      load();
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Failed'); setDeleteTarget(null); }
  };

  const matched = (detail?.lines || []).filter((l) => l.IsReconciled).length;
  const clearedTotal = (detail?.lines || []).filter((l) => l.IsReconciled).reduce((s, l) => s + Number(l.Debit) - Number(l.Credit), 0);

  return (
    <div className="space-y-4">
      <PageHeader
        title="Bank Reconciliation"
        subtitle="Match the bank statement against posted bank transactions. The accounting ledger is never modified."
        actions={<Button onClick={() => setCreateOpen(true)}>+ New Reconciliation</Button>}
      />

      <div className="card overflow-hidden">
        {loading ? <div className="p-8"><Spinner /></div> : (
          <div className="table-wrap">
            <table className="table">
              <thead><tr><th>Bank Account</th><th>Statement Date</th><th>Statement Closing</th><th>System Closing</th><th>Matched</th><th>Status</th><th className="no-print">Actions</th></tr></thead>
              <tbody>
                {runs.length === 0 && <tr><td colSpan={7} className="text-center text-slate-400 py-8">No reconciliation runs yet</td></tr>}
                {runs.map((r) => (
                  <tr key={r.ReconID}>
                    <td className="font-medium">{r.AccountCode} · {r.AccountTitle}</td>
                    <td>{formatDate(r.StatementDate)}</td>
                    <td>{formatCurrency(r.StatementClosingBalance)}</td>
                    <td>{formatCurrency(r.SystemClosingBalance)}</td>
                    <td>{r.MatchedLines} / {r.TotalLines}</td>
                    <td><Badge variant={r.Status === 'Completed' ? 'success' : 'warning'}>{r.Status}</Badge></td>
                    <td className="no-print">
                      <div className="flex gap-2 text-sm">
                        <button className="text-brand-600 hover:underline" onClick={() => openDetail(r)}>Open</button>
                        {r.Status === 'Open' && <button className="text-red-500 hover:underline" onClick={() => setDeleteTarget(r)}>Discard</button>}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* run detail */}
      <Modal open={!!detail || detailLoading} onClose={() => setDetail(null)} title="Bank reconciliation" size="xl">
        {detailLoading || !detail ? <Spinner /> : (
          <div className="space-y-3">
            <div className="grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
              <div><div className="text-xs text-slate-400 uppercase">Account</div><div className="font-medium">{detail.run.AccountCode} · {detail.run.AccountTitle}</div></div>
              <div><div className="text-xs text-slate-400 uppercase">Statement date</div><div>{formatDate(detail.run.StatementDate)}</div></div>
              <div><div className="text-xs text-slate-400 uppercase">Statement closing</div><div className="font-medium">{formatCurrency(detail.run.StatementClosingBalance)}</div></div>
              <div><div className="text-xs text-slate-400 uppercase">System closing</div><div className="font-medium">{formatCurrency(detail.run.SystemClosingBalance)}</div></div>
            </div>
            <div className="text-sm text-slate-500">
              Matched {matched} / {detail.lines.length} entries · cleared net movement {formatCurrency(clearedTotal)} · Status: {detail.run.Status}
            </div>
            <div className="table-wrap max-h-96 overflow-y-auto">
              <table className="table text-sm">
                <thead><tr><th>Date</th><th>Voucher</th><th>Description</th><th>Debit</th><th>Credit</th><th>Reconciled</th></tr></thead>
                <tbody>
                  {detail.lines.map((l) => (
                    <tr key={l.LineID}>
                      <td>{formatDate(l.VoucherDate)}</td>
                      <td className="font-mono text-xs">{l.VoucherNo || '—'}</td>
                      <td className="max-w-64 truncate">{l.Narrative || '—'}</td>
                      <td>{Number(l.Debit) > 0 ? formatCurrency(l.Debit) : '—'}</td>
                      <td>{Number(l.Credit) > 0 ? formatCurrency(l.Credit) : '—'}</td>
                      <td>
                        {detail.run.Status === 'Open' ? (
                          <input type="checkbox" checked={!!l.IsReconciled} onChange={(e) => toggleLine(l, e.target.checked)} />
                        ) : (
                          l.IsReconciled ? <Badge variant="success">Yes</Badge> : <Badge variant="neutral">No</Badge>
                        )}
                        {l.IsReconciled && l.ReconciledByName && (
                          <div className="text-[10px] text-slate-400">{l.ReconciledByName} · {formatDateTime(l.ReconciledAt)}</div>
                        )}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
            {detail.run.Status === 'Open' && (
              <div className="flex justify-end gap-2">
                <Button variant="danger" onClick={() => setDeleteTarget(detail.run)}>Discard run</Button>
                <Button onClick={completeRun}>Complete reconciliation</Button>
              </div>
            )}
          </div>
        )}
      </Modal>

      <Modal open={createOpen} onClose={() => setCreateOpen(false)} title="New bank reconciliation" size="sm">
        <form onSubmit={createRun} className="space-y-3">
          <div>
            <label className="label">Bank Account *</label>
            <select className="input" value={form.AccountID} onChange={(e) => setForm({ ...form, AccountID: e.target.value })} required>
              <option value="">— select bank —</option>
              {banks.map((b) => <option key={b.AccountID} value={b.AccountID}>{b.Code} · {b.Title}</option>)}
            </select>
          </div>
          <div><label className="label">Statement Date *</label><input type="date" className="input" value={form.StatementDate} onChange={(e) => setForm({ ...form, StatementDate: e.target.value })} required /></div>
          <div><label className="label">Statement Opening Balance</label><input type="number" step="0.01" className="input no-spinner" value={form.StatementOpeningBalance} onChange={(e) => setForm({ ...form, StatementOpeningBalance: e.target.value })} /></div>
          <div><label className="label">Statement Closing Balance</label><input type="number" step="0.01" className="input no-spinner" value={form.StatementClosingBalance} onChange={(e) => setForm({ ...form, StatementClosingBalance: e.target.value })} /></div>
          <div><label className="label">Notes</label><textarea className="input" rows="2" value={form.Notes} onChange={(e) => setForm({ ...form, Notes: e.target.value })} /></div>
          <p className="text-xs text-slate-400">All posted bank transactions up to the statement date are snapshotted for matching. One open run per account.</p>
          <div className="flex justify-end gap-2 pt-2">
            <Button type="button" variant="secondary" onClick={() => setCreateOpen(false)}>Cancel</Button>
            <Button type="submit">Create run</Button>
          </div>
        </form>
      </Modal>

      <ConfirmDialog
        open={!!deleteTarget}
        onClose={() => setDeleteTarget(null)}
        onConfirm={doDelete}
        title="Discard reconciliation run"
        message={`Discard the open reconciliation for ${deleteTarget?.AccountTitle}? Snapshotted marks will be removed.`}
        confirmLabel="Discard"
        danger
      />
    </div>
  );
}
