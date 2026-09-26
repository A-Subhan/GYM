import { useEffect, useState, useCallback } from 'react';
import api from '../../services/api';
import { useToast } from '../../context/ToastContext';
import { useAuth } from '../../context/AuthContext';
import PageHeader from '../../components/common/PageHeader';
import Button from '../../components/common/Button';
import Modal from '../../components/common/Modal';
import Spinner from '../../components/common/Spinner';
import { formatDateTime } from '../../utils/format';

export default function BackupPage() {
  const toast = useToast();
  const { user } = useAuth();
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(true);
  const [creating, setCreating] = useState(false);
  const [restoreModal, setRestoreModal] = useState(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await api.get('/backup');
      setRows(res.data.data);
    } catch (err) { toast.error('Failed to load backups'); }
    finally { setLoading(false); }
  }, []);

  useEffect(() => { load(); }, [load]);

  const createBackup = async () => {
    if (!confirm('Create a new database backup? This may take 10-30 seconds.')) return;
    setCreating(true);
    try {
      const res = await api.post('/backup');
      toast.success(`Backup created: ${res.data.data.fileName}`);
      load();
    } catch (err) { toast.error('Backup failed: ' + (err.response?.data?.error?.message || err.message)); }
    finally { setCreating(false); }
  };

  const download = (fileName) => {
    const token = localStorage.getItem('accessToken');
    // Open in new tab with auth header via fetch + blob
    api.get(`/backup/download/${fileName}`, { responseType: 'blob' })
      .then((res) => {
        const url = URL.createObjectURL(res.data);
        const a = document.createElement('a');
        a.href = url; a.download = fileName;
        document.body.appendChild(a); a.click(); document.body.removeChild(a);
        URL.revokeObjectURL(url);
      })
      .catch(() => toast.error('Download failed'));
  };

  const confirmRestore = async () => {
    if (!restoreModal) return;
    try {
      await api.post('/backup/restore', { fileName: restoreModal.fileName });
      toast.success('Database restored. Please log in again.');
      setTimeout(() => window.location.href = '/login', 2000);
    } catch (err) { toast.error('Restore failed: ' + (err.response?.data?.error?.message || err.message)); }
    finally { setRestoreModal(null); }
  };

  const remove = async (fileName) => {
    if (!confirm('Delete this backup file?')) return;
    try { await api.delete(`/backup/${fileName}`); toast.success('Deleted'); load(); }
    catch (err) { toast.error('Failed'); }
  };

  if (!user?.isSuperAdmin) {
    return (
      <div className="card p-8 text-center">
        <div className="text-4xl mb-3">🔒</div>
        <h2 className="text-xl font-semibold">Super Admin Only</h2>
        <p className="text-slate-500 mt-2">Database backup and restore is restricted to Super Admin accounts.</p>
      </div>
    );
  }

  const fmtSize = (bytes) => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
  };

  return (
    <div className="space-y-4">
      <PageHeader title="Database Backup & Restore" subtitle="Super Admin only · Use before major changes"
        actions={<Button onClick={createBackup} disabled={creating}>{creating ? 'Creating…' : '+ Create Backup'}</Button>} />

      <div className="card p-4 bg-amber-50 dark:bg-amber-900/20 border-amber-200 dark:border-amber-800">
        <div className="flex gap-2 text-sm text-amber-800 dark:text-amber-200">
          <span>⚠️</span>
          <div>
            <strong>Warning:</strong> Restoring a backup will overwrite the entire database and log out all users. Make sure no one is actively using the system before restoring. Always create a fresh backup before restoring.
          </div>
        </div>
      </div>

      {loading ? <Spinner size="lg" className="mt-12" /> : (
        <div className="card overflow-hidden">
          <div className="table-wrap">
            <table className="table">
              <thead><tr><th>File Name</th><th>Size</th><th>Created</th><th></th></tr></thead>
              <tbody>
                {rows.length === 0 && <tr><td colSpan={4} className="text-center text-slate-400 py-8">No backups yet. Click "Create Backup" to make your first one.</td></tr>}
                {rows.map((b) => (
                  <tr key={b.fileName}>
                    <td className="font-mono text-sm">{b.fileName}</td>
                    <td>{fmtSize(b.size)}</td>
                    <td>{formatDateTime(b.createdAt)}</td>
                    <td>
                      <div className="flex gap-2 text-sm">
                        <button onClick={() => download(b.fileName)} className="text-brand-600 hover:underline">Download</button>
                        <button onClick={() => setRestoreModal(b)} className="text-amber-600 hover:underline">Restore</button>
                        <button onClick={() => remove(b.fileName)} className="text-red-600 hover:underline">Delete</button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      <Modal open={!!restoreModal} onClose={() => setRestoreModal(null)} title="Confirm Restore" size="sm">
        <p className="text-slate-600 dark:text-slate-300 mb-4">
          You are about to restore the database from <strong className="font-mono">{restoreModal?.fileName}</strong>.
          This will overwrite all current data and log out everyone. Are you absolutely sure?
        </p>
        <div className="flex justify-end gap-2">
          <Button variant="secondary" onClick={() => setRestoreModal(null)}>Cancel</Button>
          <Button variant="danger" onClick={confirmRestore}>Restore Now</Button>
        </div>
      </Modal>
    </div>
  );
}
