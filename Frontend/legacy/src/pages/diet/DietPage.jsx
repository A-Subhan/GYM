import { useEffect, useState, useCallback } from 'react';
import { Link } from 'react-router-dom';
import api from '../../services/api';
import { useToast } from '../../context/ToastContext';
import PageHeader from '../../components/common/PageHeader';
import Button from '../../components/common/Button';
import Modal from '../../components/common/Modal';
import Spinner from '../../components/common/Spinner';
import Can from '../../components/common/Can';
import { formatDate } from '../../utils/format';

const MEALS = ['Breakfast', 'Snack', 'Lunch', 'Pre-Workout', 'Dinner'];

export default function DietPage() {
  const toast = useToast();
  const [rows, setRows] = useState([]);
  const [trainers, setTrainers] = useState([]);
  const [members, setMembers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false);
  const [detailModal, setDetailModal] = useState(null);
  const [detail, setDetail] = useState(null);
  const [form, setForm] = useState({ TrainerID: '', MemberID: '', Title: '', StartDate: '', EndDate: '', Notes: '', Items: [{ Meal: 'Breakfast', Food: '', Calories: '', Protein: '', Carbs: '', Fat: '' }] });

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [d, t, m] = await Promise.all([
        api.get('/diet'),
        api.get('/staff/trainers'),
        api.get('/members', { params: { pageSize: 200 } }),
      ]);
      setRows(d.data.data);
      setTrainers(t.data.data);
      setMembers(m.data.data);
    } catch (err) { toast.error('Failed to load diet plans'); }
    finally { setLoading(false); }
  }, []);

  useEffect(() => { load(); }, [load]);

  const openNew = () => {
    setForm({ TrainerID: trainers[0]?.TrainerID || '', MemberID: members[0]?.MemberID || '', Title: '', StartDate: '', EndDate: '', Notes: '', Items: [{ Meal: 'Breakfast', Food: '', Calories: '', Protein: '', Carbs: '', Fat: '' }] });
    setModalOpen(true);
  };

  const addItem = () => setForm((f) => ({ ...f, Items: [...f.Items, { Meal: 'Breakfast', Food: '', Calories: '', Protein: '', Carbs: '', Fat: '' }] }));
  const removeItem = (i) => setForm((f) => ({ ...f, Items: f.Items.filter((_, idx) => idx !== i) }));
  const setItem = (i, k, v) => setForm((f) => ({ ...f, Items: f.Items.map((it, idx) => idx === i ? { ...it, [k]: v } : it) }));

  const save = async (e) => {
    e.preventDefault();
    try {
      const payload = { ...form, TrainerID: Number(form.TrainerID), MemberID: Number(form.MemberID), Items: form.Items.filter((i) => i.Food) };
      await api.post('/diet', payload);
      toast.success('Diet plan created'); setModalOpen(false); load();
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Save failed'); }
  };

  const viewDetail = async (id) => {
    try {
      const res = await api.get(`/diet/${id}`);
      setDetail(res.data.data);
      setDetailModal(rows.find((r) => r.PlanID === id));
    } catch (err) { toast.error('Failed to load plan'); }
  };

  const remove = async (id) => {
    if (!confirm('Delete this plan?')) return;
    try { await api.delete(`/diet/${id}`); toast.success('Deleted'); load(); }
    catch (err) { toast.error('Failed'); }
  };

  if (loading) return <Spinner size="lg" className="mt-12" />;

  const totalCalories = (items) => items?.reduce((s, i) => s + (Number(i.Calories) || 0), 0) || 0;
  const totalProtein = (items) => items?.reduce((s, i) => s + (Number(i.Protein) || 0), 0) || 0;

  return (
    <div className="space-y-4">
      <PageHeader title="Diet Plans" subtitle={`${rows.length} plans`}
        actions={<Can perm="diet.add"><Button onClick={openNew}>+ New Plan</Button></Can>} />

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {rows.map((p) => (
          <div key={p.PlanID} className="card p-5">
            <div className="font-semibold">{p.Title}</div>
            <div className="text-sm text-slate-500 mt-1">{p.TrainerName}</div>
            <div className="mt-3 text-sm space-y-1">
              <div><span className="text-slate-500">Member:</span> <Link to={`/members/${p.MemberID}`} className="text-brand-600 hover:underline">{p.MemberName}</Link></div>
              <div><span className="text-slate-500">Period:</span> {p.StartDate ? formatDate(p.StartDate) : '—'} → {p.EndDate ? formatDate(p.EndDate) : '—'}</div>
            </div>
            <div className="flex gap-2 mt-4 pt-3 border-t border-slate-100 dark:border-slate-800">
              <Button size="sm" variant="secondary" onClick={() => viewDetail(p.PlanID)}>View</Button>
              <Can perm="diet.delete"><Button size="sm" variant="ghost" className="text-red-600" onClick={() => remove(p.PlanID)}>Delete</Button></Can>
            </div>
          </div>
        ))}
        {rows.length === 0 && <div className="col-span-full text-center text-slate-400 py-8">No diet plans yet.</div>}
      </div>

      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title="New Diet Plan" size="xl">
        <form onSubmit={save} className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div><label className="label">Title *</label><input className="input" value={form.Title} onChange={(e) => setForm({...form, Title: e.target.value})} required placeholder="e.g. Cutting Diet 2000kcal" /></div>
            <div><label className="label">Trainer *</label><select className="input" value={form.TrainerID} onChange={(e) => setForm({...form, TrainerID: e.target.value})} required>{trainers.map((t) => <option key={t.TrainerID} value={t.TrainerID}>{t.StaffName}</option>)}</select></div>
            <div><label className="label">Member *</label><select className="input" value={form.MemberID} onChange={(e) => setForm({...form, MemberID: e.target.value})} required>{members.map((m) => <option key={m.MemberID} value={m.MemberID}>{m.FullName} ({m.Code})</option>)}</select></div>
            <div className="grid grid-cols-2 gap-2">
              <div><label className="label">Start</label><input type="date" className="input" value={form.StartDate} onChange={(e) => setForm({...form, StartDate: e.target.value})} /></div>
              <div><label className="label">End</label><input type="date" className="input" value={form.EndDate} onChange={(e) => setForm({...form, EndDate: e.target.value})} /></div>
            </div>
            <div className="col-span-2"><label className="label">Notes</label><textarea className="input" rows="2" value={form.Notes} onChange={(e) => setForm({...form, Notes: e.target.value})} /></div>
          </div>

          <div>
            <div className="flex items-center justify-between mb-2">
              <h4 className="font-semibold">Meals</h4>
              <Button type="button" size="sm" variant="secondary" onClick={addItem}>+ Add Meal</Button>
            </div>
            <div className="space-y-2">
              {form.Items.map((it, i) => (
                <div key={i} className="grid grid-cols-12 gap-2 items-center p-2 rounded-lg bg-slate-50 dark:bg-slate-800/50">
                  <select className="input col-span-2" value={it.Meal} onChange={(e) => setItem(i, 'Meal', e.target.value)}>{MEALS.map((m) => <option key={m}>{m}</option>)}</select>
                  <input className="input col-span-4" placeholder="Food description *" value={it.Food} onChange={(e) => setItem(i, 'Food', e.target.value)} />
                  <input className="input col-span-2" type="number" placeholder="Cal" value={it.Calories} onChange={(e) => setItem(i, 'Calories', e.target.value)} />
                  <input className="input col-span-1" type="number" placeholder="P" value={it.Protein} onChange={(e) => setItem(i, 'Protein', e.target.value)} />
                  <input className="input col-span-1" type="number" placeholder="C" value={it.Carbs} onChange={(e) => setItem(i, 'Carbs', e.target.value)} />
                  <input className="input col-span-1" type="number" placeholder="F" value={it.Fat} onChange={(e) => setItem(i, 'Fat', e.target.value)} />
                  <button type="button" onClick={() => removeItem(i)} className="text-red-500 hover:text-red-700 text-xl">×</button>
                </div>
              ))}
            </div>
          </div>

          <div className="flex justify-end gap-2 pt-2"><Button type="button" variant="secondary" onClick={() => setModalOpen(false)}>Cancel</Button><Button type="submit">Create Plan</Button></div>
        </form>
      </Modal>

      <Modal open={!!detailModal} onClose={() => setDetailModal(null)} title={detailModal?.Title} size="lg">
        {!detail ? <Spinner /> : (
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-2 text-sm">
              <div><span className="text-slate-500">Member:</span> {detail.plan?.MemberName}</div>
              <div><span className="text-slate-500">Trainer:</span> {detail.plan?.TrainerName}</div>
            </div>
            {detail.plan?.Notes && <p className="text-sm text-slate-600 dark:text-slate-300 italic">{detail.plan.Notes}</p>}
            <div className="flex gap-3 text-sm">
              <div className="px-3 py-1 rounded-lg bg-emerald-50 dark:bg-emerald-900/20 text-emerald-700 dark:text-emerald-300">Total Calories: <strong>{totalCalories(detail.items)}</strong></div>
              <div className="px-3 py-1 rounded-lg bg-blue-50 dark:bg-blue-900/20 text-blue-700 dark:text-blue-300">Protein: <strong>{totalProtein(detail.items)}g</strong></div>
            </div>
            <div className="table-wrap">
              <table className="table">
                <thead><tr><th>Meal</th><th>Food</th><th>Cal</th><th>P</th><th>C</th><th>F</th></tr></thead>
                <tbody>
                  {detail.items?.map((it) => (
                    <tr key={it.ItemID}>
                      <td><span className="badge-info">{it.Meal}</span></td>
                      <td className="font-medium">{it.Food}</td>
                      <td>{it.Calories || '—'}</td>
                      <td>{it.Protein ? `${it.Protein}g` : '—'}</td>
                      <td>{it.Carbs ? `${it.Carbs}g` : '—'}</td>
                      <td>{it.Fat ? `${it.Fat}g` : '—'}</td>
                    </tr>
                  ))}
                  {(!detail.items || detail.items.length === 0) && <tr><td colSpan={6} className="text-center text-slate-400 py-4">No meals</td></tr>}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </Modal>
    </div>
  );
}
