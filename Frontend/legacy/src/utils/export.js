/**
 * Export an array of objects to a CSV file (opens download dialog).
 * @param {Array<Object>} rows
 * @param {string} filename
 * @param {Array<{key:string,label:string}>} columns  optional; default = all keys from first row
 */
export function exportToCSV(rows, filename = 'export.csv', columns = null) {
  if (!rows || rows.length === 0) {
    alert('No data to export');
    return;
  }
  const cols = columns || Object.keys(rows[0]).map((k) => ({ key: k, label: k }));
  const header = cols.map((c) => `"${(c.label || c.key).replace(/"/g, '""')}"`).join(',');
  const body = rows.map((r) =>
    cols.map((c) => {
      const v = r[c.key];
      if (v === null || v === undefined) return '';
      const s = typeof v === 'object' ? JSON.stringify(v) : String(v);
      return `"${s.replace(/"/g, '""')}"`;
    }).join(',')
  ).join('\n');
  const csv = header + '\n' + body;
  const blob = new Blob(['\uFEFF' + csv], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}

/**
 * Trigger the browser's print dialog for the current page.
 */
export function printPage() {
  window.print();
}
