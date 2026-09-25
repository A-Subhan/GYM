import { useEffect, useState, useCallback } from 'react';
import api from '../../services/api';
import { useToast } from '../../context/ToastContext';
import PageHeader from '../../components/common/PageHeader';
import Button from '../../components/common/Button';
import Modal from '../../components/common/Modal';
import DataTable from '../../components/common/DataTable';
import { formatDate, formatCurrency } from '../../utils/format';
import { StatusBadge } from '../../components/common/Badge';
import Can from '../../components/common/Can';

const EMPTY_FORM = {
  BranchID: '',
  DepartmentID: '',
  FullName: '',
  FatherName: '',
  CNIC: '',
  Mobile: '',
  Email: '',
  Address: '',
  JoiningDate: new Date().toISOString().slice(0, 10),
  Designation: '',
  BaseSalary: '',
  Status: 'Active',
  Specialization: '',
  Experience: '',
};

/* salary input: digits + one decimal point only, capped at 9999999 */
const sanitizeSalary = (value) => {
  let v = String(value).replace(/[^0-9.]/g, '');
  const firstDot = v.indexOf('.');
  if (firstDot !== -1) {
    v = v.slice(0, firstDot + 1) + v.slice(firstDot + 1).replace(/\./g, '');
    v = v.slice(0, firstDot + 3); /* max 2 decimals */
  }
  return v;
};

export default function StaffPage() {
  const toast = useToast();
  const [rows, setRows] = useState([]);
  const [departments, setDepartments] = useState([]);
  const [designations, setDesignations] = useState([]);
  const [branches, setBranches] = useState([]);
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [deptFilter, setDeptFilter] = useState('');
  const [trainerFilter, setTrainerFilter] = useState('');
  const [tab, setTab] = useState('staff');
  const [attendance, setAttendance] = useState([]);
  const [leaves, setLeaves] = useState([]);
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState(EMPTY_FORM);

  useEffect(() => {
    const t = setTimeout(() => setDebouncedSearch(search), 400);
    return () => clearTimeout(t);
  }, [search]);

  const loadStaff = useCallback(async () => {
    setLoading(true);
    try {
      const res = await api.get('/staff', {
        params: {
          page,
          pageSize: 20,
          search: debouncedSearch || undefined,
          DepartmentID: deptFilter || undefined,
          Status: statusFilter || undefined,
          IsTrainer: trainerFilter === '' ? undefined : trainerFilter,
        },
      });
      setRows(res.data.data);
      setTotal(res.data.meta.total);
      setTotalPages(res.data.meta.totalPages);
    } catch (err) { toast.error('Failed to load staff'); }
    finally { setLoading(false); }
  }, [page, debouncedSearch, statusFilter, deptFilter, trainerFilter]);

  const loadExtras = useCallback(async () => {
    try {
      /* designation options come from the Master Files system */
      const [d, b, defRes, a, l] = await Promise.all([
        api.get('/staff/departments'),
        api.get('/branches').catch(() => ({ data: { data: [] } })),
        api.get('/masters/definitions').catch(() => ({ data: { data: [] } })),
        api.get('/staff/attendance/all'),
        api.get('/staff/leaves/all'),
      ]);
      setDepartments(d.data.data);
      setBranches(b.data.data);
      setAttendance(a.data.data);
      setLeaves(l.data.data);

      const designationDef = (defRes.data.data || []).find(
        (m) => m.Name.toLowerCase() === 'designation' && m.IsActive !== false
      );
      if (designationDef) {
        const itemsRes = await api.get(`/masters/${designationDef.MasterDefinitionID}/items`, {
          params: { pageSize: 200, status: 'active' },
        }).catch(() => ({ data: { data: [] } }));
        setDesignations((itemsRes.data.data || []).map((i) => ({ DesignationID: i.MasterItemID, Name: i.Name })));
      } else {
        setDesignations([]);
      }
    } catch (err) { /* silent */ }
  }, []);

  useEffect(() => { loadExtras(); }, [loadExtras]);
  useEffect(() => { if (tab === 'staff') loadStaff(); }, [loadStaff, tab]);

  const isTrainerDesignation = (name) =>
    String(name || '').toLowerCase().includes('trainer');

  const openNew = () => {
    setEditing(null);
    setForm({ ...EMPTY_FORM, DepartmentID: departments[0]?.DepartmentID || '' });
    setModalOpen(true);
  };
  const openEdit = (s) => {
    setEditing(s.StaffID);
    setForm({
      BranchID: s.BranchID || '',
      DepartmentID: s.DepartmentID || '',
      FullName: s.FullName || '',
      FatherName: s.FatherName || '',
      CNIC: s.CNIC || '',
      Mobile: s.Mobile || '',
      Email: s.Email || '',
      Address: s.Address || '',
      JoiningDate: s.JoiningDate ? s.JoiningDate.slice(0, 10) : '',
      Designation: s.Designation || '',
      BaseSalary: s.BaseSalary !== null && s.BaseSalary !== undefined ? String(s.BaseSalary) : '',
      Status: s.Status || 'Active',
      Specialization: s.Specialization || '',
      Experience: s.Experience || '',
    });
    setModalOpen(true);
  };

  const save = async (e) => {
    e.preventDefault();
    const salary = form.BaseSalary === '' ? 0 : Number(form.BaseSalary);
    if (Number.isNaN(salary) || salary < 0 || salary > 9999999) {
      toast.error('Salary must be a number up to 9999999');
      return;
    }
    try {
      const payload = {
        ...form,
        BranchID: form.BranchID ? Number(form.BranchID) : null,
        DepartmentID: Number(form.DepartmentID),
        BaseSalary: salary,
      };
      if (editing) await api.put(`/staff/${editing}`, payload);
      else await api.post('/staff', payload);
      toast.success('Saved');
      setModalOpen(false);
      loadStaff();
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Save failed'); }
  };

  const remove = async (s) => {
    if (!confirm(`Delete ${s.FullName}?`)) return;
    try { await api.delete(`/staff/${s.StaffID}`); toast.success('Deleted'); loadStaff(); }
    catch (err) { toast.error('Failed'); }
  };

  const approveLeave = async (id, status) => {
    try { await api.put(`/staff/leaves/${id}/status`, { Status: status }); toast.success(`Leave ${status.toLowerCase()}`); loadExtras(); }
    catch (err) { toast.error('Failed'); }
  };

  const columns = [
    { key: 'FullName', label: 'Name', render: (s) => (
      <div>
        <div className="font-medium">{s.FullName}</div>
        <div className="text-xs text-slate-400 font-mono">{s.StaffCode || `#${s.StaffID}`}</div>
      </div>
    ) },
    { key: 'DepartmentName', label: 'Department' },
    { key: 'Designation', label: 'Designation', render: (s) => s.Designation || <span className="text-slate-300 dark:text-slate-600">—</span> },
    { key: 'IsTrainer', label: 'Trainer', render: (s) => s.IsTrainer
      ? <span className="badge badge-success" title={s.Specialization || undefined}>Trainer{s.Specialization ? ` — ${s.Specialization}` : ''}</span>
      : <span className="text-slate-300 dark:text-slate-600">—</span> },
    { key: 'Mobile', label: 'Mobile' },
    { key: 'BaseSalary', label: 'Salary', render: (s) => formatCurrency(s.BaseSalary) },
    { key: 'JoiningDate', label: 'Joined', render: (s) => formatDate(s.JoiningDate) },
    { key: 'Status', label: 'Status', render: (s) => <StatusBadge status={s.Status} /> },
    { key: 'actions', label: '', render: (s) => (
      <div className="flex gap-2">
        <Can perm="staff.edit"><button onClick={() => openEdit(s)} className="text-brand-600 hover:underline text-sm">Edit</button></Can>
        <Can perm="staff.delete"><button onClick={() => remove(s)} className="text-red-600 hover:underline text-sm">Delete</button></Can>
      </div>
    ) },
  ];

  return (
    <div className="space-y-4">
      <PageHeader title="Staff" subtitle={`${total} total`}
        actions={<Can perm="staff.add"><Button onClick={openNew}>+ Add Staff</Button></Can>} />

      <div className="card overflow-hidden">
        <div className="flex border-b border-slate-200 dark:border-slate-800">
          {['staff','attendance','leaves'].map((t) => (
            <button key={t} onClick={() => setTab(t)} className={`px-5 py-3 text-sm font-medium border-b-2 capitalize ${tab === t ? 'border-brand-600 text-brand-600' : 'border-transparent text-slate-500 hover:text-slate-700'}`}>{t}</button>
          ))}
        </div>

        {tab === 'staff' && (
          <>
            <div className="p-4 flex flex-wrap gap-3 items-end">
              <div className="flex-1 min-w-[200px]"><input placeholder="Search name, code, CNIC, mobile…" value={search} onChange={(e) => { setSearch(e.target.value); setPage(1); }} className="input" /></div>
              <select value={trainerFilter} onChange={(e) => { setTrainerFilter(e.target.value); setPage(1); }} className="input w-44">
                <option value="">All Staff</option>
                <option value="true">Trainers only</option>
                <option value="false">Non-trainers</option>
              </select>
              <select value={deptFilter} onChange={(e) => { setDeptFilter(e.target.value); setPage(1); }} className="input w-44"><option value="">All Depts</option>{departments.map((d) => <option key={d.DepartmentID} value={d.DepartmentID}>{d.Name}</option>)}</select>
              <select value={statusFilter} onChange={(e) => { setStatusFilter(e.target.value); setPage(1); }} className="input w-40"><option value="">All Status</option><option>Active</option><option>OnLeave</option><option>Resigned</option><option>Terminated</option></select>
            </div>
            <DataTable columns={columns} rows={rows} loading={loading} pagination={{ page, totalPages, total }} onPageChange={setPage} />
          </>
        )}

        {tab === 'attendance' && (
          <div className="table-wrap">
            <table className="table">
              <thead><tr><th>Staff</th><th>Date</th><th>Check In</th><th>Check Out</th><th>Status</th></tr></thead>
              <tbody>
                {attendance.length === 0 && <tr><td colSpan={5} className="text-center text-slate-400 py-8">No attendance records</td></tr>}
                {attendance.slice(0, 50).map((a) => (
                  <tr key={a.StaffAttendanceID}>
                    <td className="font-medium">{a.StaffName}</td>
                    <td>{formatDate(a.Date)}</td>
                    <td>{a.CheckIn ? new Date(a.CheckIn).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }) : '—'}</td>
                    <td>{a.CheckOut ? new Date(a.CheckOut).toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' }) : '—'}</td>
                    <td><StatusBadge status={a.Status} /></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {tab === 'leaves' && (
          <div className="table-wrap">
            <table className="table">
              <thead><tr><th>Staff</th><th>Type</th><th>From</th><th>To</th><th>Reason</th><th>Status</th><th></th></tr></thead>
              <tbody>
                {leaves.length === 0 && <tr><td colSpan={7} className="text-center text-slate-400 py-8">No leave requests</td></tr>}
                {leaves.map((l) => (
                  <tr key={l.LeaveID}>
                    <td className="font-medium">{l.StaffName}</td>
                    <td>{l.LeaveType}</td>
                    <td>{formatDate(l.StartDate)}</td>
                    <td>{formatDate(l.EndDate)}</td>
                    <td className="max-w-xs truncate">{l.Reason || '—'}</td>
                    <td><StatusBadge status={l.Status} /></td>
                    <td>
                      {l.Status === 'Pending' && (
                        <div className="flex gap-2 text-xs">
                          <button onClick={() => approveLeave(l.LeaveID, 'Approved')} className="text-emerald-600 hover:underline">Approve</button>
                          <button onClick={() => approveLeave(l.LeaveID, 'Rejected')} className="text-red-600 hover:underline">Reject</button>
                        </div>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editing ? `Edit Staff` : 'New Staff'} size="lg">
        <form onSubmit={save} className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div><label className="label">Full Name *</label><input className="input" maxLength={50} value={form.FullName} onChange={(e) => setForm({...form, FullName: e.target.value})} required /></div>
            <div><label className="label">Father Name</label><input className="input" maxLength={50} value={form.FatherName} onChange={(e) => setForm({...form, FatherName: e.target.value})} /></div>
            <div><label className="label">CNIC</label><input className="input" value={form.CNIC} onChange={(e) => setForm({...form, CNIC: e.target.value})} /></div>
            <div><label className="label">Mobile</label><input className="input" value={form.Mobile} onChange={(e) => setForm({...form, Mobile: e.target.value})} /></div>
            <div><label className="label">Email</label><input type="email" className="input" value={form.Email} onChange={(e) => setForm({...form, Email: e.target.value})} /></div>
            <div><label className="label">Department *</label><select className="input" value={form.DepartmentID} onChange={(e) => setForm({...form, DepartmentID: e.target.value})} required>{departments.map((d) => <option key={d.DepartmentID} value={d.DepartmentID}>{d.Name}</option>)}</select></div>
            <div><label className="label">Designation *</label><select className="input" value={form.Designation} onChange={(e) => setForm({...form, Designation: e.target.value})} required>
              <option value="">— Select designation —</option>
              {designations.map((d) => <option key={d.DesignationID} value={d.Name}>{d.Name}</option>)}
              {/* keep a legacy/missing designation selectable while editing */}
              {editing && form.Designation && !designations.some((d) => d.Name === form.Designation) && (
                <option value={form.Designation}>{form.Designation}</option>
              )}
            </select></div>
            <div><label className="label">Branch *</label><select className="input" value={form.BranchID} onChange={(e) => setForm({...form, BranchID: e.target.value})}><option value="">— Select branch —</option>{branches.map((b) => <option key={b.BranchID} value={b.BranchID}>{b.Name}</option>)}</select></div>
            <div><label className="label">Joining Date *</label><input type="date" className="input" value={form.JoiningDate} onChange={(e) => setForm({...form, JoiningDate: e.target.value})} required /></div>
            <div><label className="label">Base Salary</label><input type="text" inputMode="decimal" className="input no-spinner" maxLength={11} value={form.BaseSalary} onChange={(e) => setForm({...form, BaseSalary: sanitizeSalary(e.target.value)})} placeholder="0.00" /></div>
            <div className="col-span-2"><label className="label">Address</label><input className="input" maxLength={200} value={form.Address} onChange={(e) => setForm({...form, Address: e.target.value})} /></div>
            <div><label className="label">Status</label><select className="input" value={form.Status} onChange={(e) => setForm({...form, Status: e.target.value})}><option>Active</option><option>OnLeave</option><option>Resigned</option><option>Terminated</option></select></div>
          </div>

          {isTrainerDesignation(form.Designation) && (
            <div className="border border-slate-200 dark:border-slate-700 rounded-lg p-3">
              <p className="text-xs text-slate-500 mb-3">Trainer designation — this staff member will be treated as a trainer in the software (selectable in the member form's trainer dropdown).</p>
              <div className="grid grid-cols-2 gap-3">
                <div><label className="label">Specialization</label><input className="input" value={form.Specialization} onChange={(e) => setForm({...form, Specialization: e.target.value})} placeholder="e.g. Strength & Conditioning" /></div>
                <div><label className="label">Experience</label><input className="input" value={form.Experience} onChange={(e) => setForm({...form, Experience: e.target.value})} placeholder="e.g. 5 years" /></div>
              </div>
              <p className="text-xs text-slate-500 mt-2">Members already assigned to this trainer keep their assignment while the designation stays Trainer.</p>
            </div>
          )}

          <div className="flex justify-end gap-2 pt-2"><Button type="button" variant="secondary" onClick={() => setModalOpen(false)}>Cancel</Button><Button type="submit">{editing ? 'Update' : 'Create'}</Button></div>
        </form>
      </Modal>
    </div>
  );
}
