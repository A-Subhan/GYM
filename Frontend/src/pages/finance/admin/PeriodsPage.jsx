import { useCallback, useEffect, useState } from 'react';
import api from '../../../services/api';
import { useToast } from '../../../context/ToastContext';
import { formatDate } from '../../../utils/format';
import PageHeader from '../../../components/common/PageHeader';
import Button from '../../../components/common/Button';
import Modal from '../../../components/common/Modal';
import Can from '../../../components/common/Can';
import Badge from '../../../components/common/Badge';
import Spinner from '../../../components/common/Spinner';
import ConfirmDialog from '../../../components/common/ConfirmDialog';

const STATUS_VARIANT = { Open: 'success', Locked: 'warning', Closed: 'neutral' };

export default function PeriodsPage() {
  const toast = useToast();
  const [years, setYears] = useState([]);
  const [expanded, setExpanded] = useState(null);
  const [periods, setPeriods] = useState([]);
  const [loading, setLoading] = useState(true);
  const [periodsLoading, setPeriodsLoading] = useState(false);

  const [addOpen, setAddOpen] = useState(false);
  const [form, setForm] = useState({ Name: '', StartDate: '', EndDate: '' });
  const [closeTarget, setCloseTarget] = useState(null);
  const [lockTarget, setLockTarget] = useState(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await api.get('/finance/years');
      setYears(res.data.data || []);
    } catch (err) { toast.error('Failed to load financial years'); }
    finally { setLoading(false); }
  }, [toast]);

  useEffect(() => { load(); }, [load]);

  const loadPeriods = useCallback(async (fyId) => {
    setPeriodsLoading(true);
    try {
      const res = await api.get(`/finance/years/${fyId}/periods`);
      setPeriods(res.data.data || []);
    } catch (err) { toast.error('Failed to load periods'); }
    finally { setPeriodsLoading(false); }
  }, [toast]);

  const toggleExpand = (fyId) => {
    if (expanded === fyId) { setExpanded(null); return; }
    setExpanded(fyId);
    loadPeriods(fyId);
  };

  const errText = (err) => err.response?.data?.error?.message || 'Operation failed';

  const createYear = async (e) => {
    e.preventDefault();
    try {
      await api.post('/finance/years', form);
      toast.success('Financial year created with 12 monthly periods');
      setAddOpen(false);
      setForm({ Name: '', StartDate: '', EndDate: '' });
      load();
    } catch (err) { toast.error(errText(err)); }
  };

  const setYearStatus = async (fy, status) => {
    try {
      await api.patch(`/finance/years/${fy.FinancialYearID}/status`, { Status: status });
      toast.success(status === 'Locked' ? 'Year locked' : 'Year unlocked');
      load();
    } catch (err) { toast.error(errText(err)); }
  };

  const doClose = async () => {
    if (!closeTarget) return;
    try {
      const res = await api.post(`/finance/years/${closeTarget.FinancialYearID}/close`, {});
      toast.success(`Year closed. Closing voucher posted; FY ${res.data.data?.NextFinancialYearID ? 'next year ready' : ''}`);
      setCloseTarget(null);
      load();
    } catch (err) { toast.error(errText(err)); setCloseTarget(null); }
  };

  const setPeriodStatus = async (period, status) => {
    try {
      await api.patch(`/finance/periods/${period.PeriodID}/status`, { Status: status });
      toast.success(`Period ${status === 'Open' ? 'reopened' : status.toLowerCase()}`);
      loadPeriods(expanded);
    } catch (err) { toast.error(errText(err)); }
  };

  if (loading) return <Spinner size="lg" className="mt-20" />;

  return (
    <div className="space-y-4">
      <PageHeader
        title="Financial Years & Accounting Periods"
        subtitle="Voucher dates must fall inside an open period of an open financial year. Closing a year posts closing entries and carries balances forward."
        actions={<Can perm="finance.periods"><Button onClick={() => setAddOpen(true)}>+ New Financial Year</Button></Can>}
      />

      <div className="space-y-3">
        {years.map((fy) => (
          <div key={fy.FinancialYearID} className="card p-4">
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div>
                <div className="flex items-center gap-2">
                  <span className="font-semibold text-lg">{fy.Name}</span>
                  <Badge variant={STATUS_VARIANT[fy.Status]}>{fy.Status}</Badge>
                </div>
                <div className="text-sm text-slate-500">
                  {formatDate(fy.StartDate)} → {formatDate(fy.EndDate)} · {fy.VoucherCount} vouchers ·
                  Dr {Number(fy.TotalDebit).toLocaleString()} / Cr {Number(fy.TotalCredit).toLocaleString()}
                </div>
              </div>
              <div className="flex gap-2 text-sm no-print">
                <Button variant="ghost" onClick={() => toggleExpand(fy.FinancialYearID)}>{expanded === fy.FinancialYearID ? 'Hide periods' : 'Periods'}</Button>
                {fy.Status !== 'Closed' && (
                  <Can perm="finance.periods">
                    {fy.Status === 'Open' && <Button variant="secondary" onClick={() => setLockTarget({ fy, status: 'Locked' })}>Lock</Button>}
                    {fy.Status === 'Locked' && <Button variant="secondary" onClick={() => setLockTarget({ fy, status: 'Open' })}>Unlock</Button>}
                    <Button variant="danger" onClick={() => setCloseTarget(fy)}>Close Year</Button>
                  </Can>
                )}
              </div>
            </div>

            {expanded === fy.FinancialYearID && (
              <div className="mt-4 border-t pt-3">
                {periodsLoading ? <Spinner /> : (
                  <div className="table-wrap">
                    <table className="table text-sm">
                      <thead><tr><th>#</th><th>Start</th><th>End</th><th>Status</th><th>Drafts</th><th className="no-print">Actions</th></tr></thead>
                      <tbody>
                        {periods.map((p) => (
                          <tr key={p.PeriodID}>
                            <td>{p.PeriodNo}</td>
                            <td>{formatDate(p.StartDate)}</td>
                            <td>{formatDate(p.EndDate)}</td>
                            <td><Badge variant={STATUS_VARIANT[p.Status]}>{p.Status}</Badge></td>
                            <td>{p.DraftCount}</td>
                            <td className="no-print">
                              {fy.Status !== 'Closed' && (
                                <Can perm="finance.periods">
                                  <div className="flex gap-2">
                                    {p.Status !== 'Open' && <button className="text-emerald-600 hover:underline" onClick={() => setPeriodStatus(p, 'Open')}>Reopen</button>}
                                    {p.Status === 'Open' && <button className="text-amber-600 hover:underline" onClick={() => setPeriodStatus(p, 'Closed')}>Close</button>}
                                    {p.Status !== 'Locked' && <button className="text-slate-600 hover:underline" onClick={() => setPeriodStatus(p, 'Locked')}>Lock</button>}
                                  </div>
                                </Can>
                              )}
                            </td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            )}
          </div>
        ))}
      </div>

      <Modal open={addOpen} onClose={() => setAddOpen(false)} title="New financial year" size="sm">
        <form onSubmit={createYear} className="space-y-3">
          <div><label className="label">Name *</label><input className="input" placeholder="FY 2027" value={form.Name} onChange={(e) => setForm({ ...form, Name: e.target.value })} required /></div>
          <div><label className="label">Start Date *</label><input type="date" className="input" value={form.StartDate} onChange={(e) => setForm({ ...form, StartDate: e.target.value })} required /></div>
          <div><label className="label">End Date *</label><input type="date" className="input" value={form.EndDate} onChange={(e) => setForm({ ...form, EndDate: e.target.value })} required /></div>
          <p className="text-xs text-slate-400">12 monthly periods are created automatically. Years may not overlap.</p>
          <div className="flex justify-end gap-2 pt-2">
            <Button type="button" variant="secondary" onClick={() => setAddOpen(false)}>Cancel</Button>
            <Button type="submit">Create</Button>
          </div>
        </form>
      </Modal>

      <ConfirmDialog
        open={!!lockTarget}
        onClose={() => setLockTarget(null)}
        onConfirm={() => setYearStatus(lockTarget.fy, lockTarget.status)}
        title={lockTarget?.status === 'Locked' ? 'Lock financial year' : 'Unlock financial year'}
        message={lockTarget?.status === 'Locked'
          ? `Lock ${lockTarget.fy.Name}? New postings will be rejected until it is unlocked.`
          : `Unlock ${lockTarget.fy.Name}? Users will be able to post into it again.`}
        confirmLabel={lockTarget?.status === 'Locked' ? 'Lock' : 'Unlock'}
      />

      <ConfirmDialog
        open={!!closeTarget}
        onClose={() => setCloseTarget(null)}
        onConfirm={doClose}
        title="Close financial year"
        message={`Close ${closeTarget?.Name}? Revenue and expense accounts will be closed to Retained Earnings through a system voucher, balances will carry forward to the next year, and the year will permanently reject new postings. This cannot be undone.`}
        confirmLabel="Close year permanently"
        danger
      />
    </div>
  );
}
