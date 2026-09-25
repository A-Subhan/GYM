import { useEffect, useState, useCallback } from 'react';
import api from '../../services/api';
import { useToast } from '../../context/ToastContext';
import { formatDate, formatCurrency } from '../../utils/format';
import { StatusBadge } from '../../components/common/Badge';
import Pagination from '../../components/common/Pagination';
import Spinner from '../../components/common/Spinner';

export default function FeesPage() {
  const toast = useToast();
  const [tab, setTab] = useState('collections');
  const [rows, setRows] = useState([]);
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [total, setTotal] = useState(0);
  const [totalAmount, setTotalAmount] = useState(0);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const url = tab === 'collections' ? '/fees/collections' : '/fees/invoices';
      const res = await api.get(url, { params: { page, pageSize: 20 } });
      setRows(res.data.data);
      setTotal(res.data.meta.total);
      setTotalPages(res.data.meta.totalPages);
      if (tab === 'collections') setTotalAmount(res.data.meta.totalAmount || 0);
    } catch (err) { toast.error('Failed to load fees'); }
    finally { setLoading(false); }
  }, [tab, page]);

  useEffect(() => { load(); }, [load]);

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Fees & Invoices</h1>
        {tab === 'collections' && totalAmount > 0 && (
          <div className="text-sm text-slate-500">Total collected: <span className="font-bold text-emerald-600">{formatCurrency(totalAmount)}</span></div>
        )}
      </div>

      <div className="card overflow-hidden">
        <div className="flex border-b border-slate-200 dark:border-slate-800">
          {['collections','invoices'].map((t) => (
            <button key={t} onClick={() => { setTab(t); setPage(1); }} className={`px-5 py-3 text-sm font-medium border-b-2 capitalize ${tab === t ? 'border-brand-600 text-brand-600' : 'border-transparent text-slate-500 hover:text-slate-700'}`}>{t}</button>
          ))}
        </div>

        {loading ? <div className="p-8"><Spinner /></div> : (
          <div className="table-wrap">
            {tab === 'collections' ? (
              <table className="table">
                <thead><tr><th>Member</th><th>Amount</th><th>Method</th><th>Ref</th><th>Date</th><th>Collected By</th></tr></thead>
                <tbody>
                  {rows.length === 0 && <tr><td colSpan={6} className="text-center text-slate-400 py-8">No collections</td></tr>}
                  {rows.map((c) => (
                    <tr key={c.CollectionID}>
                      <td>{c.MemberName}<div className="text-xs text-slate-400">{c.MemberCode}</div></td>
                      <td className="font-semibold text-emerald-600">{formatCurrency(c.Amount)}</td>
                      <td>{c.MethodName}</td>
                      <td className="font-mono text-xs">{c.TransactionRef || '—'}</td>
                      <td>{formatDate(c.CollectedAt)}</td>
                      <td>{c.CollectedByName || '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            ) : (
              <table className="table">
                <thead><tr><th>Invoice #</th><th>Member</th><th>Net Amount</th><th>Paid</th><th>Status</th><th>Issue Date</th><th>Due Date</th></tr></thead>
                <tbody>
                  {rows.length === 0 && <tr><td colSpan={7} className="text-center text-slate-400 py-8">No invoices</td></tr>}
                  {rows.map((i) => (
                    <tr key={i.InvoiceID}>
                      <td className="font-mono text-xs">{i.InvoiceNo}</td>
                      <td>{i.MemberName}</td>
                      <td className="font-semibold">{formatCurrency(i.NetAmount)}</td>
                      <td>{formatCurrency(i.PaidAmount)}</td>
                      <td><StatusBadge status={i.Status} /></td>
                      <td>{formatDate(i.IssueDate)}</td>
                      <td>{formatDate(i.DueDate)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        )}
        <div className="px-4"><Pagination page={page} totalPages={totalPages} total={total} onChange={setPage} /></div>
      </div>
    </div>
  );
}
