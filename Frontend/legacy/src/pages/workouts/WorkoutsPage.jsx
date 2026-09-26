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

export default function WorkoutsPage() {
  const toast = useToast();
  const [rows, setRows] = useState([]);
  const [trainers, setTrainers] = useState([]);
  const [members, setMembers] = useState([]);
  const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false);
  const [detailModal, setDetailModal] = useState(null);
  const [detail, setDetail] = useState(null);
  const [form, setForm] = useState({ TrainerID: '', MemberID: '', Title: '', DayOfWeek: '', StartDate: '', EndDate: '', Notes: '', Items: [{ Exercise: '', Sets: '', Reps: '', Weight: '', RestPeriod: '', Notes: '' }] });

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [w, t, m] = await Promise.all([
        api.get('/workouts'),
        api.get('/staff/trainers'),
        api.get('/members', { params: { pageSize: 200 } }),
      ]);
      setRows(w.data.data);
      setTrainers(t.data.data);
      setMembers(m.data.data);
    } catch (err) { toast.error('Failed to load workout plans'); }
    finally { setLoading(false); }
  }, []);

  useEffect(() => { load(); }, [load]);

  const openNew = () => {
    setForm({ TrainerID: trainers[0]?.TrainerID || '', MemberID: members[0]?.MemberID || '', Title: '', DayOfWeek: '', StartDate: '', EndDate: '', Notes: '', Items: [{ Exercise: '', Sets: '', Reps: '', Weight: '', RestPeriod: '', Notes: '' }] });
    setModalOpen(true);
  };

  const addItem = () => setForm((f) => ({ ...f, Items: [...f.Items, { Exercise: '', Sets: '', Reps: '', Weight: '', RestPeriod: '', Notes: '' }] }));
  const removeItem = (i) => setForm((f) => ({ ...f, Items: f.Items.filter((_, idx) => idx !== i) }));
  const setItem = (i, k, v) => setForm((f) => ({ ...f, Items: f.Items.map((it, idx) => idx === i ? { ...it, [k]: v } : it) }));

  const save = async (e) => {
    e.preventDefault();
    try {
      const payload = {
        ...form,
        TrainerID: Number(form.TrainerID),
        MemberID: Number(form.MemberID),
        Items: form.Items.filter((i) => i.Exercise),
      };
      await api.post('/workouts', payload);
      toast.success('Workout plan created'); setModalOpen(false); load();
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Save failed'); }
  };

  const viewDetail = async (id) => {
    try {
      const res = await api.get(`/workouts/${id}`);
      setDetail(res.data.data);
      setDetailModal(rows.find((r) => r.PlanID === id));
    } catch (err) { toast.error('Failed to load plan'); }
  };

  const remove = async (id) => {
    if (!confirm('Delete this plan?')) return;
    try { await api.delete(`/workouts/${id}`); toast.success('Deleted'); load(); }
    catch (err) { toast.error('Failed'); }
  };

  if (loading) return <Spinner size="lg" className="mt-12" />;

  return (
    <div className="space-y-4">
      <PageHeader title="Workout Plans" subtitle={`${rows.length} plans`}
        actions={<Can perm="workouts.add"><Button onClick={openNew}>+ New Plan</Button></Can>} />

      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {rows.map((p) => (
          <div key={p.PlanID} className="card p-5">
            <div className="flex items-start justify-between">
              <div>
                <div className="font-semibold">{p.Title}</div>
                <div className="text-xs text-slate-500 mt-1">{p.DayOfWeek || 'Any day'}</div>
              </div>
            </div>
            <div className="mt-3 text-sm space-y-1">
              <div><span className="text-slate-500">Member:</span> <Link to={`/members/${p.MemberID}`} className="text-brand-600 hover:underline">{p.MemberName}</Link></div>
              <div><span className="text-slate-500">Trainer:</span> {p.TrainerName}</div>
              <div><span className="text-slate-500">Period:</span> {p.StartDate ? formatDate(p.StartDate) : '—'} → {p.EndDate ? formatDate(p.EndDate) : '—'}</div>
            </div>
            <div className="flex gap-2 mt-4 pt-3 border-t border-slate-100 dark:border-slate-800">
              <Button size="sm" variant="secondary" onClick={() => viewDetail(p.PlanID)}>View</Button>
              <Can perm="workouts.delete"><Button size="sm" variant="ghost" className="text-red-600" onClick={() => remove(p.PlanID)}>Delete</Button></Can>
            </div>
          </div>
        ))}
        {rows.length === 0 && <div className="col-span-full text-center text-slate-400 py-8">No workout plans yet.</div>}
      </div>

      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title="New Workout Plan" size="xl">
        <form onSubmit={save} className="space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div><label className="label">Title *</label><input className="input" value={form.Title} onChange={(e) => setForm({...form, Title: e.target.value})} required placeholder="e.g. Push Day" /></div>
            <div><label className="label">Day of Week</label><select className="input" value={form.DayOfWeek} onChange={(e) => setForm({...form, DayOfWeek: e.target.value})}><option value="">Any</option><option>Daily</option><option>Monday</option><option>Tuesday</option><option>Wednesday</option><option>Thursday</option><option>Friday</option><option>Saturday</option><option>Sunday</option></select></div>
            <div><label className="label">Trainer *</label><select className="input" value={form.TrainerID} onChange={(e) => setForm({...form, TrainerID: e.target.value})} required>{trainers.map((t) => <option key={t.TrainerID} value={t.TrainerID}>{t.StaffName}</option>)}</select></div>
            <div><label className="label">Member *</label><select className="input" value={form.MemberID} onChange={(e) => setForm({...form, MemberID: e.target.value})} required>{members.map((m) => <option key={m.MemberID} value={m.MemberID}>{m.FullName} ({m.Code})</option>)}</select></div>
            <div><label className="label">Start Date</label><input type="date" className="input" value={form.StartDate} onChange={(e) => setForm({...form, StartDate: e.target.value})} /></div>
            <div><label className="label">End Date</label><input type="date" className="input" value={form.EndDate} onChange={(e) => setForm({...form, EndDate: e.target.value})} /></div>
            <div className="col-span-2"><label className="label">Notes</label><textarea className="input" rows="2" value={form.Notes} onChange={(e) => setForm({...form, Notes: e.target.value})} /></div>
          </div>

          <div>
            <div className="flex items-center justify-between mb-2">
              <h4 className="font-semibold">Exercises</h4>
              <Button type="button" size="sm" variant="secondary" onClick={addItem}>+ Add Exercise</Button>
            </div>
            <div className="space-y-2">
              {form.Items.map((it, i) => (
                <div key={i} className="grid grid-cols-12 gap-2 items-center p-2 rounded-lg bg-slate-50 dark:bg-slate-800/50">
                  <input className="input col-span-4" placeholder="Exercise name *" value={it.Exercise} onChange={(e) => setItem(i, 'Exercise', e.target.value)} />
                  <input className="input col-span-1" type="number" placeholder="Sets" value={it.Sets} onChange={(e) => setItem(i, 'Sets', e.target.value)} />
                  <input className="input col-span-2" placeholder="Reps" value={it.Reps} onChange={(e) => setItem(i, 'Reps', e.target.value)} />
                  <input className="input col-span-2" placeholder="Weight" value={it.Weight} onChange={(e) => setItem(i, 'Weight', e.target.value)} />
                  <input className="input col-span-2" placeholder="Rest" value={it.RestPeriod} onChange={(e) => setItem(i, 'RestPeriod', e.target.value)} />
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
              <div><span className="text-slate-500">Day:</span> {detail.plan?.DayOfWeek || 'Any'}</div>
              <div><span className="text-slate-500">Period:</span> {detail.plan?.StartDate ? formatDate(detail.plan.StartDate) : '—'} → {detail.plan?.EndDate ? formatDate(detail.plan.EndDate) : '—'}</div>
            </div>
            {detail.plan?.Notes && <p className="text-sm text-slate-600 dark:text-slate-300 italic">{detail.plan.Notes}</p>}
            <div className="table-wrap">
              <table className="table">
                <thead><tr><th>#</th><th>Exercise</th><th>Sets</th><th>Reps</th><th>Weight</th><th>Rest</th></tr></thead>
                <tbody>
                  {detail.items?.map((it, i) => (
                    <tr key={it.ItemID}>
                      <td>{i+1}</td>
                      <td className="font-medium">{it.Exercise}</td>
                      <td>{it.Sets || '—'}</td>
                      <td>{it.Reps || '—'}</td>
                      <td>{it.Weight || '—'}</td>
                      <td>{it.RestPeriod || '—'}</td>
                    </tr>
                  ))}
                  {(!detail.items || detail.items.length === 0) && <tr><td colSpan={6} className="text-center text-slate-400 py-4">No exercises</td></tr>}
                </tbody>
              </table>
            </div>
          </div>
        )}
      </Modal>
    </div>
  );
}
