export default function Pagination({ page, totalPages, total, onChange }) {
  if (totalPages <= 1) {
    return (
      <div className="flex items-center justify-between py-3 text-sm text-slate-500 dark:text-slate-400">
        <span>{total} record{total !== 1 ? 's' : ''}</span>
      </div>
    );
  }
  const pages = [];
  const start = Math.max(1, page - 2);
  const end = Math.min(totalPages, page + 2);
  for (let i = start; i <= end; i++) pages.push(i);

  return (
    <div className="flex items-center justify-between py-3 text-sm">
      <div className="text-slate-500 dark:text-slate-400">
        Page {page} of {totalPages} · {total} records
      </div>
      <div className="flex items-center gap-1">
        <button
          disabled={page === 1}
          onClick={() => onChange(page - 1)}
          className="px-3 py-1 rounded border border-slate-300 dark:border-slate-700 disabled:opacity-40 hover:bg-slate-100 dark:hover:bg-slate-800"
        >
          ‹
        </button>
        {start > 1 && <span className="px-2 text-slate-400">…</span>}
        {pages.map((p) => (
          <button
            key={p}
            onClick={() => onChange(p)}
            className={`px-3 py-1 rounded border ${
              p === page
                ? 'bg-brand-600 text-white border-brand-600'
                : 'border-slate-300 dark:border-slate-700 hover:bg-slate-100 dark:hover:bg-slate-800'
            }`}
          >
            {p}
          </button>
        ))}
        {end < totalPages && <span className="px-2 text-slate-400">…</span>}
        <button
          disabled={page === totalPages}
          onClick={() => onChange(page + 1)}
          className="px-3 py-1 rounded border border-slate-300 dark:border-slate-700 disabled:opacity-40 hover:bg-slate-100 dark:hover:bg-slate-800"
        >
          ›
        </button>
      </div>
    </div>
  );
}
