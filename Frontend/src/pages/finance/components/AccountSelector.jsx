import { useEffect, useMemo, useState } from 'react';
import api from '../../../services/api';

/**
 * Context-sensitive account selector.
 * Only active Detail accounts are offered, filtered by Tag (line accounts)
 * and/or Book Type (voucher Book Accounts) with branch availability applied
 * server-side.
 */
export default function AccountSelector({ tag, bookType, value, onChange, disabled = false, className = 'input' }) {
  const [options, setOptions] = useState([]);
  const [filter, setFilter] = useState('');
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    let alive = true;
    setLoading(true);
    api.get('/finance/coa/selectors', { params: { tag: tag || undefined, bookType: bookType || undefined, limit: 500 } })
      .then((res) => { if (alive) setOptions(res.data.data || []); })
      .catch(() => { if (alive) setOptions([]); })
      .finally(() => { if (alive) setLoading(false); });
    return () => { alive = false; };
  }, [tag, bookType]);

  const filtered = useMemo(() => {
    if (!filter) return options;
    const f = filter.toLowerCase();
    return options.filter((o) => o.Code.includes(f) || o.Title.toLowerCase().includes(f));
  }, [options, filter]);

  return (
    <div className="flex gap-1 items-center w-full">
      <select
        className={className}
        value={value || ''}
        disabled={disabled || loading}
        onChange={(e) => onChange(e.target.value ? Number(e.target.value) : '')}
      >
        <option value="">{loading ? 'Loading…' : '— select account —'}</option>
        {filtered.map((o) => (
          <option key={o.AccountID} value={o.AccountID}>{o.Code} · {o.Title}</option>
        ))}
      </select>
      {options.length > 12 && (
        <input
          className="input w-28 flex-shrink-0"
          placeholder="filter"
          value={filter}
          disabled={disabled}
          onChange={(e) => setFilter(e.target.value)}
        />
      )}
    </div>
  );
}
