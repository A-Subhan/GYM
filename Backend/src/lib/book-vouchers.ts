import { db } from './db'
import { makeBookVoucherId, makeBookLineId, type BookVoucherPrefix, type BookLineKind } from './ids'

// =================================================================
// Dedicated book voucher posting (four books, each with its own line
// table after the SQL Server migration):
//   CASHBOOK -> CashBook  + CashBookLine   (CRV Cash Receipt / CPV Cash Payment)
//   BANKBOOK -> BankBook  + BankBookLine   (BRV Bank Receipt / BPV Bank Payment)
//   JV       -> JV        + JVLine         (manual Dr/Cr, must balance)
//   OTB      -> OpenTB    + OpenTBLine     (opening TB; may be saved unbalanced)
//
// Posting rules:
//   CRV / BRV (receipts): book account DEBITED,  detail lines CREDITED
//   CPV / BPV (payments): book account CREDITED, detail lines DEBITED
//   JV  : user enters Dr/Cr manually (must balance)
//   OTV : user enters Dr/Cr; may be saved unbalanced (difference parked)
//
// Voucher ID == Voucher Number, e.g. CRV/BR-001/SEP26/000001; reversal appends -R.
// =================================================================

export type BookType = 'CASHBOOK' | 'BANKBOOK' | 'JV' | 'OTB'
export type BookVoucherType = 'CRV' | 'CPV' | 'BRV' | 'BPV' | 'JV' | 'OTV'

export interface BookLineInput {
  accountId: string
  amount?: number          // single amount for CRV/CPV/BRV/BPV (side implied by voucher type)
  debit?: number           // explicit for JV/OTV
  credit?: number          // explicit for JV/OTV
  lineDescription?: string
  title?: string           // cash/bank books only
  reference?: string
  billType?: string        // cash/bank books only (Dr/Cr mapping per BILL_TYPE_SIDES)
  taxRate?: number         // stored as taxPercent on the line
  taxAmount?: number
  chequeNo?: string
  chequeBankName?: string
  status?: string
}

export interface PostBookVoucherInput {
  voucherType: BookVoucherType
  voucherDate: Date
  branchId: string
  branchCode: string
  bookChartId?: string | null
  description?: string
  reference?: string
  paymentMode?: string
  lines: BookLineInput[]
  postedById?: string
  // OTV-only: allow saving unbalanced
  allowUnbalanced?: boolean
  // edit mode
  existingVoucherId?: string
}

export function bookTypeFor(voucherType: BookVoucherType): BookType {
  if (voucherType === 'CRV' || voucherType === 'CPV') return 'CASHBOOK'
  if (voucherType === 'BRV' || voucherType === 'BPV') return 'BANKBOOK'
  if (voucherType === 'JV') return 'JV'
  return 'OTB'
}

/** Prisma delegate names for the voucher + line tables of a book. */
export function bookDelegates(bookType: BookType): { voucher: string; line: string; lineKind: BookLineKind } {
  switch (bookType) {
    case 'CASHBOOK': return { voucher: 'cashBook', line: 'cashBookLine', lineKind: 'C' }
    case 'BANKBOOK': return { voucher: 'bankBook', line: 'bankBookLine', lineKind: 'B' }
    case 'JV': return { voucher: 'journalVoucher', line: 'journalVoucherLine', lineKind: 'J' }
    default: return { voucher: 'openingTbVoucher', line: 'openingTbLine', lineKind: 'O' }
  }
}

function usesBookAccount(voucherType: BookVoucherType): boolean {
  return voucherType === 'CRV' || voucherType === 'CPV' || voucherType === 'BRV' || voucherType === 'BPV'
}

/** true when the book account is DEBITED (receipts); false when CREDITED (payments) */
function bookIsDebited(voucherType: BookVoucherType): boolean {
  return voucherType === 'CRV' || voucherType === 'BRV'
}

/** Lines carrying tax totals (cash/bank/JV) vs plain lines (OpenTB). */
function lineHasTax(bookType: BookType): boolean {
  return bookType !== 'OTB'
}

/** Lines carry title/billType/cheque columns (cash + bank books only). */
function lineHasChequeFields(bookType: BookType): boolean {
  return bookType === 'CASHBOOK' || bookType === 'BANKBOOK'
}

interface FinalLine {
  accountId: string
  debit: number
  credit: number
  amount: number
  lineDescription?: string
  title?: string
  reference?: string
  billType?: string
  taxRate: number
  taxAmount: number
  chequeNo?: string
  chequeAmount?: number | null
  chequeBankName?: string
  status: string
}

function r2(n: number): number {
  return Math.round(Number(n || 0) * 100) / 100
}

/** Build the create payload for the appropriate line table. */
function lineData(bookType: BookType, voucherId: string, voucherType: BookVoucherType, l: FinalLine, lineId: string): Record<string, unknown> {
  const data: Record<string, unknown> = {
    id: lineId,
    voucherId,
    accountId: l.accountId,
    debit: r2(l.debit),
    credit: r2(l.credit),
    amount: r2(l.amount),
    lineDescription: l.lineDescription,
    reference: l.reference,
    status: l.status || 'Active',
  }
  if (lineHasTax(bookType)) {
    data.taxPercent = r2(l.taxRate)
    data.taxAmount = r2(l.taxAmount)
    data.total = r2(r2(l.amount) + r2(l.taxAmount))
  }
  if (lineHasChequeFields(bookType)) {
    data.title = l.title
    data.billType = l.billType
    data.chequeNo = l.chequeNo
    data.chequeAmount = l.chequeAmount ?? (l.chequeNo ? r2(l.amount) : null) // cheque amount synced with amount
    data.chequeBankName = l.chequeBankName
    data.chequeStatus = l.chequeNo ? 'Hold' : null
  }
  return data
}

async function persistLines(tx: any, bookType: BookType, voucherId: string, voucherType: BookVoucherType, voucherDate: Date, lines: FinalLine[]) {
  const { line, lineKind } = bookDelegates(bookType)
  for (const l of lines) {
    const lineId = await makeBookLineId(lineKind, voucherDate, tx)
    await tx[line].create({ data: lineData(bookType, voucherId, voucherType, l, lineId) })
  }
}

export async function postBookVoucher(input: PostBookVoucherInput) {
  const isEdit = !!input.existingVoucherId
  const bookType = bookTypeFor(input.voucherType)

  let finalLines: FinalLine[] = []

  if (usesBookAccount(input.voucherType)) {
    if (!input.bookChartId) throw new Error(`Book account required for ${input.voucherType}`)
    if (!input.lines.length) throw new Error('Voucher must have at least one detail line')
    const detailIsCredit = bookIsDebited(input.voucherType) // receipts -> details credited
    finalLines = input.lines.map((l) => {
      const amt = r2(l.amount ?? 0)
      return {
        accountId: l.accountId,
        debit: detailIsCredit ? 0 : amt,
        credit: detailIsCredit ? amt : 0,
        amount: amt,
        lineDescription: l.lineDescription,
        title: l.title,
        reference: l.reference,
        billType: l.billType,
        taxRate: Number(l.taxRate) || 0,
        taxAmount: r2(l.taxAmount ?? 0),
        chequeNo: l.chequeNo,
        chequeAmount: l.chequeNo ? amt : null,
        chequeBankName: l.chequeBankName,
        status: l.status || 'Active',
      }
    })
    // auto book-account line on the opposite side (no tax on book line).
    // The book account moves by the GROSS total (amount + tax) so the
    // voucher balances: each detail line's `total` column = amount + tax.
    const totalDetail = r2(finalLines.reduce((s, l) => s + l.amount + l.taxAmount, 0))
    finalLines.unshift({
      accountId: input.bookChartId,
      debit: detailIsCredit ? totalDetail : 0,
      credit: detailIsCredit ? 0 : totalDetail,
      amount: totalDetail,
      lineDescription: `${input.voucherType} book line`,
      title: undefined,
      reference: undefined,
      billType: undefined,
      taxRate: 0,
      taxAmount: 0,
      chequeNo: undefined,
      chequeAmount: undefined,
      chequeBankName: undefined,
      status: 'Active',
    })
  } else {
    // JV / OTV — explicit debit/credit per line; bill type may force the side (cash/bank only field, kept for symmetry)
    if (!input.lines.length) throw new Error('Voucher must have at least one line')
    finalLines = input.lines.map((l) => {
      let debit = r2(l.debit ?? 0)
      let credit = r2(l.credit ?? 0)
      const amt = r2(l.amount ?? 0)
      if (l.billType && (amt > 0 || (debit === 0 && credit === 0))) {
        const side = sideForBillType(l.billType, l.accountId)
        if (side === 'Debit') { debit = amt || debit; credit = 0 }
        else if (side === 'Credit') { credit = amt || credit; debit = 0 }
      }
      return {
        accountId: l.accountId,
        debit,
        credit,
        amount: amt || debit || credit,
        lineDescription: l.lineDescription,
        title: l.title,
        reference: l.reference,
        billType: l.billType,
        taxRate: Number(l.taxRate) || 0,
        taxAmount: r2(l.taxAmount ?? 0),
        chequeNo: l.chequeNo,
        chequeAmount: l.chequeNo ? r2(l.amount ?? (debit || credit)) : null,
        chequeBankName: l.chequeBankName,
        status: l.status || 'Active',
      }
    })
  }

  const totalDebit = r2(finalLines.reduce((s, l) => s + l.debit, 0))
  const totalCredit = r2(finalLines.reduce((s, l) => s + l.credit, 0))
  const totalTax = r2(finalLines.reduce((s, l) => s + l.taxAmount, 0))
  const isOTV = input.voucherType === 'OTV'
  const balanced = Math.abs(totalDebit - totalCredit) < 0.01

  if (!isOTV && !balanced) {
    throw new Error(`Voucher not balanced: debit=${totalDebit}, credit=${totalCredit}`)
  }
  if (isOTV && !balanced && !input.allowUnbalanced && !isEdit) {
    // OTV may be saved unbalanced intentionally (knock-off flow)
    throw new Error(`Opening TB not balanced: debit=${totalDebit}, credit=${totalCredit}`)
  }

  // voucher id == voucher number
  let voucherId: string
  if (isEdit) {
    voucherId = input.existingVoucherId!
  } else {
    voucherId = await makeBookVoucherId(input.voucherType as BookVoucherPrefix, input.branchCode, input.voucherDate)
  }

  const { voucher: voucherDelegate, line: lineDelegate } = bookDelegates(bookType)

  return await db.$transaction(async (tx) => {
    if (isEdit) {
      // ensure exists + still editable (only non-reversed)
      const existing = await (tx as any)[voucherDelegate].findUnique({ where: { id: voucherId } })
      if (!existing) throw new Error('Voucher not found for edit')
      if (existing.status === 'Reversed') throw new Error('Reversed vouchers cannot be edited')
      await (tx as any)[lineDelegate].deleteMany({ where: { voucherId } })
      await (tx as any)[voucherDelegate].update({
        where: { id: voucherId },
        data: {
          voucherDate: input.voucherDate,
          description: input.description,
          reference: input.reference,
          paymentMode: input.paymentMode,
          totalAmount: usesBookAccount(input.voucherType) ? r2(totalDebit + totalTax) : undefined,
          totalDebit: usesBookAccount(input.voucherType) ? undefined : totalDebit,
          totalCredit: usesBookAccount(input.voucherType) ? undefined : totalCredit,
          difference: isOTV ? r2(totalDebit - totalCredit) : undefined,
          isBalanced: isOTV ? balanced : undefined,
          postedById: input.postedById ?? existing.postedById,
          updatedAt: new Date(),
        },
      })
      await persistLines(tx, bookType, voucherId, input.voucherType, new Date(input.voucherDate), finalLines)
      const updated = await (tx as any)[voucherDelegate].findUnique({
        where: { id: voucherId },
        include: { lines: { include: { account: true } } },
      })
      await tx.auditLog.create({
        data: { userId: input.postedById, action: 'UPDATE', module: 'book-vouchers', details: JSON.stringify({ voucherId, voucherType: input.voucherType }) },
      })
      return updated
    }

    const data: any = {
      id: voucherId,
      voucherType: input.voucherType,
      voucherDate: input.voucherDate,
      branchId: input.branchId,
      description: input.description,
      reference: input.reference,
      status: 'Posted',
      postedById: input.postedById,
    }
    if (usesBookAccount(input.voucherType)) {
      data.bookChartId = input.bookChartId
      data.paymentMode = input.paymentMode
      // gross: detail amounts + tax — keeps every voucher balanced
      data.totalAmount = r2(totalDebit + totalTax)
    } else {
      data.totalDebit = totalDebit
      data.totalCredit = totalCredit
      if (isOTV) {
        data.difference = r2(totalDebit - totalCredit)
        data.isBalanced = balanced
      }
    }

    await (tx as any)[voucherDelegate].create({ data })
    await persistLines(tx, bookType, voucherId, input.voucherType, input.voucherDate, finalLines)
    await tx.auditLog.create({
      data: { userId: input.postedById, action: 'POST', module: 'book-vouchers', details: JSON.stringify({ voucherId, voucherType: input.voucherType, totalDebit, totalCredit }) },
    })
    const created = await (tx as any)[voucherDelegate].findUnique({
      where: { id: voucherId },
      include: { lines: { include: { account: true } } },
    })
    return created
  }, { timeout: 15000 })
}

// =================================================================
// Bill Type -> Dr/Cr side mapping (client-confirmed, 10 items)
// =================================================================

export const BILL_TYPES: Array<{ name: string; side: 'Debit' | 'Credit' | 'Both' | 'Auto' }> = [
  { name: 'Sales Bill', side: 'Credit' },
  { name: 'Sales Return', side: 'Debit' },
  { name: 'Purchase Bill', side: 'Debit' },
  { name: 'Purchase Return', side: 'Credit' },
  { name: 'Receipt', side: 'Debit' },
  { name: 'Payment', side: 'Credit' },
  { name: 'Expense Bill', side: 'Debit' },
  { name: 'Income / Other Income', side: 'Credit' },
  { name: 'Contra / Adjustment', side: 'Both' },
  { name: 'Opening Balance', side: 'Auto' },
]

// Account groups that naturally carry a DEBIT balance
const DEBIT_NATURE_ACCOUNT_TYPES = ['Asset', 'Fixed Asset', 'Current Asset', 'Expense', 'Expenses', 'Receivable']

/** Resolve the effective side for a bill type. 'Auto' uses the account's nature. */
export function sideForBillType(billType: string, accountId?: string): 'Debit' | 'Credit' | 'Both' | 'Auto' {
  const bt = BILL_TYPES.find((b) => b.name.toLowerCase() === String(billType || '').toLowerCase())
  if (!bt) return 'Both'
  if (bt.side !== 'Auto') return bt.side
  // Opening Balance: derive from account nature
  if (accountId) {
    // synchronous best-effort: caller may pre-resolve; here we cannot query (pure fn)
    return 'Auto'
  }
  return 'Auto'
}

/** Async resolver that uses the chart account nature for 'Auto' bill types. */
export async function resolveSideForBillType(billType: string, accountId: string): Promise<'Debit' | 'Credit'> {
  const bt = BILL_TYPES.find((b) => b.name.toLowerCase() === String(billType || '').toLowerCase())
  if (bt && bt.side !== 'Auto' && bt.side !== 'Both') return bt.side
  const account = await db.chart.findUnique({ where: { id: accountId } })
  if (account && DEBIT_NATURE_ACCOUNT_TYPES.some((t) => String(account.accountType).toLowerCase().includes(t.toLowerCase()))) return 'Debit'
  return 'Credit'
}

// =================================================================
// Reversal — appends -R to the voucher id
// =================================================================

export async function reverseBookVoucher(voucherId: string, voucherType: BookVoucherType, userId: string, reason: string) {
  const bookType = bookTypeFor(voucherType)
  const { voucher: voucherDelegate, line: lineDelegate } = bookDelegates(bookType)
  const reversalId = `${voucherId}-R`

  return await db.$transaction(async (tx) => {
    const v: any = await (tx as any)[voucherDelegate].findUnique({ where: { id: voucherId }, include: { lines: true } })
    if (!v) throw new Error('Voucher not found')
    if (v.status === 'Reversed') throw new Error('Voucher already reversed')
    const dupe = await (tx as any)[voucherDelegate].findUnique({ where: { id: reversalId } })
    if (dupe) throw new Error('Voucher already reversed')

    const data: any = {
      id: reversalId,
      voucherType: v.voucherType,
      voucherDate: new Date(),
      branchId: v.branchId,
      description: `Reversal of ${voucherId}: ${reason}`.slice(0, 250),
      reference: voucherId,
      status: 'Posted',
      reversedById: userId,
      reversedAt: new Date(),
      reversalReason: reason,
      postedById: userId,
    }
    if (bookType === 'CASHBOOK' || bookType === 'BANKBOOK') {
      data.bookChartId = v.bookChartId
      data.paymentMode = v.paymentMode
      data.totalAmount = v.totalAmount
    } else {
      data.totalDebit = v.totalCredit
      data.totalCredit = v.totalDebit
      if (bookType === 'OTB') {
        data.difference = -(v as any).difference
        data.isBalanced = false
      }
    }
    await (tx as any)[voucherDelegate].create({ data })

    for (const l of v.lines) {
      const linePayload: any = {
        voucherId: reversalId,
        accountId: l.accountId,
        debit: l.credit,
        credit: l.debit,
        amount: l.amount,
        lineDescription: `Reversal: ${l.lineDescription || ''}`.slice(0, 250),
        reference: l.reference,
        status: 'Active',
      }
      if (lineHasTax(bookType)) {
        linePayload.id = await makeBookLineId(bookDelegates(bookType).lineKind, new Date(), tx)
        linePayload.taxPercent = l.taxPercent
        linePayload.taxAmount = l.taxAmount
        linePayload.total = l.total
      }
      if (lineHasChequeFields(bookType)) {
        linePayload.title = l.title
        linePayload.billType = l.billType
        linePayload.chequeNo = l.chequeNo
        linePayload.chequeAmount = l.chequeAmount
        linePayload.chequeBankName = l.chequeBankName
        linePayload.chequeStatus = l.chequeStatus
      }
      await (tx as any)[lineDelegate].create({ data: linePayload })
    }

    await (tx as any)[voucherDelegate].update({ where: { id: voucherId }, data: { status: 'Reversed', reversedById: userId, reversedAt: new Date(), reversalReason: reason } })
    await tx.auditLog.create({ data: { userId, action: 'REVERSE', module: 'book-vouchers', details: JSON.stringify({ voucherId, reversalId, reason }) } })

    return reversalId
  }, { timeout: 15000 })
}

// =================================================================
// Ledger/balance helpers over the four line tables
// =================================================================

/** Debit/credit sums for one account across Posted, NOT-deleted vouchers (optionally up to a date). */
export async function getChartBalance(chartId: string, asOf?: Date): Promise<{ debit: number; credit: number; balance: number }> {
  const voucherFilter: any = { status: 'Posted', isDeleted: false, ...(asOf ? { voucherDate: { lte: asOf } } : {}) }
  const [c, b, j, o] = await Promise.all([
    db.cashBookLine.aggregate({
      where: { accountId: chartId, status: 'Active', voucher: voucherFilter },
      _sum: { debit: true, credit: true },
    }),
    db.bankBookLine.aggregate({
      where: { accountId: chartId, status: 'Active', voucher: voucherFilter },
      _sum: { debit: true, credit: true },
    }),
    db.journalVoucherLine.aggregate({
      where: { accountId: chartId, status: 'Active', voucher: voucherFilter },
      _sum: { debit: true, credit: true },
    }),
    db.openingTbLine.aggregate({
      where: { accountId: chartId, status: 'Active', voucher: voucherFilter },
      _sum: { debit: true, credit: true },
    }),
  ])
  const debit = r2(
    (c._sum.debit || 0) + (b._sum.debit || 0) + (j._sum.debit || 0) + (o._sum.debit || 0),
  )
  const credit = r2(
    (c._sum.credit || 0) + (b._sum.credit || 0) + (j._sum.credit || 0) + (o._sum.credit || 0),
  )
  return { debit, credit, balance: r2(debit - credit) }
}

/** Opening (before `from`) + period movement + closing balance for one chart account. */
export async function getChartBalanceBetween(
  chartId: string,
  from: Date,
  to: Date,
): Promise<{ opening: number; debit: number; credit: number; balance: number }> {
  const beforeFilter = { status: 'Posted', isDeleted: false, voucherDate: { lt: from } }
  const inFilter = { status: 'Posted', isDeleted: false, voucherDate: { gte: from, lte: to } }
  const sums = await Promise.all([
    db.cashBookLine.aggregate({ where: { accountId: chartId, status: 'Active', voucher: beforeFilter }, _sum: { debit: true, credit: true } }),
    db.bankBookLine.aggregate({ where: { accountId: chartId, status: 'Active', voucher: beforeFilter }, _sum: { debit: true, credit: true } }),
    db.journalVoucherLine.aggregate({ where: { accountId: chartId, status: 'Active', voucher: beforeFilter }, _sum: { debit: true, credit: true } }),
    db.openingTbLine.aggregate({ where: { accountId: chartId, status: 'Active', voucher: beforeFilter }, _sum: { debit: true, credit: true } }),
    db.cashBookLine.aggregate({ where: { accountId: chartId, status: 'Active', voucher: inFilter }, _sum: { debit: true, credit: true } }),
    db.bankBookLine.aggregate({ where: { accountId: chartId, status: 'Active', voucher: inFilter }, _sum: { debit: true, credit: true } }),
    db.journalVoucherLine.aggregate({ where: { accountId: chartId, status: 'Active', voucher: inFilter }, _sum: { debit: true, credit: true } }),
    db.openingTbLine.aggregate({ where: { accountId: chartId, status: 'Active', voucher: inFilter }, _sum: { debit: true, credit: true } }),
  ])
  const sumDebit = (idx: number[]) => r2(idx.reduce((s, i) => s + (sums[i]._sum.debit || 0), 0))
  const sumCredit = (idx: number[]) => r2(idx.reduce((s, i) => s + (sums[i]._sum.credit || 0), 0))
  const opening = r2(sumDebit([0, 1, 2, 3]) - sumCredit([0, 1, 2, 3]))
  const debit = sumDebit([4, 5, 6, 7])
  const credit = sumCredit([4, 5, 6, 7])
  return { opening, debit, credit, balance: r2(opening + debit - credit) }
}
