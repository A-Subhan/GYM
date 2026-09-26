import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useParams } from 'react-router-dom';
import api from '../../../services/api';
import { useToast } from '../../../context/ToastContext';
import { useAuth } from '../../../context/AuthContext';
import { formatDate } from '../../../utils/format';
import { exportToCSV, printPage } from '../../../utils/export';
import Button from '../../../components/common/Button';
import Can from '../../../components/common/Can';
import Badge from '../../../components/common/Badge';
import Spinner from '../../../components/common/Spinner';
import ConfirmDialog from '../../../components/common/ConfirmDialog';
import PageHeader from '../../../components/common/PageHeader';
import PrintHeader from '../components/PrintHeader';
import AccountTreePicker from '../components/AccountTreePicker';

const TAGS = ['Customer', 'Vendor', 'Bank', 'Cash', 'Employee', 'Tax'];
const BOOK_TYPES = ['Cash Book', 'Bank Book'];
const EMPTY_FORM = {
  Title: '', ParentAccountID: '', IsControl: false, KnockOff: false,
  BookType: '', BranchID: '', IsActive: true,
  Description: '', ReferenceNo: '',
  Address: '', Phone: '', Whatsapp: '', Telephone: '', Fax: '', Email: '',
  Cnic: '', Ntn: '', Strn: '',
  BankName: '', BankAccountTitle: '', BankAccountNo: '', IBAN: '', BankBranch: '',
  Tags: [],
};

const TYPE_VARIANT = { Asset: 'info', Liability: 'warning', Capital: 'neutral', Revenue: 'success', Expense: 'danger' };
const parseTags = (t) => (t ? String(t).split(',').filter(Boolean) : []);

/* ------------------------------------------------------------------ */
/* Universal Add / Edit account form (right panel, inline — no popup)  */
/* ------------------------------------------------------------------ */
function AccountForm({ mode, form, setForm, nextCodePreview, branches, saving, onSubmit, onCancel }) {
  const isEdit = mode === 'edit';
  const set = (k, v) => setForm((f) => ({ ...f, [k]: v }));
  const [parentPicker, setParentPicker] = useState(false);
  const parentLabel = form.ParentAccountID
    ? `${form.ParentCode || ''} ${form.ParentTitle || ''}`.trim() || `Account #${form.ParentAccountID}`
    : '';

  return (
    <form onSubmit={(e) => { e.preventDefault(); onSubmit(); }} className="space-y-4">
      {/* basic */}
      <section>
        <h4 className="text-xs font-semibold uppercase tracking-wide text-slate-400 mb-2">Basic Information</h4>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div>
            <label className="label">Account Name *</label>
            <input className="input" value={form.Title} onChange={(e) => set('Title', e.target.value)} required />
          </div>
          <div>
            <label className="label">Account Code (auto)</label>
            <input className="input font-mono bg-slate-100 dark:bg-slate-800" value={isEdit ? (form.Code || '') : (nextCodePreview || '…')} disabled />
            <p className="text-[11px] text-slate-400 mt-1">Generated automatically from the parent — never typed.</p>
          </div>
          <div>
            <label className="label">Parent Account *</label>
            {isEdit ? (
              <input className="input bg-slate-100 dark:bg-slate-800" value={parentLabel} disabled />
            ) : (
              <button type="button" className={`input text-left truncate ${form.ParentAccountID ? '' : 'text-slate-400'}`}
                onClick={() => setParentPicker(true)}>
                {form.ParentAccountID ? parentLabel : 'Choose parent account…'}
              </button>
            )}
          </div>
          <div>
            <label className="label">Account Type *</label>
            {isEdit ? (
              <input className="input bg-slate-100 dark:bg-slate-800" value={form.IsControl ? 'Control Account' : 'Detail Account'} disabled />
            ) : (
              <select className="input" value={form.IsControl ? 'control' : 'detail'}
                onChange={(e) => set('IsControl', e.target.value === 'control')}>
                <option value="detail">Detail Account (postings allowed)</option>
                <option value="control">Control Account (grouping only)</option>
              </select>
            )}
          </div>
          <div>
            <label className="label">Book Type</label>
            <select className="input" value={form.BookType || ''} disabled={isEdit ? !form.IsControl : form.IsControl}
              onChange={(e) => set('BookType', e.target.value)}>
              <option value="">— none —</option>
              {BOOK_TYPES.map((b) => <option key={b} value={b}>{b}</option>)}
            </select>
            <p className="text-[11px] text-slate-400 mt-1">Detail accounts only. Controls voucher Book Account selection.</p>
          </div>
          <div>
            <label className="label">Branch</label>
            <select className="input" value={form.BranchID || ''} onChange={(e) => set('BranchID', e.target.value)}>
              <option value="">All Branches</option>
              {branches.map((b) => <option key={b.BranchID} value={b.BranchID}>{b.Name}</option>)}
            </select>
          </div>
          <div>
            <label className="label">Status</label>
            <select className="input" value={form.IsActive ? 'active' : 'inactive'}
              onChange={(e) => set('IsActive', e.target.value === 'active')}>
              <option value="active">Active</option>
              <option value="inactive">Inactive</option>
            </select>
          </div>
          <div className="flex items-center gap-2 pt-5">
            <input type="checkbox" id="knockoff" checked={!!form.KnockOff} disabled={isEdit ? !form.IsControl : form.IsControl}
              onChange={(e) => set('KnockOff', e.target.checked)} />
            <label htmlFor="knockoff" className="text-sm">Bill Wise / Knock Off</label>
          </div>
        </div>
      </section>

      {/* general */}
      <section>
        <h4 className="text-xs font-semibold uppercase tracking-wide text-slate-400 mb-2">General Information</h4>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div className="sm:col-span-2">
            <label className="label">Description</label>
            <textarea className="input" rows="2" value={form.Description} onChange={(e) => set('Description', e.target.value)} />
          </div>
          <div>
            <label className="label">Reference Number</label>
            <input className="input" value={form.ReferenceNo} onChange={(e) => set('ReferenceNo', e.target.value)} />
          </div>
          <div>
            <label className="label">Tags</label>
            <div className="flex flex-wrap gap-1.5">
              {TAGS.map((t) => (
                <label key={t} className="flex items-center gap-1 text-xs border rounded-lg px-2 py-1 cursor-pointer">
                  <input type="checkbox" checked={form.Tags.includes(t)}
                    onChange={(e) => set('Tags', e.target.checked ? [...form.Tags, t] : form.Tags.filter((x) => x !== t))} />
                  {t}
                </label>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* contact */}
      <section>
        <h4 className="text-xs font-semibold uppercase tracking-wide text-slate-400 mb-2">Contact Information</h4>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div className="sm:col-span-2"><label className="label">Address</label><input className="input" value={form.Address} onChange={(e) => set('Address', e.target.value)} /></div>
          <div><label className="label">Phone Number</label><input className="input" value={form.Phone} onChange={(e) => set('Phone', e.target.value)} /></div>
          <div><label className="label">WhatsApp Number</label><input className="input" value={form.Whatsapp} onChange={(e) => set('Whatsapp', e.target.value)} /></div>
          <div><label className="label">Telephone Number</label><input className="input" value={form.Telephone} onChange={(e) => set('Telephone', e.target.value)} /></div>
          <div><label className="label">Fax Number</label><input className="input" value={form.Fax} onChange={(e) => set('Fax', e.target.value)} /></div>
          <div><label className="label">Email</label><input className="input" value={form.Email} onChange={(e) => set('Email', e.target.value)} /></div>
        </div>
      </section>

      {/* identification */}
      <section>
        <h4 className="text-xs font-semibold uppercase tracking-wide text-slate-400 mb-2">Identification</h4>
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <div><label className="label">CNIC Number</label><input className="input" value={form.Cnic} onChange={(e) => set('Cnic', e.target.value)} /></div>
          <div><label className="label">NTN Number</label><input className="input" value={form.Ntn} onChange={(e) => set('Ntn', e.target.value)} /></div>
          <div><label className="label">STRN Number</label><input className="input" value={form.Strn} onChange={(e) => set('Strn', e.target.value)} /></div>
        </div>
      </section>

      {/* bank */}
      {(form.BookType === 'Bank Book') && (
        <section>
          <h4 className="text-xs font-semibold uppercase tracking-wide text-slate-400 mb-2">Bank Information</h4>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div><label className="label">Bank Name</label><input className="input" value={form.BankName} onChange={(e) => set('BankName', e.target.value)} /></div>
            <div><label className="label">Account Title</label><input className="input" value={form.BankAccountTitle} onChange={(e) => set('BankAccountTitle', e.target.value)} /></div>
            <div><label className="label">Account Number</label><input className="input" value={form.BankAccountNo} onChange={(e) => set('BankAccountNo', e.target.value)} /></div>
            <div><label className="label">IBAN</label><input className="input" value={form.IBAN} onChange={(e) => set('IBAN', e.target.value)} /></div>
            <div><label className="label">Bank Branch</label><input className="input" value={form.BankBranch} onChange={(e) => set('BankBranch', e.target.value)} /></div>
          </div>
        </section>
      )}

      <div className="flex justify-end gap-2 pt-2 border-t border-slate-200 dark:border-slate-800">
        <Button type="button" variant="secondary" onClick={onCancel}>Cancel</Button>
        <Button type="submit" disabled={saving}>{saving ? 'Saving…' : isEdit ? 'Save Changes' : 'Create Account'}</Button>
      </div>

      <AccountTreePicker
        open={parentPicker}
        onClose={() => setParentPicker(false)}
        onSelect={(acc) => { setParentPicker(false); if (acc) set('ParentAccountID', acc.AccountID); }}
        title="Select Parent Account"
      />
    </form>
  );
}

/* ------------------------------------------------------------------ */
/* Account details (view mode of the right panel)                      */
/* ------------------------------------------------------------------ */
function AccountDetails({ detail, onEdit, photoUrl }) {
  const a = detail.account;
  if (!a) return null;
  const Row = ({ label, value }) => (
    (value !== undefined && value !== null && value !== '') ? (
      <div className="flex justify-between gap-3 py-1 text-sm">
        <span className="text-slate-400 flex-shrink-0">{label}</span>
        <span className="text-right font-medium break-words">{value}</span>
      </div>
    ) : null
  );
  return (
    <div className="space-y-4">
      <div className="flex items-center gap-3">
        {photoUrl
          ? <img src={photoUrl} alt="" className="w-14 h-14 rounded-xl object-cover border border-slate-200 dark:border-slate-700" />
          : <div className="w-14 h-14 rounded-xl bg-slate-100 dark:bg-slate-800 flex items-center justify-center text-slate-400 text-xl">🏦</div>}
        <div className="min-w-0">
          <div className="font-mono text-xs text-slate-400">{a.Code}</div>
          <div className="font-bold text-lg leading-tight truncate">{a.Title}</div>
        </div>
      </div>

      <div>
        <Row label="Group" value={<Badge variant={TYPE_VARIANT[a.AccountType]}>{a.AccountType}</Badge>} />
        <Row label="Account Type" value={a.IsControl ? 'Control Account' : 'Detail Account'} />
        <Row label="Book Type" value={a.BookType} />
        <Row label="Branch" value={a.BranchName || 'All Branches'} />
        <Row label="Status" value={a.IsDeleted ? <Badge variant="danger">Deleted</Badge> : a.IsActive ? <Badge variant="success">Active</Badge> : <Badge variant="neutral">Inactive</Badge>} />
        <Row label="Knock Off" value={a.KnockOff ? 'Enabled (Bill Wise)' : '—'} />
        <Row label="Parent" value={a.ParentCode ? `${a.ParentCode} · ${a.ParentTitle}` : '—'} />
        {detail.tags?.length > 0 && <Row label="Tags" value={detail.tags.map((t) => <Badge key={t} variant="neutral">{t}</Badge>)} />}
      </div>

      <div>
        <h4 className="text-xs font-semibold uppercase tracking-wide text-slate-400 mb-1">General</h4>
        <Row label="Description" value={a.Description} />
        <Row label="Reference No" value={a.ReferenceNo} />
      </div>

      <div>
        <h4 className="text-xs font-semibold uppercase tracking-wide text-slate-400 mb-1">Contact</h4>
        <Row label="Address" value={a.Address} />
        <Row label="Phone" value={a.Phone} />
        <Row label="WhatsApp" value={a.Whatsapp} />
        <Row label="Telephone" value={a.Telephone} />
        <Row label="Fax" value={a.Fax} />
        <Row label="Email" value={a.Email} />
      </div>

      <div>
        <h4 className="text-xs font-semibold uppercase tracking-wide text-slate-400 mb-1">Identification</h4>
        <Row label="CNIC" value={a.CNIC} />
        <Row label="NTN" value={a.NTN} />
        <Row label="STRN" value={a.STRN} />
      </div>

      {a.BookType === 'Bank Book' && (
        <div>
          <h4 className="text-xs font-semibold uppercase tracking-wide text-slate-400 mb-1">Bank Information</h4>
          <Row label="Bank Name" value={a.BankName} />
          <Row label="Account Title" value={a.BankAccountTitle} />
          <Row label="Account Number" value={a.BankAccountNo} />
          <Row label="IBAN" value={a.IBAN} />
          <Row label="Bank Branch" value={a.BankBranch} />
        </div>
      )}
    </div>
  );
}

/* ================================================================== */
/* Main COA screen: left tree + right details/form                     */
/* ================================================================== */
export default function ChartOfAccountsPage() {
  const { tag } = useParams();
  const toast = useToast();
  const { user } = useAuth();
  const isSuperAdmin = user?.isSuperAdmin === true;
  const listRef = useRef(null);

  const [rows, setRows] = useState([]);
  const [branches, setBranches] = useState([]);
  const [loading, setLoading] = useState(true);
  const [query, setQuery] = useState('');
  const [collapsed, setCollapsed] = useState(new Set());

  const [selectedId, setSelectedId] = useState(null);
  const [selected, setSelected] = useState(null);
  const [detailsLoading, setDetailsLoading] = useState(false);
  const [mode, setMode] = useState('empty');          // empty | view | add | edit
  const [form, setForm] = useState({ ...EMPTY_FORM, Code: '', ParentCode: '', ParentTitle: '' });
  const [nextCodePreview, setNextCodePreview] = useState('');
  const [photoFile, setPhotoFile] = useState(null);
  const [photoPreview, setPhotoPreview] = useState(null);
  const [saving, setSaving] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await api.get('/finance/coa', { params: { tag: tag || undefined } });
      setRows(res.data.data || []);
    } catch (err) { toast.error('Failed to load chart of accounts'); }
    finally { setLoading(false); }
  }, [tag, toast]);

  useEffect(() => { load(); setMode('empty'); setSelected(null); setSelectedId(null); }, [load]);
  useEffect(() => { setQuery(''); setCollapsed(new Set()); }, [tag]);
  useEffect(() => {
    // graceful: users without branches.view simply get the All Branches option
    api.get('/branches').then((r) => setBranches(r.data.data || [])).catch(() => setBranches([]));
  }, [isSuperAdmin]);

  const byId = useMemo(() => new Map(rows.map((r) => [r.AccountID, r])), [rows]);
  const childrenOf = useMemo(() => {
    const m = new Map();
    for (const a of rows) {
      const k = a.ParentAccountID || 0;
      if (!m.has(k)) m.set(k, []);
      m.get(k).push(a);
    }
    return m;
  }, [rows]);

  const hasChildren = useCallback((id) => childrenOf.has(id) && childrenOf.get(id).length > 0, [childrenOf]);

  /* -------- global search: whole COA, case-insensitive, ancestor reveal -------- */
  const searchHits = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return null;
    const hits = new Set();
    for (const a of rows) {
      if (
        String(a.Code || '').toLowerCase().includes(q) ||
        String(a.Title || '').toLowerCase().includes(q) ||
        String(a.Description || '').toLowerCase().includes(q) ||
        String(a.ReferenceNo || '').toLowerCase().includes(q)
      ) hits.add(a.AccountID);
    }
    const keep = new Set();
    for (const id of hits) {
      let cur = byId.get(id);
      while (cur) { keep.add(cur.AccountID); cur = cur.ParentAccountID ? byId.get(cur.ParentAccountID) : null; }
    }
    return keep;
  }, [query, rows, byId]);

  /* -------- visible rows (respects collapse; search shows hits + ancestors) -------- */
  const visibleRows = useMemo(() => {
    const out = [];
    const walk = (parentId, depth) => {
      for (const a of childrenOf.get(parentId) || []) {
        if (searchHits) {
          // search mode: show only matching accounts and the ancestor chain
          if (!searchHits.has(a.AccountID)) continue;
          out.push({ ...a, depth });
          walk(a.AccountID, depth + 1);
        } else {
          out.push({ ...a, depth });
          if (!collapsed.has(a.AccountID)) walk(a.AccountID, depth + 1);
        }
      }
    };
    walk(0, 0);
    return out;
  }, [childrenOf, collapsed, searchHits]);

  const anyExpanded = useMemo(
    () => rows.some((a) => hasChildren(a.AccountID) && !collapsed.has(a.AccountID)),
    [rows, collapsed, hasChildren]
  );

  const toggleNode = (id) => setCollapsed((c) => {
    const n = new Set(c);
    if (n.has(id)) n.delete(id); else n.add(id);
    return n;
  });

  const toggleAll = () => {
    if (anyExpanded) {
      setCollapsed(new Set(rows.filter((a) => hasChildren(a.AccountID)).map((a) => a.AccountID)));
    } else {
      setCollapsed(new Set());
    }
  };

  /* -------- selection + details -------- */
  const select = useCallback(async (row) => {
    setSelectedId(row.AccountID);
    setMode('view');
    setDetailsLoading(true);
    setPhotoPreview(null);
    setPhotoFile(null);
    try {
      const res = await api.get(`/finance/coa/${row.AccountID}`);
      setSelected(res.data.data);
    } catch (err) { toast.error('Failed to load account details'); }
    finally { setDetailsLoading(false); }
  }, [toast]);

  /* -------- add / edit -------- */
  const startAdd = useCallback(async (parentRow) => {
    const parent = parentRow || (selectedId ? byId.get(selectedId) : null);
    if (!parent) {
      setForm({ ...EMPTY_FORM, Code: '', ParentAccountID: '', ParentCode: '', ParentTitle: '' });
      setNextCodePreview('');
      setMode('add');
      setSelected(null); setSelectedId(null); setPhotoFile(null); setPhotoPreview(null);
      return;
    }
    try {
      const res = await api.get('/finance/coa/next-code', { params: { parentId: parent.AccountID } });
      if (!res.data.data.CanAddChild) {
        toast.error('The selected account is at the deepest COA level — no child can be added under it.');
        return;
      }
      setForm({
        ...EMPTY_FORM,
        ParentAccountID: parent.AccountID,
        ParentCode: parent.Code, ParentTitle: parent.Title,
        BranchID: parent.BranchID || '',
      });
      setNextCodePreview(res.data.data.NextCode);
      setMode('add');
      setSelected(null); setSelectedId(parent.AccountID); setPhotoFile(null); setPhotoPreview(null);
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Failed to prepare the form'); }
  }, [selectedId, byId, toast]);

  const startEdit = useCallback(() => {
    if (!selected) return;
    const a = selected.account;
    setForm({
      ...EMPTY_FORM,
      Code: a.Code, Title: a.Title,
      ParentAccountID: a.ParentAccountID, ParentCode: a.ParentCode, ParentTitle: a.ParentTitle,
      IsControl: !!a.IsControl, KnockOff: !!a.KnockOff,
      BookType: a.BookType || '', BranchID: a.BranchID || '', IsActive: !!a.IsActive,
      Description: a.Description || '', ReferenceNo: a.ReferenceNo || '',
      Address: a.Address || '', Phone: a.Phone || '', Whatsapp: a.Whatsapp || '', Telephone: a.Telephone || '',
      Fax: a.Fax || '', Email: a.Email || '', Cnic: a.CNIC || '', Ntn: a.NTN || '', Strn: a.STRN || '',
      BankName: a.BankName || '', BankAccountTitle: a.BankAccountTitle || '', BankAccountNo: a.BankAccountNo || '',
      IBAN: a.IBAN || '', BankBranch: a.BankBranch || '',
      Tags: selected.tags || [],
    });
    setPhotoPreview(a.photoDataUrl || null);
    setPhotoFile(null);
    setMode('edit');
  }, [selected]);

  const save = async () => {
    if (!form.Title.trim()) return toast.error('Account name is required');
    if (!isEdit && !form.ParentAccountID) return toast.error('Select a parent account');
    setSaving(true);
    try {
      const payload = {
        Title: form.Title.trim(),
        ParentAccountID: form.ParentAccountID || undefined,
        IsControl: !!form.IsControl,
        KnockOff: !!form.KnockOff,
        BookType: form.BookType || null,
        BranchID: form.BranchID ? Number(form.BranchID) : null,
        IsActive: !!form.IsActive,
        Description: form.Description || null,
        ReferenceNo: form.ReferenceNo || null,
        Address: form.Address || null,
        Phone: form.Phone || null,
        Whatsapp: form.Whatsapp || null,
        Telephone: form.Telephone || null,
        Fax: form.Fax || null,
        Email: form.Email || null,
        Cnic: form.Cnic || null,
        Ntn: form.Ntn || null,
        Strn: form.Strn || null,
        BankName: form.BankName || null,
        BankAccountTitle: form.BankAccountTitle || null,
        BankAccountNo: form.BankAccountNo || null,
        IBAN: form.IBAN || null,
        BankBranch: form.BankBranch || null,
        Tags: form.Tags,
      };
      let accountId;
      if (mode === 'edit') {
        accountId = selected.account.AccountID;
        await api.put(`/finance/coa/${accountId}`, payload);
      } else {
        const res = await api.post('/finance/coa', payload);
        accountId = res.data.data.AccountID;
      }
      if (photoFile) {
        const fd = new FormData();
        fd.append('Photo', photoFile);
        await api.post(`/finance/coa/${accountId}/photo`, fd);
      }
      toast.success(mode === 'edit' ? 'Account updated' : 'Account created');
      await load();
      const res = await api.get(`/finance/coa/${accountId}`);
      setSelected(res.data.data);
      setSelectedId(accountId);
      setMode('view');
      setPhotoFile(null);
      setPhotoPreview(res.data.data.account.photoDataUrl || null);
    } catch (err) {
      toast.error(err.response?.data?.error?.message || 'Save failed');
    } finally { setSaving(false); }
  };

  const doDelete = async () => {
    if (!deleteTarget) return;
    try {
      await api.delete(`/finance/coa/${deleteTarget.AccountID}`);
      toast.success('Account deleted');
      if (selectedId === deleteTarget.AccountID) { setSelected(null); setSelectedId(null); setMode('empty'); }
      setDeleteTarget(null);
      load();
    } catch (err) {
      const msg = err.response?.data?.error?.message || 'Delete failed';
      toast.error(
        /transactions/i.test(msg)
          ? 'This account has accounting history and cannot be deleted. Deactivate it instead to keep it out of new vouchers.'
          : msg
      );
      setDeleteTarget(null);
    }
  };

  /* -------- export + print -------- */
  const buildHierarchical = () => {
    const out = [];
    const walk = (parentId, depth) => {
      for (const a of childrenOf.get(parentId) || []) {
        out.push({ ...a, depth });
        walk(a.AccountID, depth + 1);
      }
    };
    walk(0, 0);
    return out;
  };

  const doExport = () => {
    const flat = buildHierarchical();
    exportToCSV(
      flat.map((a) => ({
        Code: a.Code,
        Name: `${'    '.repeat(a.depth)}${a.Title}`,
        ParentCode: a.ParentCode || '',
        ParentName: a.ParentTitle || '',
        AccountType: a.IsControl ? 'Control Account' : 'Detail Account',
        Group: a.AccountType,
        BookType: a.BookType || '',
        Branch: a.BranchName || 'All Branches',
        Status: a.IsActive ? 'Active' : 'Inactive',
      })),
      'chart-of-accounts.csv',
      [
        { key: 'Code', label: 'Account Code' }, { key: 'Name', label: 'Account Name' },
        { key: 'ParentCode', label: 'Parent Code' }, { key: 'ParentName', label: 'Parent Name' },
        { key: 'AccountType', label: 'Account Type' }, { key: 'Group', label: 'Group' },
        { key: 'BookType', label: 'Book Type' }, { key: 'Branch', label: 'Branch' },
        { key: 'Status', label: 'Status' },
      ]
    );
  };

  const printRows = buildHierarchical();

  /* -------- render -------- */
  return (
    <div className="space-y-4">
      <PageHeader
        title={`Chart of Accounts${tag ? ` — ${tag} accounts` : ''}`}
        subtitle="Hierarchy, codes and account profiles. Only Detail accounts can receive postings."
        actions={
          <div className="flex gap-2 no-print">
            <Button variant="ghost" onClick={doExport}>Export</Button>
            <Button variant="secondary" onClick={printPage}>Print</Button>
          </div>
        }
      />

      <div className="grid grid-cols-1 xl:grid-cols-5 gap-4">
        {/* ---------------- LEFT: tree + actions ---------------- */}
        <div className={`xl:col-span-3 space-y-3 ${mode === 'add' || mode === 'edit' ? 'hidden xl:block' : ''}`}>
          <div className="card p-3 flex flex-wrap gap-2 items-center no-print">
            <Button onClick={() => startAdd(selectedId ? byId.get(selectedId) : null)}>
              + Add Account
            </Button>
            <Can perm="finance.coa">
              <Button variant="secondary" disabled={!selectedId || mode === 'edit'} onClick={startEdit}>Edit</Button>
              <Button variant="danger" disabled={!selectedId} onClick={() => setDeleteTarget(byId.get(selectedId))}>Delete</Button>
            </Can>
            <Button variant="ghost" onClick={() => { load(); if (selectedId) select({ AccountID: selectedId }); }}>Refresh</Button>
            <Button variant="secondary" onClick={toggleAll}>{anyExpanded ? 'Collapse All' : 'Expand All'}</Button>
            <input
              className="input flex-1 min-w-48"
              placeholder="Search code, name, description, reference…"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
          </div>

          <div className="card overflow-hidden">
            {loading ? <div className="p-8"><Spinner /></div> : (
              <div className="table-wrap max-h-[70vh] overflow-y-auto" ref={listRef}>
                <table className="table text-sm">
                  <thead className="sticky top-0 z-10">
                    <tr>
                      <th>Account Code</th>
                      <th>Account Name</th>
                      <th>Type</th>
                      <th>Book Type</th>
                      <th>Branch</th>
                      <th>Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {visibleRows.length === 0 && (
                      <tr><td colSpan={6} className="text-center text-slate-400 py-8">
                        {searchHits && searchHits.size === 0 ? 'No accounts match the search.' : 'No accounts'}
                      </td></tr>
                    )}
                    {visibleRows.map((a) => {
                      const isSel = a.AccountID === selectedId;
                      return (
                        <tr key={a.AccountID}
                          onClick={() => select(a)}
                          className={`cursor-pointer ${isSel ? 'bg-brand-50 dark:bg-brand-950/40' : ''}`}>
                          <td className="font-mono text-xs whitespace-nowrap">
                            <span style={{ display: 'inline-block', width: a.depth * 14 }}></span>
                            {hasChildren(a.AccountID) ? (
                              <button className="mr-1 text-slate-400 hover:text-slate-700 font-bold"
                                onClick={(e) => { e.stopPropagation(); toggleNode(a.AccountID); }}>
                                {collapsed.has(a.AccountID) ? '+' : '−'}
                              </button>
                            ) : <span className="inline-block w-3"></span>}
                            {a.Code}
                          </td>
                          <td className={a.IsControl ? 'font-medium' : ''}>
                            <span className="truncate">{a.Title}</span>
                            {a.KnockOff === 1 && <Badge variant="info">KO</Badge>}
                          </td>
                          <td>{a.IsControl ? <Badge variant="neutral">Control</Badge> : <Badge variant="info">Detail</Badge>}</td>
                          <td>{a.BookType || '—'}</td>
                          <td>{a.BranchName || 'All'}</td>
                          <td>{a.IsActive ? <Badge variant="success">Active</Badge> : <Badge variant="neutral">Inactive</Badge>}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        </div>

        {/* ---------------- RIGHT: details / universal form ---------------- */}
        <div className={`xl:col-span-2 ${mode === 'add' || mode === 'edit' ? '' : 'hidden xl:block'}`}>
          <div className="card p-4 xl:sticky xl:top-20 max-h-[80vh] overflow-y-auto">
            {mode === 'empty' && (
              <div className="text-center text-slate-400 py-16">
                <div className="text-3xl mb-2">🗂️</div>
                Select an account to view its details,<br />or click <span className="font-medium">+ Add Account</span>.
              </div>
            )}

            {mode === 'view' && (
              detailsLoading ? <Spinner /> : selected ? (
                <>
                  <div className="flex justify-end gap-2 mb-3 no-print">
                    <Can perm="finance.coa">
                      <Button onClick={startEdit}>Edit</Button>
                    </Can>
                  </div>
                  <AccountDetails detail={selected} onEdit={startEdit} photoUrl={selected.account.photoDataUrl} />
                </>
              ) : null
            )}

            {(mode === 'add' || mode === 'edit') && (
              <>
                <div className="flex items-center justify-between mb-3">
                  <h3 className="font-bold">{mode === 'edit' ? `Edit ${form.Code}` : 'Add Account'}</h3>
                  <label className="text-sm no-print">
                    <span className="text-slate-400 mr-2">Photo</span>
                    <input type="file" accept="image/*" className="text-xs"
                      onChange={(e) => {
                        const f = e.target.files[0] || null;
                        setPhotoFile(f);
                        setPhotoPreview(f ? URL.createObjectURL(f) : null);
                      }} />
                  </label>
                </div>
                {photoPreview && (
                  <img src={photoPreview} alt="" className="w-20 h-20 rounded-xl object-cover mb-3 border border-slate-200 dark:border-slate-700" />
                )}
                <AccountForm
                  mode={mode}
                  form={form}
                  setForm={setForm}
                  nextCodePreview={nextCodePreview}
                  branches={branches}
                  saving={saving}
                  onSubmit={save}
                  onCancel={() => {
                    if (mode === 'edit' && selected) { setMode('view'); setPhotoFile(null); setPhotoPreview(selected.account.photoDataUrl || null); }
                    else setMode('empty');
                  }}
                />
              </>
            )}
          </div>
        </div>
      </div>

      {/* print report */}
      <div className="hidden print:block">
        <div className="print-area">
          <PrintHeader title="Chart of Accounts" subtitle={tag ? `${tag} accounts` : 'Complete account hierarchy'} />
          <table className="table">
            <thead><tr><th>Code</th><th>Account Name</th><th>Type</th><th>Book Type</th><th>Branch</th><th>Status</th></tr></thead>
            <tbody>
              {printRows.map((a) => (
                <tr key={a.AccountID}>
                  <td className="font-mono">{a.Code}</td>
                  <td><span style={{ display: 'inline-block', width: a.depth * 16 }} />{a.Title}</td>
                  <td>{a.IsControl ? 'Control' : 'Detail'}</td>
                  <td>{a.BookType || '—'}</td>
                  <td>{a.BranchName || 'All Branches'}</td>
                  <td>{a.IsActive ? 'Active' : 'Inactive'}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      <ConfirmDialog
        open={!!deleteTarget}
        onClose={() => setDeleteTarget(null)}
        onConfirm={doDelete}
        title="Delete account"
        message={`Delete account ${deleteTarget?.Code} — ${deleteTarget?.Title}? Accounts with accounting history or child accounts cannot be deleted and can be deactivated instead.`}
        confirmLabel="Delete"
        danger
      />
    </div>
  );
}
