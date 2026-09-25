import { formatCurrency, formatDate } from '../../../utils/format';
import PrintHeader from './PrintHeader';

/**
 * Printable voucher document (browser print → PDF).
 * Shows company info, voucher identification, the money account,
 * the detail lines with amounts/taxes and a Debit/Credit summary.
 */
export default function VoucherPrint({ voucher, lines, meta }) {
  if (!voucher) return null;
  const total = Number(voucher.Amount ?? voucher.DebitTotal ?? 0);
  const isSimple = meta.family === 'CASH' || meta.family === 'BANK';
  const moneyLabel = meta.family === 'BANK' ? 'Bank Account' : meta.family === 'CASH' ? 'Cash Account' : null;

  return (
    <div className="print-area">
      <PrintHeader
        title={`${meta.title}${voucher.VoucherNo ? ` — ${voucher.VoucherNo}` : ''}`}
        subtitle={`Voucher Date: ${formatDate(voucher.VoucherDate)} · Branch: ${voucher.BranchName || '—'} · Status: ${voucher.Status}`}
      />

      <div className="grid grid-cols-2 gap-3 text-sm mb-4">
        {moneyLabel && (
          <div>
            <div className="text-xs uppercase tracking-wide text-slate-400">{moneyLabel}</div>
            <div className="font-medium">{voucher.MoneyAccountCode ? `${voucher.MoneyAccountCode} · ${voucher.MoneyAccountTitle}` : '—'}</div>
          </div>
        )}
        <div>
          <div className="text-xs uppercase tracking-wide text-slate-400">Description</div>
          <div>{voucher.Narrative || '—'}</div>
        </div>
      </div>

      <table className="table mb-3">
        <thead>
          <tr>
            <th>Account</th>
            <th>Description</th>
            {isSimple ? <th className="text-right">Amount</th> : <th className="text-right">Debit</th>}
            {!isSimple && <th className="text-right">Credit</th>}
            <th>Tax</th>
            {isSimple && <th>Bill Ref</th>}
          </tr>
        </thead>
        <tbody>
          {(lines || []).map((l) => (
            <tr key={l.LineID}>
              <td>{l.AccountCode} · {l.AccountTitle}</td>
              <td>{l.Description || '—'}</td>
              {isSimple
                ? <td className="text-right">{formatCurrency(l.Amount)}</td>
                : <>
                    <td className="text-right">{Number(l.Debit) > 0 ? formatCurrency(l.Debit) : '—'}</td>
                    <td className="text-right">{Number(l.Credit) > 0 ? formatCurrency(l.Credit) : '—'}</td>
                  </>}
              <td>{l.TaxHeadName ? `${l.TaxHeadCode} · ${l.TaxHeadName}` : '—'}</td>
              {isSimple && <td>{l.BillRef || '—'}</td>}
            </tr>
          ))}
          <tr className="font-semibold border-t-2 border-slate-300">
            <td colSpan={isSimple ? 2 : 2}>Total</td>
            {isSimple
              ? <td className="text-right">{formatCurrency(total)}</td>
              : <>
                  <td className="text-right">{formatCurrency(voucher.DebitTotal)}</td>
                  <td className="text-right">{formatCurrency(voucher.CreditTotal)}</td>
                </>}
            <td></td>
            {isSimple && <td></td>}
          </tr>
        </tbody>
      </table>

      {isSimple && (
        <div className="text-sm text-slate-600 dark:text-slate-300">
          <span className="font-semibold">Accounting effect: </span>
          {voucher.Direction === 'Receipt'
            ? <>Dr {voucher.MoneyAccountTitle} {formatCurrency(total)} / Cr detail accounts {formatCurrency(total)}</>
            : <>Dr detail accounts {formatCurrency(total)} / Cr {voucher.MoneyAccountTitle} {formatCurrency(total)}</>}
        </div>
      )}
    </div>
  );
}
