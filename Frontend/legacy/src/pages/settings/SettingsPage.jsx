import { useEffect, useState, useCallback } from 'react';
import api from '../../services/api';
import { useToast } from '../../context/ToastContext';
import { useTheme } from '../../context/ThemeContext';
import { formatDate } from '../../utils/format';
import Spinner from '../../components/common/Spinner';
import Button from '../../components/common/Button';

export default function SettingsPage() {
  const toast = useToast();
  const { theme, setTheme } = useTheme();
  const [settings, setSettings] = useState({});
  const [categories, setCategories] = useState({});
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await api.get('/settings');
      setSettings(res.data.data.map);
      // keep each key's original category so saves never re-categorize keys
      setCategories(Object.fromEntries(res.data.data.items.map((i) => [i.Key, i.Category || 'general'])));
    } catch (err) { toast.error('Failed to load settings'); }
    finally { setLoading(false); }
  }, []);

  useEffect(() => { load(); }, [load]);

  const set = (k, v) => setSettings((s) => ({ ...s, [k]: v }));

  const save = async () => {
    setSaving(true);
    try {
      const items = Object.entries(settings).map(([key, value]) => ({
        key, value, category: categories[key] || 'general',
      }));
      await api.put('/settings/bulk', { items });
      toast.success('Settings saved');
    } catch (err) { toast.error('Save failed'); }
    finally { setSaving(false); }
  };

  if (loading) return <Spinner size="lg" className="mt-20" />;

  return (
    <div className="max-w-3xl mx-auto space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Settings</h1>
        <Button onClick={save} disabled={saving}>{saving ? 'Saving…' : 'Save Changes'}</Button>
      </div>

      <div className="card p-6 space-y-4">
        <h3 className="text-sm font-semibold uppercase tracking-wide text-slate-500">Gym Information</h3>
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          <Field label="Gym Name" value={settings.GymName || ''} onChange={(v) => set('GymName', v)} />
          <Field label="Phone" value={settings.GymPhone || ''} onChange={(v) => set('GymPhone', v)} />
          <Field label="Email" value={settings.GymEmail || ''} onChange={(v) => set('GymEmail', v)} />
          <Field label="Address" value={settings.GymAddress || ''} onChange={(v) => set('GymAddress', v)} span={2} />
        </div>
      </div>

      <div className="card p-6 space-y-4">
        <h3 className="text-sm font-semibold uppercase tracking-wide text-slate-500">Finance</h3>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
          <Field label="Currency" value={settings.Currency || 'PKR'} onChange={(v) => set('Currency', v)} />
          <Field label="Currency Symbol" value={settings.CurrencySymbol || 'Rs'} onChange={(v) => set('CurrencySymbol', v)} />
          <Field label="Tax %" value={settings.TaxPercent || '0'} onChange={(v) => set('TaxPercent', v)} />
          <Field label="Late Fee Amount" value={settings.LateFeeAmount || '0'} onChange={(v) => set('LateFeeAmount', v)} />
        </div>
      </div>

      <div className="card p-6 space-y-4">
        <h3 className="text-sm font-semibold uppercase tracking-wide text-slate-500">Appearance</h3>
        <div>
          <label className="label">Default Theme</label>
          <div className="flex gap-2">
            <button onClick={() => setTheme('light')} className={`px-4 py-2 rounded-lg border ${theme === 'light' ? 'bg-brand-600 text-white border-brand-600' : 'border-slate-300 dark:border-slate-700'}`}>☀️ Light</button>
            <button onClick={() => setTheme('dark')} className={`px-4 py-2 rounded-lg border ${theme === 'dark' ? 'bg-brand-600 text-white border-brand-600' : 'border-slate-300 dark:border-slate-700'}`}>🌙 Dark</button>
          </div>
          <p className="text-xs text-slate-500 mt-2">Theme is stored in your browser. Each user can choose their preference.</p>
        </div>
      </div>

      <div className="card p-6 space-y-2">
        <h3 className="text-sm font-semibold uppercase tracking-wide text-slate-500">Developer Information</h3>
        <div className="text-sm text-slate-600 dark:text-slate-300">
          <div className="font-semibold text-slate-800 dark:text-slate-100">{settings.DeveloperName || 'Contoura Labs'}</div>
          <div><a href={`mailto:${settings.DeveloperEmail}`} className="text-brand-600 hover:underline">{settings.DeveloperEmail}</a></div>
          <div><a href={`https://wa.me/${(settings.DeveloperPhone || '').replace(/[^0-9]/g, '')}`} target="_blank" rel="noreferrer" className="text-brand-600 hover:underline">{settings.DeveloperPhone}</a></div>
          <div><a href={settings.DeveloperWebsite} target="_blank" rel="noreferrer" className="text-brand-600 hover:underline">{settings.DeveloperWebsite}</a></div>
        </div>
      </div>
    </div>
  );
}

function Field({ label, value, onChange, span = 1 }) {
  return (
    <div className={span === 2 ? 'md:col-span-2' : ''}>
      <label className="label">{label}</label>
      <input className="input" value={value} onChange={(e) => onChange(e.target.value)} />
    </div>
  );
}
