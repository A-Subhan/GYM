import Spinner from './Spinner';
import Pagination from './Pagination';

export default function DataTable({ columns, rows, loading, pagination, onPageChange, emptyMessage = 'No records found' }) {
  if (loading) {
    return (
      <div className="card overflow-hidden">
        <div className="p-8 flex justify-center"><Spinner /></div>
      </div>
    );
  }
  return (
    <div className="card overflow-hidden">
      <div className="table-wrap">
        <table className="table">
          <thead>
            <tr>
              {columns.map((c) => (
                <th key={c.key} style={c.width ? { width: c.width } : undefined}>{c.label}</th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 && (
              <tr><td colSpan={columns.length} className="text-center text-slate-400 py-8">{emptyMessage}</td></tr>
            )}
            {rows.map((row, i) => (
              <tr key={row.id || row.ID || i}>
                {columns.map((c) => (
                  <td key={c.key}>{c.render ? c.render(row, i) : (row[c.key] ?? '—')}</td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {pagination && (
        <div className="px-4">
          <Pagination
            page={pagination.page}
            totalPages={pagination.totalPages}
            total={pagination.total}
            onChange={onPageChange}
          />
        </div>
      )}
    </div>
  );
}
