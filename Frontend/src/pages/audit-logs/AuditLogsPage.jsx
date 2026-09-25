import { useEffect, useState, useCallback } from 'react';
import api from '../../services/api';
import { useToast } from '../../context/ToastContext';
import { formatDateTime } from '../../utils/format';
import Pagination from '../../components/common/Pagination';
import Spinner from '../../components/common/Spinner';
import { StatusBadge } from '../../components/common/Badge';

export default function AuditLogsPage() {
  const toast = useToast();
  const [rows, setRows] = useState([]);
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [module, setModule] = useState('');
  const [action, setAction] = useState('');

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await api.get('/audit-logs', { params: { page, pageSize: 50, module: module || undefined, action: action || undefined } });
      setRows(res.data.data);
      setTotal(res.data.meta.total);
      setTotalPages(res.data.meta.totalPages);
    } catch (err) { toast.error('Failed to load audit logs'); }
    finally { setLoading(false); }
  }, [page, module, action]);

  useEffect(() => { load(); }, [load]);

  return (
    <div className="space-y-4">
      <h1 className="text-2xl font-bold">Audit Logs</h1>
      <div className="card p-4 flex gap-3 items-end">
        <div><label className="label">Module</label>
          <select value={module} onChange={(e) => { setModule(e.target.value); setPage(1); }} className="input">
            <option value="">All</option>
            {['auth','members','memberships','attendance','fees','finance','users','settings','branches'].map((m) => <option key={m} value={m}>{m}</option>)}
          </select>
        </div>
        <div><label className="label">Action</label>
          <select value={action} onChange={(e) => { setAction(e.target.value); setPage(1); }} className="input">
            <option value="">All</option>
            {['LOGIN','LOGOUT','LOGIN_FAILED','CREATE','UPDATE','DELETE','SETTINGS_CHANGE'].map((a) => <option key={a} value={a}>{a}</option>)}
          </select>
        </div>
      </div>

      <div className="card overflow-hidden">
        {loading ? <div className="p-8"><Spinner /></div> : (
          <div className="table-wrap">
            <table className="table">
              <thead><tr><th>When</th><th>User</th><th>Action</th><th>Module</th><th>Entity</th><th>IP Address</th><th>Location</th></tr></thead>
              <tbody>
                {rows.length === 0 && <tr><td colSpan={7} className="text-center text-slate-400 py-8">No audit entries</td></tr>}
                {rows.map((a) => (
                  <tr key={a.LogID}>
                    <td className="whitespace-normal">{formatDateTime(a.CreatedAt)}</td>
                    <td>{a.UserName || '—'}<div className="text-xs text-slate-400">{a.Username}</div></td>
                    <td><StatusBadge status={a.Action} /></td>
                    <td>{a.Module}</td>
                    <td>{a.EntityID || '—'}</td>
                    <td className="font-mono text-xs">{a.IPAddress || '—'}</td>
                    <td className="font-mono text-xs">{a.Location || '—'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <div className="px-4"><Pagination page={page} totalPages={totalPages} total={total} onChange={setPage} /></div>
      </div>
    </div>
  );
}
