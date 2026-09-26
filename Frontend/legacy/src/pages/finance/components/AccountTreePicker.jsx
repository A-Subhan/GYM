import { useEffect, useMemo, useState } from 'react';
import api from '../../../services/api';
import Modal from '../../../components/common/Modal';
import Badge from '../../../components/common/Badge';

/**
 * Chart of Accounts picker.
 * Shows the complete account hierarchy; ONLY active Detail accounts are
 * selectable (groups/controls are visible but disabled). Search matches
 * account code or name and keeps the matching branches expanded.
 * restrictBookType limits selection to accounts of that Book Type.
 */
export default function AccountTreePicker({ open, onClose, onSelect, restrictTag = null, restrictBookType = null, title = 'Select Account' }) {
  const [all, setAll] = useState([]);
  const [loading, setLoading] = useState(false);
  const [query, setQuery] = useState('');

  useEffect(() => {
    if (!open) return;
    setLoading(true);
    api.get('/finance/accounts-tree')
      .then((res) => setAll(res.data.data || []))
      .catch(() => setAll([]))
      .finally(() => setLoading(false));
  }, [open]);

  const tagsOf = (row) => (row.Tags ? String(row.Tags).split(',').filter(Boolean) : []);

  const matches = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return null;
    return new Set(
      all
        .filter((a) => a.Code.includes(q) || a.Title.toLowerCase().includes(q))
        .map((a) => a.AccountID)
    );
  }, [query, all]);

  // keep ancestors of matching nodes visible when searching
  const visible = useMemo(() => {
    if (!matches) return null;
    const byParent = new Map(all.map((a) => [a.AccountID, a]));
    const keep = new Set();
    for (const id of matches) {
      let cur = byParent.get(id);
      while (cur) { keep.add(cur.AccountID); cur = cur.ParentAccountID ? byParent.get(cur.ParentAccountID) : null; }
    }
    return keep;
  }, [matches, all]);

  const childrenOf = useMemo(() => {
    const map = new Map();
    for (const a of all) {
      const key = a.ParentAccountID || 0;
      if (!map.has(key)) map.set(key, []);
      map.get(key).push(a);
    }
    return map;
  }, [all]);

  const renderRows = (parentId, depth) => {
    const kids = (childrenOf.get(parentId) || []);
    return kids.flatMap((a) => {
      if (visible && !visible.has(a.AccountID)) return [];
      const selectable = a.IsControl === 0 && a.IsActive === true && a.IsDeleted === 0
        && (!restrictTag || tagsOf(a).includes(restrictTag))
        && (!restrictBookType || a.BookType === restrictBookType);
      const row = (
        <div
          key={a.AccountID}
          className={`flex items-center justify-between rounded-lg px-2 py-1.5 text-sm ${
            selectable ? 'hover:bg-slate-100 dark:hover:bg-slate-800 cursor-pointer' : 'opacity-50'
          }`}
          style={{ marginLeft: depth * 14 }}
          onClick={() => selectable && onSelect(a)}
        >
          <div className="flex items-center gap-2 min-w-0">
            <span className="font-mono text-xs text-slate-500">{a.Code}</span>
            <span className={`truncate ${a.IsControl ? 'font-medium text-slate-500 dark:text-slate-400' : 'text-slate-800 dark:text-slate-100'}`}>
              {a.Title}
            </span>
            {a.IsControl === 1 && <span className="text-[10px] uppercase tracking-wide text-slate-400">group</span>}
            {a.IsControl === 0 && a.KnockOff === 1 && <Badge variant="info">Knock Off</Badge>}
            {a.BookType && <Badge variant="neutral">{a.BookType}</Badge>}
            {!restrictTag && tagsOf(a).map((t) => <Badge key={t} variant="neutral">{t}</Badge>)}
          </div>
          {selectable && <span className="text-xs text-brand-600 font-medium flex-shrink-0">Select</span>}
        </div>
      );
      return [row, ...renderRows(a.AccountID, depth + 1)];
    });
  };

  return (
    <Modal open={open} onClose={onClose} title={title} size="lg">
      <div className="space-y-3">
        <input
          className="input"
          autoFocus
          placeholder="Search by account code or name…"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
        />
        <p className="text-xs text-slate-400">
          Only active Detail accounts can be selected. Group accounts are shown for context.
          {restrictTag ? ` This picker is restricted to accounts tagged “${restrictTag}”.` : ''}
        </p>
        <div className="max-h-[55vh] overflow-y-auto space-y-0.5 border border-slate-200 dark:border-slate-800 rounded-xl p-2">
          {loading && <div className="text-center text-slate-400 py-6 text-sm">Loading chart of accounts…</div>}
          {!loading && renderRows(0, 0)}
          {!loading && renderRows(0, 0).length === 0 && (
            <div className="text-center text-slate-400 py-6 text-sm">No accounts match the search.</div>
          )}
        </div>
      </div>
    </Modal>
  );
}
