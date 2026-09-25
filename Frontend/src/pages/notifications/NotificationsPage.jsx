import { useEffect, useState, useCallback } from 'react';
import api from '../../services/api';
import { useToast } from '../../context/ToastContext';
import PageHeader from '../../components/common/PageHeader';
import Button from '../../components/common/Button';
import Spinner from '../../components/common/Spinner';
import { timeAgo } from '../../utils/format';

const TYPE_ICONS = {
  membership_expiry: '⏰', payment_due: '💳', birthday: '🎂', equipment_maintenance: '🔧', default: 'ℹ',
};

export default function NotificationsPage() {
  const toast = useToast();
  const [rows, setRows] = useState([]);
  const [loading, setLoading] = useState(true);
  const [unreadOnly, setUnreadOnly] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const res = await api.get('/notifications', { params: { unreadOnly: unreadOnly ? 'true' : undefined, pageSize: 100 } });
      setRows(res.data.data);
    } catch (err) { toast.error('Failed to load notifications'); }
    finally { setLoading(false); }
  }, [unreadOnly]);

  useEffect(() => { load(); }, [load]);

  const markRead = async (id) => {
    try { await api.post(`/notifications/${id}/read`); load(); }
    catch (err) { toast.error('Failed'); }
  };

  const markAllRead = async () => {
    try { await api.post('/notifications/read-all'); toast.success('All marked as read'); load(); }
    catch (err) { toast.error('Failed'); }
  };

  const remove = async (id) => {
    try { await api.delete(`/notifications/${id}`); load(); }
    catch (err) { toast.error('Failed'); }
  };

  return (
    <div className="space-y-4">
      <PageHeader title="Notifications" subtitle={`${rows.length} item${rows.length !== 1 ? 's' : ''}`}
        actions={
          <div className="flex gap-2 items-center">
            <label className="flex items-center gap-2 text-sm cursor-pointer">
              <input type="checkbox" checked={unreadOnly} onChange={(e) => setUnreadOnly(e.target.checked)} />
              Unread only
            </label>
            <Button variant="secondary" onClick={markAllRead}>Mark all read</Button>
          </div>
        } />

      <div className="card overflow-hidden">
        {loading ? <div className="p-8 flex justify-center"><Spinner /></div> : (
          <div className="divide-y divide-slate-100 dark:divide-slate-800">
            {rows.length === 0 && <div className="text-center text-slate-400 py-12">No notifications</div>}
            {rows.map((n) => (
              <div key={n.NotificationID} className={`p-4 flex items-start gap-3 ${!n.IsRead ? 'bg-blue-50/50 dark:bg-blue-900/10' : ''}`}>
                <div className="w-10 h-10 rounded-full bg-slate-100 dark:bg-slate-800 flex items-center justify-center text-xl flex-shrink-0">
                  {TYPE_ICONS[n.Type] || TYPE_ICONS.default}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="font-medium">{n.Title}</span>
                    {!n.IsRead && <span className="w-2 h-2 bg-blue-500 rounded-full"></span>}
                  </div>
                  <p className="text-sm text-slate-600 dark:text-slate-400 mt-0.5">{n.Message}</p>
                  <div className="text-xs text-slate-400 mt-1">{timeAgo(n.CreatedAt)}</div>
                </div>
                <div className="flex gap-2 text-xs">
                  {!n.IsRead && <button onClick={() => markRead(n.NotificationID)} className="text-brand-600 hover:underline">Mark read</button>}
                  <button onClick={() => remove(n.NotificationID)} className="text-red-600 hover:underline">Delete</button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
