import { useCallback, useEffect, useState } from 'react';
import api from '../../../services/api';
import { useToast } from '../../../context/ToastContext';
import PageHeader from '../../../components/common/PageHeader';
import Button from '../../../components/common/Button';
import Can from '../../../components/common/Can';
import Spinner from '../../../components/common/Spinner';
import ConfirmDialog from '../../../components/common/ConfirmDialog';

const TABS = [
  { key: 'company', label: 'Company' },
  { key: 'accounting', label: 'Accounting' },
  { key: 'numbering', label: 'Voucher Numbering' },
  { key: 'reports', label: 'Report Settings' },
  { key: 'structure', label: 'COA Structure' },
  { key: 'mappings', label: 'Account Mappings' },
];

const MAPPING_TYPES = [
  { type: 'PaymentMethod', hint: 'SourceKey = PaymentMethods.MethodID (1=Cash, 2=Bank, 3=Card, 4=JazzCash, 5=EasyPaisa)' },
  { type: 'IncomeCategory', hint: 'SourceKey = IncomeCategories.CatID (1..4)' },
  { type: 'ExpenseCategory', hint: 'SourceKey = expense category name (Salary, Rent, …)' },
  { type: 'Payroll', hint: 'Singleton — default expense account for salary payments' },
  { type: 'MembershipRevenue', hint: 'Singleton — default revenue account for membership fees' },
  { type: 'DefaultCash', hint: 'Singleton — default cash account' },
  { type: 'DefaultBank', hint: 'Singleton — default bank account' },
];

function Field({ label, value, onChange, span = 1, type = 'text' }) {
  return (
    <div className={span === 2 ? 'md:col-span-2' : ''}>
      <label className="label">{label}</label>
      <input type={type} className="input" value={value ?? ''} onChange={(e) => onChange(e.target.value)} />
    </div>
  );
}

export default function FinanceDefaultsPage() {
  const toast = useToast();
  const [tab, setTab] = useState('company');
  const [parsed, setParsed] = useState({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const [structure, setStructure] = useState({ levels: [] });
  const [structureDirty, setStructureDirty] = useState(false);
  const [structureConfirm, setStructureConfirm] = useState(false);

  const [mappings, setMappings] = useState([]);
  const [mappingType, setMappingType] = useState('PaymentMethod');
  const [mapSourceKey, setMapSourceKey] = useState('');
  const [mapAccountId, setMapAccountId] = useState('');
  const [selectorAccounts, setSelectorAccounts] = useState([]);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [defRes, structRes] = await Promise.all([
        api.get('/finance/defaults'),
        api.get('/finance/coa/structure'),
      ]);
      setParsed(defRes.data.data.parsed || {});
      setStructure({
        levels: structRes.data.data.levels || [],
        info: structRes.data.data.info || {},
      });
    } catch (err) { toast.error('Failed to load finance defaults'); }
    finally { setLoading(false); }
  }, [toast]);

  useEffect(() => { load(); }, [load]);

  const loadMappings = useCallback((type) => {
    api.get('/finance/mappings', { params: { type } })
      .then((r) => setMappings(r.data.data || []))
      .catch(() => setMappings([]));
  }, []);
  useEffect(() => { if (tab === 'mappings') loadMappings(mappingType); }, [tab, mappingType, loadMappings]);
  useEffect(() => {
    if (tab === 'mappings') {
      api.get('/finance/coa/selectors', { params: { limit: 500 } })
        .then((r) => setSelectorAccounts(r.data.data || []))
        .catch(() => setSelectorAccounts([]));
    }
  }, [tab]);

  const saveSection = async (key, value, confirmText) => {
    setSaving(true);
    try {
      await api.put('/finance/defaults', { Key: key, Value: value });
      toast.success('Saved');
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Save failed'); }
    finally { setSaving(false); }
  };

  if (loading) return <Spinner size="lg" className="mt-20" />;

  const company = parsed.FinanceCompany || {};
  const accounting = parsed.FinanceAccounting || {};
  const numbering = parsed.FinanceVoucherNumbering || {};
  const reports = parsed.FinanceReports || {};

  const setSection = (key, field, value) => {
    if (key === 'company') setParsed((p) => ({ ...p, FinanceCompany: { ...company, [field]: value } }));
    if (key === 'accounting') setParsed((p) => ({ ...p, FinanceAccounting: { ...accounting, [field]: value } }));
    if (key === 'numbering') setParsed((p) => ({ ...p, FinanceVoucherNumbering: { ...numbering, [field]: value } }));
    if (key === 'reports') setParsed((p) => ({ ...p, FinanceReports: { ...reports, [field]: value } }));
  };

  const saveStructure = () => {
    const total = structure.levels.reduce((s, l) => s + Number(l.Digits || 0), 0);
    if (total > 12) return toast.error('Total digits cannot exceed 12');
    setStructureConfirm(true);
  };

  const doSaveStructure = async () => {
    setStructureConfirm(false);
    setSaving(true);
    try {
      await api.put('/finance/coa/structure', { Levels: structure.levels.map((l) => Number(l.Digits)) });
      toast.success('COA structure updated');
      setStructureDirty(false);
      load();
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Save failed'); }
    finally { setSaving(false); }
  };

  const setMapping = async () => {
    try {
      await api.put('/finance/mappings', {
        MappingType: mappingType,
        SourceKey: mapSourceKey || null,
        AccountID: Number(mapAccountId),
      });
      toast.success('Mapping saved');
      setMapSourceKey(''); setMapAccountId('');
      loadMappings(mappingType);
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Failed'); }
  };

  const deleteMapping = async (m) => {
    try {
      await api.delete(`/finance/mappings/${m.MappingID}`);
      loadMappings(mappingType);
    } catch (err) { toast.error('Failed'); }
  };

  return (
    <div className="space-y-4">
      <PageHeader title="Finance Defaults" subtitle="Company profile, accounting policy, voucher numbering, report layout, COA structure and module mappings." />

      <div className="card p-1 flex flex-wrap gap-1 no-print">
        {TABS.map((t) => (
          <button key={t.key} onClick={() => setTab(t.key)}
            className={`px-4 py-2 rounded-lg text-sm font-medium ${tab === t.key ? 'bg-brand-600 text-white' : 'text-slate-600 dark:text-slate-300 hover:bg-slate-100 dark:hover:bg-slate-800'}`}>
            {t.label}
          </button>
        ))}
      </div>

      <div className="card p-6 space-y-4 max-w-3xl">
        {tab === 'company' && (
          <>
            <h3 className="text-sm font-semibold uppercase tracking-wide text-slate-500">Company Information</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              <Field label="Company Name" value={company.name} onChange={(v) => setSection('company', 'name', v)} />
              <Field label="Phone" value={company.phone} onChange={(v) => setSection('company', 'phone', v)} />
              <Field label="Email" value={company.email} onChange={(v) => setSection('company', 'email', v)} />
              <Field label="Website" value={company.website} onChange={(v) => setSection('company', 'website', v)} />
              <Field label="NTN" value={company.ntn} onChange={(v) => setSection('company', 'ntn', v)} />
              <Field label="STRN" value={company.strn} onChange={(v) => setSection('company', 'strn', v)} />
              <Field label="Logo Path" value={company.logoPath} onChange={(v) => setSection('company', 'logoPath', v)} />
              <Field label="Address" value={company.address} onChange={(v) => setSection('company', 'address', v)} span={2} />
            </div>
            <Can perm="finance.settings">
              <Button disabled={saving} onClick={() => saveSection('FinanceCompany', company)}>Save Company Settings</Button>
            </Can>
          </>
        )}

        {tab === 'accounting' && (
          <>
            <h3 className="text-sm font-semibold uppercase tracking-wide text-slate-500">Accounting Policy</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              <div>
                <label className="label">Accounting Type</label>
                <select className="input" value={accounting.accountingType || 'Accrual'} onChange={(e) => setSection('accounting', 'accountingType', e.target.value)}>
                  <option>Accrual</option><option>Cash</option>
                </select>
              </div>
              <div>
                <label className="label">Outstanding Documents Mode</label>
                <select className="input" value={(Number(accounting.billWise) === 1) ? 'billwise' : 'fifo'} onChange={(e) => setSection('accounting', 'billWise', e.target.value === 'billwise' ? 1 : 0)}>
                  <option value="billwise">Bill Wise / Knock Off (match by bill reference)</option>
                  <option value="fifo">FIFO (oldest document first)</option>
                </select>
                <p className="text-xs text-slate-400 mt-1">Drives customer & vendor aging allocation. Both modes are fully implemented.</p>
              </div>
              <Field label="Fiscal Year Policy" value={accounting.fiscalYearPolicy} onChange={(v) => setSection('accounting', 'fiscalYearPolicy', v)} />
              <Field label="Accounting Period Policy" value={accounting.periodPolicy} onChange={(v) => setSection('accounting', 'periodPolicy', v)} />
              <Field label="Default Currency" value={accounting.defaultCurrency} onChange={(v) => setSection('accounting', 'defaultCurrency', v)} />
              <Field label="Rounding Digits" value={accounting.roundingDigits} onChange={(v) => setSection('accounting', 'roundingDigits', Number(v))} />
              <Field label="Retained Earnings Account ID" value={accounting.retainedEarningsAccountId} onChange={(v) => setSection('accounting', 'retainedEarningsAccountId', Number(v))} />
              <div className="flex items-center gap-2 pt-6">
                <input type="checkbox" id="branchacc" checked={Number(accounting.branchAccounting) === 1} onChange={(e) => setSection('accounting', 'branchAccounting', e.target.checked ? 1 : 0)} />
                <label htmlFor="branchacc" className="text-sm">Branch accounting (vouchers are branch-scoped)</label>
              </div>
            </div>
            <Can perm="finance.settings">
              <Button disabled={saving} onClick={() => saveSection('FinanceAccounting', accounting)}>Save Accounting Settings</Button>
            </Can>
          </>
        )}

        {tab === 'numbering' && (
          <>
            <h3 className="text-sm font-semibold uppercase tracking-wide text-slate-500">Voucher Numbering</h3>
            <p className="text-sm text-slate-500">
              Format: <span className="font-mono">PREFIX-DATESEQ</span> — e.g. CRV-010920260001. Sequences are per voucher type, branch and financial year, and are concurrency-safe.
            </p>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              <div>
                <label className="label">Date component format</label>
                <select className="input" value={numbering.dateFormat || 'ddMMyyyy'} onChange={(e) => setSection('numbering', 'dateFormat', e.target.value)}>
                  <option value="ddMMyyyy">ddMMyyyy (01092026)</option>
                  <option value="yyyyMMdd">yyyyMMdd (20260901)</option>
                  <option value="ddMMyy">ddMMyy (010926)</option>
                </select>
              </div>
              <Field label="Sequence digits" value={numbering.seqDigits} onChange={(v) => setSection('numbering', 'seqDigits', Number(v) || 4)} />
            </div>
            <p className="text-xs text-slate-400">Prefixes are configured per voucher type and lock automatically after the first voucher of that type is posted.</p>
            <Can perm="finance.settings">
              <Button disabled={saving} onClick={() => saveSection('FinanceVoucherNumbering', numbering)}>Save Numbering Settings</Button>
            </Can>
          </>
        )}

        {tab === 'reports' && (
          <>
            <h3 className="text-sm font-semibold uppercase tracking-wide text-slate-500">Report Settings</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
              <Field label="Report Footer" value={reports.footer} onChange={(v) => setSection('reports', 'footer', v)} span={2} />
              <Field label="Date Format" value={reports.dateFormat} onChange={(v) => setSection('reports', 'dateFormat', v)} />
              <Field label="Currency Display" value={reports.currencyDisplay} onChange={(v) => setSection('reports', 'currencyDisplay', v)} />
              <Field label="Default Layout" value={reports.defaultLayout} onChange={(v) => setSection('reports', 'defaultLayout', v)} />
              <div className="flex items-center gap-6 pt-6">
                <label className="flex items-center gap-2 text-sm">
                  <input type="checkbox" checked={Number(reports.printCompanyInfo) === 1} onChange={(e) => setSection('reports', 'printCompanyInfo', e.target.checked ? 1 : 0)} />
                  Print company information
                </label>
                <label className="flex items-center gap-2 text-sm">
                  <input type="checkbox" checked={Number(reports.showLogo) === 1} onChange={(e) => setSection('reports', 'showLogo', e.target.checked ? 1 : 0)} />
                  Show logo
                </label>
              </div>
            </div>
            <Can perm="finance.settings">
              <Button disabled={saving} onClick={() => saveSection('FinanceReports', reports)}>Save Report Settings</Button>
            </Can>
          </>
        )}

        {tab === 'structure' && (
          <>
            <h3 className="text-sm font-semibold uppercase tracking-wide text-slate-500">Chart of Accounts Structure</h3>
            <p className="text-sm text-slate-500">
              Define digits per level (max 7 levels, 12 total digits). The structure is locked once changing it would invalidate existing account codes.
            </p>
            <div className="space-y-2">
              {structure.levels.map((l, i) => (
                <div key={l.LevelNo} className="flex items-center gap-3">
                  <span className="text-sm w-20">Level {l.LevelNo}</span>
                  <input type="number" min="1" max="6" className="input w-24 no-spinner"
                    value={l.Digits}
                    onChange={(e) => {
                      const levels = structure.levels.map((x, xi) => (xi === i ? { ...x, Digits: e.target.value } : x));
                      setStructure({ ...structure, levels });
                      setStructureDirty(true);
                    }} />
                  <span className="text-xs text-slate-400">digits</span>
                </div>
              ))}
            </div>
            <div className="text-sm">
              Total digits: <span className={`font-bold ${structure.levels.reduce((s, l) => s + Number(l.Digits || 0), 0) > 12 ? 'text-red-600' : ''}`}>
                {structure.levels.reduce((s, l) => s + Number(l.Digits || 0), 0)}
              </span> / 12
              {structure.info?.HasAccounts === 1 && <span className="ml-3 text-amber-600">Accounts exist — only conforming changes are accepted.</span>}
            </div>
            <Can perm="finance.settings">
              <Button disabled={saving || !structureDirty} onClick={saveStructure}>Save Structure</Button>
            </Can>
          </>
        )}

        {tab === 'mappings' && (
          <>
            <h3 className="text-sm font-semibold uppercase tracking-wide text-slate-500">Source → Account Mappings</h3>
            <p className="text-sm text-slate-500">Future modules (fees, payroll, expenses, inventory) post through the central engine using these configurable mappings.</p>
            <div className="flex flex-wrap gap-2">
              {MAPPING_TYPES.map((m) => (
                <button key={m.type} onClick={() => setMappingType(m.type)}
                  className={`px-3 py-1.5 rounded-lg text-sm font-medium ${mappingType === m.type ? 'bg-brand-600 text-white' : 'bg-slate-100 dark:bg-slate-800 text-slate-600 dark:text-slate-300'}`}>
                  {m.type}
                </button>
              ))}
            </div>
            <p className="text-xs text-slate-400">{MAPPING_TYPES.find((m) => m.type === mappingType)?.hint}</p>
            <div className="flex flex-wrap gap-2 items-end">
              <div>
                <label className="label">Source Key (blank for singleton)</label>
                <input className="input w-48" value={mapSourceKey} onChange={(e) => setMapSourceKey(e.target.value)} />
              </div>
              <div className="flex-1 min-w-64">
                <label className="label">Target Account</label>
                <select className="input" value={mapAccountId} onChange={(e) => setMapAccountId(e.target.value)}>
                  <option value="">— select detail account —</option>
                  {selectorAccounts.map((a) => <option key={a.AccountID} value={a.AccountID}>{a.Code} · {a.Title}</option>)}
                </select>
              </div>
              <Can perm="finance.settings"><Button onClick={setMapping} disabled={!mapAccountId}>Save Mapping</Button></Can>
            </div>
            <div className="table-wrap">
              <table className="table text-sm">
                <thead><tr><th>Mapping Type</th><th>Source Key</th><th>Account</th><th></th></tr></thead>
                <tbody>
                  {mappings.length === 0 && <tr><td colSpan={4} className="text-center text-slate-400 py-6">No mappings for this type</td></tr>}
                  {mappings.map((m) => (
                    <tr key={m.MappingID}>
                      <td>{m.MappingType}</td>
                      <td className="font-mono text-xs">{m.SourceKey ?? '(default)'}</td>
                      <td>{m.AccountCode} · {m.AccountTitle}</td>
                      <td><Can perm="finance.settings"><button className="text-red-500 hover:underline" onClick={() => deleteMapping(m)}>Delete</button></Can></td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          </>
        )}
      </div>

      <ConfirmDialog
        open={structureConfirm}
        onClose={() => setStructureConfirm(false)}
        onConfirm={doSaveStructure}
        title="Change COA structure"
        message="Changing the structure affects how new account codes are validated. The change is rejected if it would invalidate any existing account code. Continue?"
        confirmLabel="Save structure"
      />
    </div>
  );
}
