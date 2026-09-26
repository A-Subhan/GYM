import { useCallback, useEffect, useMemo, useState } from 'react';
import { useParams, useSearchParams } from 'react-router-dom';
import api from '../../../services/api';
import { useToast } from '../../../context/ToastContext';
import { useAuth } from '../../../context/AuthContext';
import { formatCurrency, formatDate, formatDateTime } from '../../../utils/format';
import { exportToCSV, printPage } from '../../../utils/export';
import PageHeader from '../../../components/common/PageHeader';
import Button from '../../../components/common/Button';
import Modal from '../../../components/common/Modal';
import Can from '../../../components/common/Can';
import Spinner from '../../../components/common/Spinner';
import Pagination from '../../../components/common/Pagination';
import AccountSelector from '../components/AccountSelector';
import PrintHeader from '../components/PrintHeader';

const D = (v) => (v ? String(v).slice(0, 10) : '');

/* Report registry: filters + columns. Column sets can be overridden by the
   user's saved custom formats (UserReportFormats) — the standard layout is
   never modified. */
const REPORTS = {
  ledger: {
    title: 'General Ledger',
    needsAccount: true,
    defaultFilters: { fromDate: '', toDate: '' },
    columns: [
      { key: 'VoucherDate', label: 'Date', render: (r) => formatDate(r.VoucherDate) },
      { key: 'VoucherNo', label: 'Voucher #' },
      { key: 'TypeCode', label: 'Type' },
      { key: 'AccountCode', label: 'Account' },
      { key: 'Narrative', label: 'Description' },
      { key: 'Debit', label: 'Debit', render: (r) => (Number(r.Debit) > 0 ? formatCurrency(r.Debit) : '—'), num: true },
      { key: 'Credit', label: 'Credit', render: (r) => (Number(r.Credit) > 0 ? formatCurrency(r.Credit) : '—'), num: true },
      { key: 'RunningBalance', label: 'Balance', render: (r) => formatCurrency(r.RunningBalance), num: true },
      { key: 'BranchName', label: 'Branch' },
      { key: 'CreatedBy', label: 'Created By' },
    ],
  },
  'trial-balance': {
    title: 'Trial Balance',
    defaultFilters: { fromDate: '', toDate: '' },
    columns: [
      { key: 'Code', label: 'Code' },
      { key: 'Title', label: 'Account' },
      { key: 'AccountType', label: 'Type' },
      { key: 'OpeningDebit', label: 'Opening (Dr)', render: (r) => formatCurrency(r.OpeningDebit), num: true },
      { key: 'OpeningCredit', label: 'Opening (Cr)', render: (r) => formatCurrency(r.OpeningCredit), num: true },
      { key: 'PeriodDebit', label: 'Period (Dr)', render: (r) => formatCurrency(r.PeriodDebit), num: true },
      { key: 'PeriodCredit', label: 'Period (Cr)', render: (r) => formatCurrency(r.PeriodCredit), num: true },
      { key: 'ClosingDebit', label: 'Closing (Dr)', render: (r) => formatCurrency(r.ClosingDebit), num: true },
      { key: 'ClosingCredit', label: 'Closing (Cr)', render: (r) => formatCurrency(r.ClosingCredit), num: true },
    ],
  },
  'opening-tb': {
    title: 'Opening Trial Balance',
    needsYear: true,
    defaultFilters: {},
    columns: [
      { key: 'Code', label: 'Code' },
      { key: 'Title', label: 'Account' },
      { key: 'AccountType', label: 'Type' },
      { key: 'OpeningDebit', label: 'Opening (Dr)', render: (r) => formatCurrency(r.OpeningDebit), num: true },
      { key: 'OpeningCredit', label: 'Opening (Cr)', render: (r) => formatCurrency(r.OpeningCredit), num: true },
    ],
  },
  'balance-sheet': {
    title: 'Balance Sheet',
    defaultFilters: { asOf: '' },
    columns: [
      { key: 'Code', label: 'Code' },
      { key: 'Title', label: 'Account' },
      { key: 'AccountType', label: 'Section' },
      { key: 'Balance', label: 'Balance', render: (r) => formatCurrency(r.Balance), num: true },
    ],
  },
  'profit-loss': {
    title: 'Profit & Loss',
    defaultFilters: { fromDate: '', toDate: '' },
    columns: [
      { key: 'Code', label: 'Code' },
      { key: 'Title', label: 'Account' },
      { key: 'AccountType', label: 'Type' },
      { key: 'Amount', label: 'Amount', render: (r) => formatCurrency(r.Amount), num: true },
    ],
  },
  'customer-aging': {
    title: 'Customer Aging',
    defaultFilters: { asOf: '' },
    columns: [
      { key: 'PartyName', label: 'Customer' },
      { key: 'PartyCode', label: 'Code' },
      { key: 'BillRef', label: 'Bill Ref' },
      { key: 'BillDate', label: 'Bill Date', render: (r) => formatDate(r.BillDate) },
      { key: 'DueDate', label: 'Due Date', render: (r) => formatDate(r.DueDate) },
      { key: 'OriginalAmount', label: 'Original', render: (r) => formatCurrency(r.OriginalAmount), num: true },
      { key: 'AdjustedAmount', label: 'Adjusted', render: (r) => formatCurrency(r.AdjustedAmount), num: true },
      { key: 'RemainingAmount', label: 'Remaining', render: (r) => formatCurrency(r.RemainingAmount), num: true },
      { key: 'AgeDays', label: 'Age' },
      { key: 'Bucket', label: 'Bucket' },
    ],
  },
  'vendor-aging': {
    title: 'Vendor Aging',
    defaultFilters: { asOf: '' },
    columns: [
      { key: 'PartyName', label: 'Vendor' },
      { key: 'PartyCode', label: 'Code' },
      { key: 'BillRef', label: 'Bill Ref' },
      { key: 'BillDate', label: 'Bill Date', render: (r) => formatDate(r.BillDate) },
      { key: 'DueDate', label: 'Due Date', render: (r) => formatDate(r.DueDate) },
      { key: 'OriginalAmount', label: 'Original', render: (r) => formatCurrency(r.OriginalAmount), num: true },
      { key: 'AdjustedAmount', label: 'Adjusted', render: (r) => formatCurrency(r.AdjustedAmount), num: true },
      { key: 'RemainingAmount', label: 'Remaining', render: (r) => formatCurrency(r.RemainingAmount), num: true },
      { key: 'AgeDays', label: 'Age' },
      { key: 'Bucket', label: 'Bucket' },
    ],
  },
  'bank-statement': {
    title: 'Bank Statement',
    needsBank: true,
    defaultFilters: { fromDate: '', toDate: '' },
    summary: true,
    columns: [
      { key: 'VoucherDate', label: 'Date', render: (r) => formatDate(r.VoucherDate) },
      { key: 'VoucherNo', label: 'Voucher #' },
      { key: 'TypeCode', label: 'Type' },
      { key: 'Narrative', label: 'Description' },
      { key: 'Debit', label: 'Deposit', render: (r) => (Number(r.Debit) > 0 ? formatCurrency(r.Debit) : '—'), num: true },
      { key: 'Credit', label: 'Withdrawal', render: (r) => (Number(r.Credit) > 0 ? formatCurrency(r.Credit) : '—'), num: true },
      { key: 'RunningBalance', label: 'Balance', render: (r) => formatCurrency(r.RunningBalance), num: true },
    ],
  },
  'voucher-register': {
    title: 'Voucher Register',
    paginated: true,
    defaultFilters: { fromDate: '', toDate: '', status: '', search: '' },
    columns: [
      { key: 'VoucherNo', label: 'Voucher #' },
      { key: 'VoucherDate', label: 'Date', render: (r) => formatDate(r.VoucherDate) },
      { key: 'TypeTitle', label: 'Type' },
      { key: 'BranchName', label: 'Branch' },
      { key: 'Narrative', label: 'Narration' },
      { key: 'DebitTotal', label: 'Debit Total', render: (r) => formatCurrency(r.DebitTotal), num: true },
      { key: 'CreditTotal', label: 'Credit Total', render: (r) => formatCurrency(r.CreditTotal), num: true },
      { key: 'Status', label: 'Status' },
      { key: 'CreatedByName', label: 'Created By' },
      { key: 'PostedByName', label: 'Posted By' },
    ],
  },
};

export default function FinanceReportsPage() {
  const { key: reportKey } = useParams();
  const meta = REPORTS[reportKey];
  const toast = useToast();
  const { user } = useAuth();
  const isSuperAdmin = user?.isSuperAdmin === true;
  const [searchParams] = useSearchParams();

  const [accountsReady, setAccountsReady] = useState(false);
  const [banks, setBanks] = useState([]);
  const [years, setYears] = useState([]);
  const [branches, setBranches] = useState([]);
  const [filters, setFilters] = useState(meta.defaultFilters);
  const [accountId, setAccountId] = useState(searchParams.get('accountId') || '');
  const [bankId, setBankId] = useState('');
  const [yearId, setYearId] = useState('');
  const [branchId, setBranchId] = useState('');

  const [rows, setRows] = useState([]);
  const [summary, setSummary] = useState(null);
  const [totals, setTotals] = useState(null);
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(false);

  /* custom formats */
  const [formats, setFormats] = useState([]);
  const [activeFormat, setActiveFormat] = useState(null);
  const [formatModal, setFormatModal] = useState(false);
  const [formatName, setFormatName] = useState('');
  const [formatIsDefault, setFormatIsDefault] = useState(false);
  const [visibleCols, setVisibleCols] = useState({}); // key -> bool
  const [colOrder, setColOrder] = useState([]);       // ordered keys

  useEffect(() => {
    setFilters({ ...meta.defaultFilters });
    setAccountId(searchParams.get('accountId') || '');
    setBankId(''); setYearId(''); setPage(1); setSummary(null); setTotals(null);
    setVisibleCols({}); setColOrder([]); setActiveFormat(null);
  }, [reportKey]);

  useEffect(() => {
    api.get('/finance/coa/selectors', { params: { tag: 'Bank', limit: 500 } }).then((r) => setBanks(r.data.data || [])).catch(() => {});
    api.get('/finance/years').then((r) => setYears(r.data.data || [])).catch(() => {});
    if (isSuperAdmin) api.get('/branches').then((r) => setBranches(r.data.data || [])).catch(() => {});
  }, [isSuperAdmin]);

  const loadFormats = useCallback(() => {
    api.get('/finance/report-formats', { params: { reportKey } })
      .then((res) => {
        const list = res.data.data || [];
        setFormats(list);
        const def = list.find((f) => f.IsDefault);
        if (def) {
          setActiveFormat(def);
          const cols = JSON.parse(def.ColumnsJson);
          setVisibleCols(Object.fromEntries(cols.map((c) => [c.key, c.visible !== false])));
          setColOrder(cols.filter((c) => c.visible !== false).sort((a, b) => (a.order || 0) - (b.order || 0)).map((c) => c.key));
        }
      })
      .catch(() => {});
  }, [reportKey]);
  useEffect(() => { loadFormats(); }, [loadFormats]);

  const load = useCallback(async (p = 1) => {
    if (meta.needsAccount && !accountId) { setRows([]); return; }
    if (meta.needsBank && !bankId) { setRows([]); return; }
    if (meta.needsYear && !yearId) { setRows([]); return; }
    setLoading(true);
    try {
      let url, params = {};
      if (reportKey === 'ledger') { url = '/finance/ledger'; params.accountId = accountId; }
      else if (reportKey === 'trial-balance') url = '/finance/trial-balance';
      else if (reportKey === 'opening-tb') { url = '/finance/opening-tb'; params.financialYearId = yearId; }
      else if (reportKey === 'balance-sheet') url = '/finance/balance-sheet';
      else if (reportKey === 'profit-loss') url = '/finance/profit-loss';
      else if (reportKey === 'customer-aging') url = '/finance/aging/customer';
      else if (reportKey === 'vendor-aging') url = '/finance/aging/vendor';
      else if (reportKey === 'bank-statement') { url = '/finance/bank-statement'; params.accountId = bankId; }
      else if (reportKey === 'voucher-register') { url = '/finance/vouchers'; params.pageSize = 15; params.page = p; }

      if (filters.fromDate) params.fromDate = filters.fromDate;
      if (filters.toDate) params.toDate = filters.toDate;
      if (filters.asOf) params.asOf = filters.asOf;
      if (filters.status) params.status = filters.status;
      if (filters.search) params.search = filters.search;
      if (branchId) params.branchId = branchId;

      const res = await api.get(url, { params });
      const data = res.data.data;
      if (reportKey === 'voucher-register') {
        setRows(data || []);
        setTotal(res.data.meta?.total || 0);
        setTotalPages(res.data.meta?.totalPages || 1);
      } else if (reportKey === 'ledger' || reportKey === 'bank-statement') {
        setSummary(data.summary || data[0] || null);
        setRows(data.lines || data[1] || []);
      } else if (reportKey === 'trial-balance' || reportKey === 'opening-tb' || reportKey === 'balance-sheet' || reportKey === 'profit-loss') {
        setRows(data.rows || []);
        setTotals(data.totals || null);
      } else {
        setRows(data || []);
      }
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Failed to load report'); }
    finally { setLoading(false); }
  }, [reportKey, meta, accountId, bankId, yearId, filters, branchId, toast]);

  useEffect(() => { setAccountsReady(true); }, []);
  useEffect(() => { if (accountsReady) load(1); }, [accountsReady, reportKey, accountId, bankId, yearId, filters, branchId]);

  /* effective column order/visibility (standard layout untouched; format overlays it) */
  const columns = useMemo(() => {
    const base = meta.columns;
    if (!colOrder.length) return base;
    const map = Object.fromEntries(base.map((c) => [c.key, c]));
    const ordered = colOrder.map((k) => map[k]).filter(Boolean);
    const rest = base.filter((c) => !colOrder.includes(c.key) && visibleCols[c.key] !== false);
    return [...ordered, ...rest];
  }, [meta.columns, colOrder, visibleCols]);

  const isColumnVisible = (c) => visibleCols[c.key] !== false;

  const doExport = () => {
    exportToCSV(
      rows,
      `${reportKey}.csv`,
      columns.filter(isColumnVisible).map((c) => ({ key: c.key, label: c.label }))
    );
  };

  const saveFormat = async () => {
    if (!formatName.trim()) return toast.error('Give the format a name');
    try {
      const cols = meta.columns.map((c, i) => ({ key: c.key, label: c.label, visible: isColumnVisible(c), order: colOrder.indexOf(c.key) >= 0 ? colOrder.indexOf(c.key) : 100 + i }));
      await api.post('/finance/report-formats', {
        ReportKey: reportKey, FormatName: formatName.trim(), Columns: cols, IsDefault: formatIsDefault,
      });
      toast.success('Format saved');
      setFormatModal(false); setFormatName(''); setFormatIsDefault(false);
      loadFormats();
    } catch (err) { toast.error('Could not save format'); }
  };

  const applyFormat = (f) => {
    setActiveFormat(f);
    if (!f) { setVisibleCols({}); setColOrder([]); return; }
    const cols = JSON.parse(f.ColumnsJson);
    setVisibleCols(Object.fromEntries(cols.map((c) => [c.key, c.visible !== false])));
    setColOrder(cols.filter((c) => c.visible !== false).sort((a, b) => (a.order || 0) - (b.order || 0)).map((c) => c.key));
  };

  const deleteFormat = async (f) => {
    try {
      await api.delete(`/finance/report-formats/${f.FormatID}`);
      if (activeFormat?.FormatID === f.FormatID) { setActiveFormat(null); setVisibleCols({}); setColOrder([]); }
      loadFormats();
      toast.success('Format deleted');
    } catch (err) { toast.error('Could not delete format'); }
  };

  const moveCol = (key, dir) => {
    const order = (colOrder.length ? colOrder : meta.columns.map((c) => c.key)).filter((k) => visibleCols[k] !== false);
    const i = order.indexOf(key);
    const j = i + dir;
    if (i < 0 || j < 0 || j >= order.length) return;
    [order[i], order[j]] = [order[j], order[i]];
    setColOrder(order);
  };

  if (!meta) return <div className="text-center text-slate-400 mt-20">Unknown report.</div>;

  const subtitleParts = [];
  if (filters.fromDate) subtitleParts.push(`From ${formatDate(filters.fromDate)}`);
  if (filters.toDate) subtitleParts.push(`To ${formatDate(filters.toDate)}`);
  if (filters.asOf) subtitleParts.push(`As of ${formatDate(filters.asOf)}`);
  if (summary && reportKey === 'bank-statement') subtitleParts.push(`Closing ${formatCurrency(summary.ClosingBalance)}`);

  return (
    <div className="space-y-4">
      <PageHeader
        title={meta.title}
        actions={
          <div className="flex gap-2 no-print">
            {rows.length > 0 && <Button variant="ghost" onClick={doExport}>Export CSV</Button>}
            {rows.length > 0 && <Button variant="secondary" onClick={printPage}>Print</Button>}
            <Can perm="finance.reports"><Button variant="secondary" onClick={() => setFormatModal(true)}>Formats</Button></Can>
          </div>
        }
      />

      <div className="card p-4 flex flex-wrap gap-3 items-end no-print">
        {meta.needsAccount && (
          <div className="min-w-72 flex-1">
            <label className="label">Account *</label>
            <AccountSelector value={accountId} onChange={setAccountId} />
          </div>
        )}
        {meta.needsBank && (
          <div className="min-w-72 flex-1">
            <label className="label">Bank Account *</label>
            <select className="input" value={bankId} onChange={(e) => setBankId(e.target.value)}>
              <option value="">— select bank —</option>
              {banks.map((b) => <option key={b.AccountID} value={b.AccountID}>{b.Code} · {b.Title}</option>)}
            </select>
          </div>
        )}
        {meta.needsYear && (
          <div>
            <label className="label">Financial Year *</label>
            <select className="input w-44" value={yearId} onChange={(e) => setYearId(e.target.value)}>
              <option value="">— select year —</option>
              {years.map((y) => <option key={y.FinancialYearID} value={y.FinancialYearID}>{y.Name} ({D(y.StartDate)} → {D(y.EndDate)})</option>)}
            </select>
          </div>
        )}
        {filters.fromDate !== undefined && !meta.needsYear && (
          <div><label className="label">From</label><input type="date" className="input w-40" value={filters.fromDate || ''} onChange={(e) => setFilters({ ...filters, fromDate: e.target.value })} /></div>
        )}
        {filters.toDate !== undefined && !meta.needsYear && (
          <div><label className="label">To</label><input type="date" className="input w-40" value={filters.toDate || ''} onChange={(e) => setFilters({ ...filters, toDate: e.target.value })} /></div>
        )}
        {filters.asOf !== undefined && (
          <div><label className="label">As of</label><input type="date" className="input w-40" value={filters.asOf || ''} onChange={(e) => setFilters({ ...filters, asOf: e.target.value })} /></div>
        )}
        {filters.status !== undefined && (
          <div><label className="label">Status</label>
            <select className="input w-32" value={filters.status} onChange={(e) => setFilters({ ...filters, status: e.target.value })}>
              <option value="">All</option><option>Draft</option><option>Posted</option><option>Reversed</option>
            </select>
          </div>
        )}
        {filters.search !== undefined && (
          <div className="flex-1 min-w-40"><label className="label">Search</label><input className="input" value={filters.search} onChange={(e) => setFilters({ ...filters, search: e.target.value })} /></div>
        )}
        {isSuperAdmin && (
          <div><label className="label">Branch</label>
            <select className="input w-40" value={branchId} onChange={(e) => setBranchId(e.target.value)}>
              <option value="">All branches</option>
              {branches.map((b) => <option key={b.BranchID} value={b.BranchID}>{b.Name}</option>)}
            </select>
          </div>
        )}
      </div>

      {activeFormat && (
        <div className="text-xs text-slate-500 no-print">
          Custom format: <span className="font-semibold">{activeFormat.FormatName}</span>
          <button className="ml-2 text-brand-600 hover:underline" onClick={() => applyFormat(null)}>reset to standard</button>
        </div>
      )}

      <div className="card overflow-hidden">
        {loading ? <div className="p-8"><Spinner /></div> : (
          <div className="print-area p-4">
            <PrintHeader title={meta.title} subtitle={subtitleParts.join(' · ')} />
            <div className="table-wrap">
              <table className="table">
                <thead><tr>{columns.filter(isColumnVisible).map((c) => <th key={c.key} className={c.num ? 'text-right' : ''}>{c.label}</th>)}</tr></thead>
                <tbody>
                  {rows.length === 0 && <tr><td colSpan={columns.length} className="text-center text-slate-400 py-8">No data for the selected filters</td></tr>}
                  {rows.map((r, i) => (
                    <tr key={r.EntryID || r.VoucherID || r.AccountID || i}>
                      {columns.filter(isColumnVisible).map((c) => (
                        <td key={c.key} className={c.num ? 'text-right' : ''}>{c.render ? c.render(r, i) : (r[c.key] ?? '—')}</td>
                      ))}
                    </tr>
                  ))}
                </tbody>
                {totals && (
                  <tfoot>
                    <tr className="font-semibold border-t-2 border-slate-300">
                      <td colSpan={reportKey === 'trial-balance' || reportKey === 'opening-tb' ? 2 : Math.max(1, columns.length - Object.keys(totals).length + 1)}>TOTALS</td>
                      {Object.entries(totals).filter(([k]) => k !== 'FromDate' && k !== 'ToDate').map(([k, v]) => (
                        <td key={k} className="text-right">{formatCurrency(v)}</td>
                      ))}
                    </tr>
                  </tfoot>
                )}
              </table>
            </div>
            {reportKey === 'balance-sheet' && totals && (
              <div className={`mt-4 text-center p-3 rounded-xl ${Math.abs(Number(totals.Difference)) < 0.01 ? 'bg-emerald-50 dark:bg-emerald-900/20' : 'bg-red-50 dark:bg-red-900/20'}`}>
                <div className="text-sm">Assets {formatCurrency(totals.AssetsTotal)} = Liabilities {formatCurrency(totals.LiabilitiesTotal)} + Equity {formatCurrency(totals.EquityTotal)}</div>
                <div className="text-xs text-slate-500">includes net profit {formatCurrency(totals.NetProfit)} · difference {formatCurrency(totals.Difference)}</div>
              </div>
            )}
            {reportKey === 'profit-loss' && totals && (
              <div className="mt-4 text-center p-3 rounded-xl bg-slate-50 dark:bg-slate-900/20">
                <div className="text-sm">Revenue {formatCurrency(totals.RevenueTotal)} − Expenses {formatCurrency(totals.ExpenseTotal)} = <span className="font-bold">Net Profit {formatCurrency(totals.NetProfit)}</span></div>
              </div>
            )}
            {summary && reportKey === 'ledger' && (
              <div className="mt-3 text-sm text-slate-500">
                Opening {formatCurrency(summary.OpeningBalance)} · Period Debit {formatCurrency(summary.TotalDebit)} · Period Credit {formatCurrency(summary.TotalCredit)} · Closing {formatCurrency(summary.ClosingBalance)}
              </div>
            )}
            {summary && reportKey === 'bank-statement' && (
              <div className="mt-3 text-sm text-slate-500">
                Opening {formatCurrency(summary.OpeningBalance)} · Deposits {formatCurrency(summary.TotalDebit)} · Withdrawals {formatCurrency(summary.TotalCredit)} · Closing {formatCurrency(summary.ClosingBalance)}
              </div>
            )}
          </div>
        )}
        {meta.paginated && (
          <div className="px-4 no-print"><Pagination page={page} totalPages={totalPages} total={total} onChange={(p) => { setPage(p); load(p); }} /></div>
        )}
      </div>

      {/* -------- custom formats -------- */}
      <Modal open={formatModal} onClose={() => setFormatModal(false)} title="Custom report formats" size="md">
        <div className="space-y-4">
          <div>
            <div className="label">Columns (visibility & order)</div>
            <div className="space-y-1">
              {meta.columns.map((c) => (
                <div key={c.key} className="flex items-center justify-between border rounded-lg px-3 py-1.5 text-sm">
                  <label className="flex items-center gap-2 cursor-pointer">
                    <input type="checkbox" checked={isColumnVisible(c)}
                      onChange={(e) => setVisibleCols({ ...visibleCols, [c.key]: e.target.checked })} />
                    {c.label}
                  </label>
                  <div className="flex gap-1">
                    <button type="button" className="px-2 border rounded hover:bg-slate-100" onClick={() => moveCol(c.key, -1)}>↑</button>
                    <button type="button" className="px-2 border rounded hover:bg-slate-100" onClick={() => moveCol(c.key, 1)}>↓</button>
                  </div>
                </div>
              ))}
            </div>
          </div>

          <div className="border-t pt-3">
            <div className="label">Save current layout as a format</div>
            <div className="flex gap-2 items-center">
              <input className="input flex-1" placeholder="Format name" value={formatName} onChange={(e) => setFormatName(e.target.value)} />
              <label className="flex items-center gap-1 text-sm whitespace-nowrap">
                <input type="checkbox" checked={formatIsDefault} onChange={(e) => setFormatIsDefault(e.target.checked)} /> Default
              </label>
              <Button onClick={saveFormat}>Save</Button>
            </div>
          </div>

          <div className="border-t pt-3">
            <div className="label">My saved formats</div>
            {formats.length === 0 && <div className="text-sm text-slate-400">None saved yet.</div>}
            {formats.map((f) => (
              <div key={f.FormatID} className="flex items-center justify-between py-1 text-sm">
                <button className="text-brand-600 hover:underline" onClick={() => applyFormat(f)}>
                  {f.FormatName}{f.IsDefault ? ' (default)' : ''}
                </button>
                <button className="text-red-500 hover:underline" onClick={() => deleteFormat(f)}>Delete</button>
              </div>
            ))}
          </div>
        </div>
      </Modal>
    </div>
  );
}
