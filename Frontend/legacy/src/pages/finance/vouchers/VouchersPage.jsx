import { useCallback, useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import api from '../../../services/api';
import { useToast } from '../../../context/ToastContext';
import { useAuth } from '../../../context/AuthContext';
import { formatCurrency, formatDate } from '../../../utils/format';
import PageHeader from '../../../components/common/PageHeader';
import Button from '../../../components/common/Button';
import Modal from '../../../components/common/Modal';
import Can from '../../../components/common/Can';
import Badge from '../../../components/common/Badge';
import Spinner from '../../../components/common/Spinner';
import Pagination from '../../../components/common/Pagination';
import ConfirmDialog from '../../../components/common/ConfirmDialog';
import AccountSelector from '../components/AccountSelector';
import SimpleVoucherForm from '../components/SimpleVoucherForm';
import JournalVoucherForm from '../components/JournalVoucherForm';
import VoucherPrint from '../components/VoucherPrint';

const TYPES = {
  brv: { family: 'BANK', path: 'bank-vouchers', direction: 'Receipt', code: 'BRV', title: 'Bank Receipt Voucher', short: 'Bank Receipt', moneyLabel: 'Book Account', bookType: 'Bank Book', simple: true },
  bpv: { family: 'BANK', path: 'bank-vouchers', direction: 'Payment', code: 'BPV', title: 'Bank Payment Voucher', short: 'Bank Payment', moneyLabel: 'Book Account', bookType: 'Bank Book', simple: true },
  crv: { family: 'CASH', path: 'cash-vouchers', direction: 'Receipt', code: 'CRV', title: 'Cash Receipt Voucher', short: 'Cash Receipt', moneyLabel: 'Book Account', bookType: 'Cash Book', simple: true },
  cpv: { family: 'CASH', path: 'cash-vouchers', direction: 'Payment', code: 'CPV', title: 'Cash Payment Voucher', short: 'Cash Payment', moneyLabel: 'Book Account', bookType: 'Cash Book', simple: true },
  jpv: { family: 'JOURNAL', path: 'journal-vouchers', code: 'JPV', title: 'Journal Voucher', short: 'Journal Voucher' },
  opb: { family: 'OTB', path: 'opening-trial-balances', code: 'OPB', title: 'Opening Trial Balance', short: 'Opening Trial Balance' },
};

const STATUS_VARIANT = { Posted: 'success', Reversed: 'neutral', Draft: 'warning', Hold: 'warning' };

export default function VouchersPage() {
  const { type = 'jpv' } = useParams();
  const meta = TYPES[type] || TYPES.jpv;
  const toast = useToast();
  const { user } = useAuth();
  const isSuperAdmin = user?.isSuperAdmin === true;

  const [rows, setRows] = useState([]);
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [total, setTotal] = useState(0);
  const [totalAmount, setTotalAmount] = useState(0);
  const [filters, setFilters] = useState({ status: '', fromDate: '', toDate: '', search: '', bookAccountId: '', accountId: '' });
  const [loading, setLoading] = useState(true);

  const [formOpen, setFormOpen] = useState(false);
  const [editing, setEditing] = useState(null);       // { header, lines }
  const [saving, setSaving] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState(null);
  const [printData, setPrintData] = useState(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const params = { page, pageSize: 15 };
      if (filters.status) params.status = filters.status;
      if (filters.fromDate) params.fromDate = filters.fromDate;
      if (filters.toDate) params.toDate = filters.toDate;
      if (filters.search) params.search = filters.search;
      if (filters.bookAccountId) params.bookAccountId = filters.bookAccountId;
      if (filters.accountId) params.accountId = filters.accountId;
      const res = await api.get(`/finance/${meta.path}`, { params });
      setRows(res.data.data);
      setTotal(res.data.meta.total);
      setTotalPages(res.data.meta.totalPages);
      setTotalAmount(res.data.meta.totalAmount || 0);
    } catch (err) { toast.error('Failed to load vouchers'); }
    finally { setLoading(false); }
  }, [meta.path, page, filters, toast]);

  useEffect(() => { load(); }, [load]);
  useEffect(() => { setPage(1); }, [type, filters.status, filters.search, filters.fromDate, filters.toDate, filters.bookAccountId, filters.accountId]);

  const openNew = () => { setEditing(null); setFormOpen(true); };

  const openEdit = async (row) => {
    try {
      const res = await api.get(`/finance/${meta.path}/${row.ID}`);
      setEditing({ header: res.data.data.voucher, lines: res.data.data.lines });
      setFormOpen(true);
    } catch (err) { toast.error('Failed to load voucher'); }
  };

  const postVoucher = async (row) => {
    try {
      const res = await api.post(`/finance/${meta.path}/${row.ID}/post`);
      toast.success(`Voucher posted as ${res.data.data.VoucherNo}`);
      load();
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Post failed'); }
  };

  const openPrint = async (row) => {
    try {
      const res = await api.get(`/finance/${meta.path}/${row.ID}`);
      setPrintData(res.data.data);
    } catch (err) { toast.error('Failed to load voucher'); }
  };

  const doDelete = async () => {
    if (!deleteTarget) return;
    try {
      await api.delete(`/finance/${meta.path}/${deleteTarget.ID}`);
      toast.success('Voucher deleted and reversed in the ledger');
      setDeleteTarget(null);
      load();
    } catch (err) {
      toast.error(err.response?.data?.error?.message || 'Delete failed');
      setDeleteTarget(null);
    }
  };

  const errText = (err) => err.response?.data?.error?.message || 'Operation failed';

  const toggleStatusFilter = (value) =>
    setFilters((f) => ({ ...f, status: f.status === value ? '' : value }));

  const Form = meta.simple ? SimpleVoucherForm : JournalVoucherForm;

  return (
    <div className="space-y-4">
      <PageHeader
        title={meta.title}
        subtitle={
          meta.simple
            ? `Enter the ${meta.moneyLabel.toLowerCase()}, a description and detail lines with amounts — the debit and credit sides are generated automatically.`
            : 'Select detail accounts and enter Debit / Credit per line. The voucher must balance before it can be saved.'
        }
        actions={<Can perm="finance.add"><Button onClick={openNew}>+ Add Voucher</Button></Can>}
      />

      <div className="card p-4 flex flex-wrap gap-3 items-end no-print">
        <div>
          <label className="label">Status</label>
          <select className="input w-36" value={filters.status} onChange={(e) => setFilters({ ...filters, status: e.target.value })}>
            <option value="">All</option><option>Posted</option><option>Draft</option><option>Hold</option><option>Reversed</option>
          </select>
        </div>
        <div>
          <label className="label">Book Account</label>
          <div className="w-52"><AccountSelector bookType={meta.bookType} value={filters.bookAccountId || ''} onChange={(v) => setFilters({ ...filters, bookAccountId: v || '' })} /></div>
        </div>
        <div>
          <label className="label">Line Account</label>
          <div className="w-52"><AccountSelector value={filters.accountId || ''} onChange={(v) => setFilters({ ...filters, accountId: v || '' })} /></div>
        </div>
        <div><label className="label">From</label><input type="date" className="input w-40" value={filters.fromDate} onChange={(e) => setFilters({ ...filters, fromDate: e.target.value })} /></div>
        <div><label className="label">To</label><input type="date" className="input w-40" value={filters.toDate} onChange={(e) => setFilters({ ...filters, toDate: e.target.value })} /></div>
        <div className="flex-1 min-w-40"><label className="label">Voucher # / Description</label><input className="input" value={filters.search} onChange={(e) => setFilters({ ...filters, search: e.target.value })} /></div>
        <div className="text-sm text-slate-500">Total: <span className="font-bold text-slate-700 dark:text-slate-200">{formatCurrency(totalAmount)}</span></div>
      </div>

      <div className="card overflow-hidden">
        {loading ? <div className="p-8"><Spinner /></div> : (
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th className="no-print">Actions</th>
                  <th>Voucher No</th>
                  <th>Date</th>
                  <th>Book Account</th>
                  <th>Description</th>
                  <th>Lines</th>
                  <th className="text-right">Total Amount</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {rows.length === 0 && (
                  <tr><td colSpan={8} className="text-center text-slate-400 py-8">No vouchers yet</td></tr>
                )}
                {rows.map((r) => (
                  <tr key={r.ID}>
                    <td className="no-print">
                      <div className="flex gap-2 text-sm whitespace-nowrap">
                        <Can perm="finance.edit"><button className="text-brand-600 hover:underline" onClick={() => openEdit(r)}>Edit</button></Can>
                        <button className="text-slate-600 dark:text-slate-300 hover:underline" onClick={() => openPrint(r)}>Print</button>
                        <Can perm="finance.delete"><button className="text-red-500 hover:underline" onClick={() => setDeleteTarget(r)}>Delete</button></Can>
                        {r.Status === 'Draft' || r.Status === 'Hold' ? (
                          <Can perm="finance.post"><button className="text-emerald-600 hover:underline" onClick={() => postVoucher(r)}>Post Voucher</button></Can>
                        ) : null}
                      </div>
                    </td>
                    <td className="font-mono text-xs">{r.VoucherNo || '—'}</td>
                    <td>{formatDate(r.VoucherDate)}</td>
                    <td className="max-w-40 truncate">{r.MoneyAccountTitle || '—'}</td>
                    <td className="max-w-56 truncate">{r.Narrative || '—'}</td>
                    <td className="text-center">{r.LineCount}</td>
                    <td className="text-right font-semibold">{formatCurrency(r.Amount)}</td>
                    <td><Badge variant={STATUS_VARIANT[r.Status] || 'neutral'}>{r.Status}</Badge></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <div className="px-4 no-print"><Pagination page={page} totalPages={totalPages} total={total} onChange={setPage} /></div>
      </div>

      {/* entry / edit */}
      {formOpen && (
        <Form
          open={formOpen}
          onClose={() => setFormOpen(false)}
          onSaved={() => { setFormOpen(false); load(); }}
          meta={meta}
          editing={editing}
        />
      )}

      {/* print */}
      <Modal open={!!printData} onClose={() => setPrintData(null)} title="Print Voucher" size="lg">
        {printData ? (
          <>
            <VoucherPrint voucher={printData.voucher} lines={printData.lines} meta={meta} />
            <div className="flex justify-end gap-2 mt-4 no-print">
              <Button variant="secondary" onClick={() => setPrintData(null)}>Close</Button>
              <Button onClick={() => window.print()}>Print</Button>
            </div>
          </>
        ) : <Spinner />}
      </Modal>

      <ConfirmDialog
        open={!!deleteTarget}
        onClose={() => setDeleteTarget(null)}
        onConfirm={doDelete}
        title="Delete voucher"
        message={`Delete voucher ${deleteTarget?.VoucherNo || ''}? The voucher will be reversed in the ledger and kept in accounting history — it will no longer appear in this list.`}
        confirmLabel="Delete"
        danger
      />
    </div>
  );
}
