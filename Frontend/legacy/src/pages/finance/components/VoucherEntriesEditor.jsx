import AccountSelector from './AccountSelector';

/**
 * Reusable double-entry grid for all voucher types.
 * Rows: { AccountID, Debit, Credit, Narrative, PartyMemberID, PartySupplierID, PartyStaffID, BillRef, BillDate, DueDate }
 * The money side of Receipt/Payment vouchers is restricted to accounts tagged
 * Cash/Bank (tenderTag); the engine re-validates server-side.
 */
const EMPTY_ROW = () => ({ AccountID: '', Debit: '', Credit: '', Narrative: '', PartyMemberID: '', PartySupplierID: '', PartyStaffID: '', BillRef: '', BillDate: '', DueDate: '' });

export default function VoucherEntriesEditor({ entries, setEntries, tenderTag, partyKind, disabled = false }) {
  const rows = entries.length ? entries : [EMPTY_ROW()];

  const update = (i, field, val) => {
    const next = rows.map((r, idx) => (idx === i ? { ...r, [field]: val } : r));
    // keep sides mutually exclusive: typing on one side clears the other
    if (field === 'Debit' && val !== '' && Number(val) > 0) next[i].Credit = '';
    if (field === 'Credit' && val !== '' && Number(val) > 0) next[i].Debit = '';
    setEntries(next);
  };

  const addRow = () => setEntries([...rows, EMPTY_ROW()]);
  const removeRow = (i) => setEntries(rows.filter((_, idx) => idx !== i));

  const totalDr = rows.reduce((s, r) => s + (Number(r.Debit) || 0), 0);
  const totalCr = rows.reduce((s, r) => s + (Number(r.Credit) || 0), 0);
  const diff = Number((totalDr - totalCr).toFixed(2));
  const balanced = totalDr > 0 && diff === 0;

  return (
    <div className="space-y-2">
      <div className="table-wrap">
        <table className="table">
          <thead>
            <tr>
              <th style={{ width: '32%' }}>Account</th>
              <th style={{ width: '13%' }}>Debit</th>
              <th style={{ width: '13%' }}>Credit</th>
              {partyKind && <th style={{ width: '14%' }}>{partyKind === 'member' ? 'Customer' : partyKind === 'supplier' ? 'Vendor' : 'Employee'}</th>}
              <th>Narration</th>
              {!disabled && <th style={{ width: 36 }}></th>}
            </tr>
          </thead>
          <tbody>
            {rows.map((row, i) => (
              <tr key={i}>
                <td>
                  <AccountSelector
                    tag={tenderTag && Number(row.Debit) > 0 ? tenderTag : null}
                    value={row.AccountID}
                    onChange={(v) => update(i, 'AccountID', v)}
                    disabled={disabled}
                  />
                </td>
                <td>
                  <input type="number" step="0.01" min="0" className="input no-spinner" disabled={disabled}
                    value={row.Debit} onChange={(e) => update(i, 'Debit', e.target.value)} />
                </td>
                <td>
                  <input type="number" step="0.01" min="0" className="input no-spinner" disabled={disabled}
                    value={row.Credit} onChange={(e) => update(i, 'Credit', e.target.value)} />
                </td>
                {partyKind && (
                  <td>
                    <input type="number" className="input no-spinner" disabled={disabled}
                      placeholder={partyKind === 'member' ? 'Member ID' : partyKind === 'supplier' ? 'Supplier ID' : 'Staff ID'}
                      value={row[partyKind === 'member' ? 'PartyMemberID' : partyKind === 'supplier' ? 'PartySupplierID' : 'PartyStaffID'] || ''}
                      onChange={(e) => update(i, partyKind === 'member' ? 'PartyMemberID' : partyKind === 'supplier' ? 'PartySupplierID' : 'PartyStaffID', e.target.value)} />
                  </td>
                )}
                <td>
                  <input className="input" disabled={disabled} value={row.Narrative || ''}
                    onChange={(e) => update(i, 'Narrative', e.target.value)} />
                </td>
                {!disabled && (
                  <td>
                    <button type="button" className="text-red-500 hover:text-red-700 font-bold" title="Remove line"
                      onClick={() => removeRow(i)}>×</button>
                  </td>
                )}
              </tr>
            ))}
          </tbody>
          <tfoot>
            <tr className="font-semibold border-t-2 border-slate-300">
              <td>Totals</td>
              <td className="text-emerald-700">{totalDr.toFixed(2)}</td>
              <td className="text-red-700">{totalCr.toFixed(2)}</td>
              {partyKind && <td></td>}
              <td colSpan={disabled ? 1 : 2}>
                Difference: <span className={balanced ? 'text-emerald-700 font-bold' : 'text-red-600 font-bold'}>{diff.toFixed(2)}</span>
              </td>
            </tr>
          </tfoot>
        </table>
      </div>

      {!disabled && (
        <div className="flex items-center justify-between">
          <button type="button" className="btn-secondary text-sm px-3 py-1.5" onClick={addRow}>+ Add line</button>
          {!balanced && (
            <div className="text-xs text-red-600 font-medium">
              {totalDr <= 0 ? 'Debit total must be greater than zero.' : 'Debit and Credit must be equal before posting.'}
            </div>
          )}
        </div>
      )}
    </div>
  );
}
