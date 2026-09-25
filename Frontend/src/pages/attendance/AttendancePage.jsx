import { useEffect, useState, useCallback, useRef } from 'react';
import api from '../../services/api';
import { useToast } from '../../context/ToastContext';
import { formatDateTime } from '../../utils/format';
import Pagination from '../../components/common/Pagination';
import Spinner from '../../components/common/Spinner';
import Button from '../../components/common/Button';
import Modal from '../../components/common/Modal';

export default function AttendancePage() {
  const toast = useToast();
  const [rows, setRows] = useState([]);
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [date, setDate] = useState('');
  const [checkInOpen, setCheckInOpen] = useState(false);

  /* member search picker state */
  const [query, setQuery] = useState('');
  const [results, setResults] = useState([]);
  const [searching, setSearching] = useState(false);
  const [selected, setSelected] = useState(null);
  const [checkingIn, setCheckingIn] = useState(false);
  const searchTimer = useRef(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const params = { page, pageSize: 25, date: date || undefined };
      const res = await api.get('/attendance', { params });
      setRows(res.data.data);
      setTotal(res.data.meta.total);
      setTotalPages(res.data.meta.totalPages);
    } catch (err) { toast.error('Failed to load attendance'); }
    finally { setLoading(false); }
  }, [page, date]);

  useEffect(() => { load(); }, [load]);

  /* debounced member search whenever the query changes */
  useEffect(() => {
    if (!checkInOpen) return undefined;
    if (!query.trim()) {
      setResults([]);
      setSearching(false);
      return undefined;
    }
    setSearching(true);
    searchTimer.current = setTimeout(async () => {
      try {
        const res = await api.get('/members', { params: { search: query.trim(), pageSize: 8 } });
        setResults(res.data.data || []);
      } catch (err) { setResults([]); }
      finally { setSearching(false); }
    }, 350);
    return () => clearTimeout(searchTimer.current);
  }, [query, checkInOpen]);

  const openCheckIn = () => {
    setQuery('');
    setResults([]);
    setSelected(null);
    setCheckInOpen(true);
  };

  const doCheckIn = async () => {
    if (!selected) return toast.error('Please select a member first');
    setCheckingIn(true);
    try {
      await api.post('/attendance/check-in', { memberId: selected.MemberID, method: 'Manual' });
      toast.success(`Checked in — ${selected.FullName}`);
      setCheckInOpen(false);
      setSelected(null);
      setQuery('');
      load();
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Check-in failed'); }
    finally { setCheckingIn(false); }
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Attendance</h1>
        <Button onClick={openCheckIn}>+ Check In</Button>
      </div>

      <div className="card p-4 flex items-end gap-3">
        <div><label className="label">Filter by date</label><input type="date" value={date} onChange={(e) => { setDate(e.target.value); setPage(1); }} className="input" /></div>
        <Button variant="secondary" onClick={() => { setDate(''); setPage(1); }}>Reset</Button>
      </div>

      <div className="card overflow-hidden">
        {loading ? <div className="p-8"><Spinner /></div> : (
          <div className="table-wrap">
            <table className="table">
              <thead><tr><th>Member</th><th>Code</th><th>Check In</th><th>Check Out</th><th>Method</th></tr></thead>
              <tbody>
                {rows.length === 0 && <tr><td colSpan={5} className="text-center text-slate-400 py-8">No attendance records</td></tr>}
                {rows.map((a) => (
                  <tr key={a.AttendanceID}>
                    <td className="font-medium">{a.MemberName}</td>
                    <td className="font-mono text-xs">{a.MemberCode}</td>
                    <td>{formatDateTime(a.CheckInTime)}</td>
                    <td>{a.CheckOutTime ? formatDateTime(a.CheckOutTime) : <span className="text-amber-600">Still in</span>}</td>
                    <td><span className="badge-info">{a.Method}</span></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <div className="px-4"><Pagination page={page} totalPages={totalPages} total={total} onChange={setPage} /></div>
      </div>

      <Modal open={checkInOpen} onClose={() => setCheckInOpen(false)} title="Manual Check-In" size="sm">
        <div className="space-y-3">
          <div>
            <label className="label">Search member *</label>
            <input
              type="text"
              className="input"
              placeholder="Name, code, mobile or CNIC…"
              value={query}
              onChange={(e) => { setQuery(e.target.value); setSelected(null); }}
              autoFocus
            />
          </div>

          {query.trim() && (
            <div className="border border-slate-200 dark:border-slate-700 rounded-lg max-h-56 overflow-y-auto">
              {searching && <div className="px-3 py-2 text-sm text-slate-400">Searching…</div>}
              {!searching && results.length === 0 && (
                <div className="px-3 py-4 text-sm text-slate-400 text-center">No members found for “{query}”</div>
              )}
              {!searching && results.map((m) => (
                <button
                  key={m.MemberID}
                  type="button"
                  onClick={() => { setSelected(m); setQuery(m.FullName); }}
                  className={`w-full text-left px-3 py-2 text-sm border-b border-slate-100 dark:border-slate-800 last:border-b-0 hover:bg-slate-50 dark:hover:bg-slate-800 ${selected?.MemberID === m.MemberID ? 'bg-brand-50 dark:bg-brand-900/20' : ''}`}
                >
                  <div className="font-medium">{m.FullName}</div>
                  <div className="text-xs text-slate-400">{m.Code} · {m.Mobile || 'no mobile'}</div>
                </button>
              ))}
            </div>
          )}

          {selected && (
            <div className="text-sm bg-slate-50 dark:bg-slate-800 rounded-lg px-3 py-2">
              Selected: <span className="font-medium">{selected.FullName}</span> <span className="text-slate-400">({selected.Code})</span>
            </div>
          )}

          <div className="flex justify-end gap-2">
            <Button type="button" variant="secondary" onClick={() => setCheckInOpen(false)}>Cancel</Button>
            <Button type="button" onClick={doCheckIn} disabled={!selected || checkingIn}>{checkingIn ? 'Checking in…' : 'Check In'}</Button>
          </div>
        </div>
      </Modal>
    </div>
  );
}
