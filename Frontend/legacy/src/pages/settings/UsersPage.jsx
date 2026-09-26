import { useEffect, useState, useCallback } from 'react';
import api from '../../services/api';
import { useToast } from '../../context/ToastContext';
import { useAuth } from '../../context/AuthContext';
import { formatDate } from '../../utils/format';
import Pagination from '../../components/common/Pagination';
import Spinner from '../../components/common/Spinner';
import Button from '../../components/common/Button';
import Modal from '../../components/common/Modal';
import { StatusBadge } from '../../components/common/Badge';

export default function UsersPage() {
  const toast = useToast();
  const { user: currentUser } = useAuth();
  const [rows, setRows] = useState([]);
  const [roles, setRoles] = useState([]);
  const [branches, setBranches] = useState([]);
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [total, setTotal] = useState(0);
  const [loading, setLoading] = useState(true);
  const [modalOpen, setModalOpen] = useState(false);
  const [editing, setEditing] = useState(null);
  const [form, setForm] = useState({ Username: '', Email: '', FullName: '', Password: '', RoleID: '', BranchID: '', Phone: '' });

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const [u, r, b] = await Promise.all([
        api.get('/users', { params: { page, pageSize: 20 } }),
        api.get('/users/meta/roles'),
        api.get('/branches').catch(() => ({ data: { data: [] } })),
      ]);
      setRows(u.data.data);
      setTotal(u.data.meta.total);
      setTotalPages(u.data.meta.totalPages);
      setRoles(r.data.data);
      setBranches(b.data.data);
      if (r.data.data[0]) setForm((f) => ({ ...f, RoleID: r.data.data[0].RoleID }));
    } catch (err) { toast.error('Failed to load users'); }
    finally { setLoading(false); }
  }, [page]);

  useEffect(() => { load(); }, [load]);

  const openNew = () => { setEditing(null); setForm({ Username: '', Email: '', FullName: '', Password: '', RoleID: roles[0]?.RoleID || '', BranchID: '', Phone: '' }); setModalOpen(true); };
  const openEdit = (u) => { setEditing(u.UserID); setForm({ Username: u.Username, Email: u.Email || '', FullName: u.FullName, Password: '', RoleID: u.RoleID, BranchID: u.BranchID || '', Phone: u.Phone || '' }); setModalOpen(true); };

  const save = async (e) => {
    e.preventDefault();
    try {
      if (editing) {
        const { Password, ...payload } = form;
        await api.put(`/users/${editing}`, payload);
        toast.success('User updated');
      } else {
        await api.post('/users', form);
        toast.success('User created');
      }
      setModalOpen(false); load();
    } catch (err) { toast.error(err.response?.data?.error?.message || 'Save failed'); }
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-bold">Users & Roles</h1>
        <Button onClick={openNew}>+ New User</Button>
      </div>

      <div className="card overflow-hidden">
        {loading ? <div className="p-8"><Spinner /></div> : (
          <div className="table-wrap">
            <table className="table">
              <thead><tr><th>Username</th><th>Full Name</th><th>Role</th><th>Branch</th><th>Last Login</th><th>Status</th><th></th></tr></thead>
              <tbody>
                {rows.map((u) => (
                  <tr key={u.UserID}>
                    <td className="font-medium">{u.Username}{u.UserID === currentUser?.userId && <span className="ml-2 text-xs text-brand-600">(you)</span>}</td>
                    <td>{u.FullName}</td>
                    <td><span className="badge-info">{u.RoleName}</span></td>
                    <td>{u.BranchName || '—'}</td>
                    <td>{u.LastLoginAt ? formatDate(u.LastLoginAt) : '—'}</td>
                    <td><StatusBadge status={u.IsActive ? 'Active' : 'Inactive'} /></td>
                    <td>{u.UserID !== 1 && <button onClick={() => openEdit(u)} className="text-brand-600 hover:underline text-sm">Edit</button>}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
        <div className="px-4"><Pagination page={page} totalPages={totalPages} total={total} onChange={setPage} /></div>
      </div>

      <Modal open={modalOpen} onClose={() => setModalOpen(false)} title={editing ? 'Edit User' : 'New User'}>
        <form onSubmit={save} className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <div><label className="label">Username *</label><input className="input" value={form.Username} onChange={(e) => setForm({...form, Username: e.target.value})} required disabled={!!editing} /></div>
            <div><label className="label">Full Name *</label><input className="input" value={form.FullName} onChange={(e) => setForm({...form, FullName: e.target.value})} required /></div>
            <div><label className="label">Email</label><input type="email" className="input" value={form.Email} onChange={(e) => setForm({...form, Email: e.target.value})} /></div>
            <div><label className="label">Phone</label><input className="input" value={form.Phone} onChange={(e) => setForm({...form, Phone: e.target.value})} /></div>
            <div><label className="label">Role *</label>
              <select className="input" value={form.RoleID} onChange={(e) => setForm({...form, RoleID: Number(e.target.value)})} required>
                {roles.map((r) => <option key={r.RoleID} value={r.RoleID}>{r.Name}</option>)}
              </select>
            </div>
            <div><label className="label">Branch</label>
              <select className="input" value={form.BranchID} onChange={(e) => setForm({...form, BranchID: e.target.value})}>
                <option value="">— None —</option>
                {branches.map((b) => <option key={b.BranchID} value={b.BranchID}>{b.Name}</option>)}
              </select>
            </div>
            {!editing && <div className="col-span-2"><label className="label">Password *</label><input type="password" className="input" value={form.Password} onChange={(e) => setForm({...form, Password: e.target.value})} required minLength="8" /></div>}
          </div>
          <div className="flex justify-end gap-2 pt-2"><Button type="button" variant="secondary" onClick={() => setModalOpen(false)}>Cancel</Button><Button type="submit">{editing ? 'Update' : 'Create'}</Button></div>
        </form>
      </Modal>
    </div>
  );
}
