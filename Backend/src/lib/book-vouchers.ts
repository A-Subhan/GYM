import { db } from './db'
import { makeBookVoucherId, type BookVoucherPrefix } from './ids'

// =================================================================
// Dedicated book voucher posting (replaces generic Voucher)
//   CRV Cash Receipt      : cash book DEBITED,  detail lines CREDITED
//   CPV Cash Payment      : cash book CREDITED, detail lines DEBITED
//   BRV Bank Receipt      : bank book DEBITED,  detail lines CREDITED
//   BPV Bank Payment      : bank book CREDITED, detail lines DEBITED
//   JV  Journal           : user enters Dr/Cr manually (must balance)
//   OTV Opening TB        : user enters Dr/Cr; may be saved unbalanced
//                           (difference parked, can be knocked off later)
// Voucher ID == Voucher Number, e.g. CRV/MAIN/Sep25/000001; reversal appends -R.
// =================================================================

export type BookType = 'CASHBOOK' | 'BANKBOOK' | 'JV' | 'OTB'
export type BookVoucherType = 'CRV' | 'CPV' | 'BRV' | 'BPV' | 'JV' | 'OTV'

export interface BookLineInput {
  accountId: string
  amount?: number          // single amount for CRV/CPV/BRV/BPV (side implied by voucher type)
  debit?: number           // explicit for JV/OTV
  credit?: number          // explicit for JV/OTV
  lineDescription?: string
  title?: string
  reference?: string
  billType?: string        // Bill Type (Dr/Cr mapping per BILL_TYPE_SIDES)
  taxRate?: number
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

function usesBookAccount(voucherType: BookVoucherType): boolean {
  return voucherType === 'CRV' || voucherType === 'CPV' || voucherType === 'BRV' || voucherType === 'BPV'
}

/** true when the book account is DEBITED (receipts); false when CREDITED (payments) */
function bookIsDebited(voucherType: BookVoucherType): boolean {
  return voucherType === 'CRV' || voucherType === 'BRV'
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

async function persistLines(
  tx: any,
  voucherId: string,
  voucherType: BookVoucherType,
  bookType: BookType,
  lines: FinalLine[],
) {
  for (const l of lines) {
    await tx.bookVoucherLine.create({
      data: {
        voucherId,
        voucherType,
        bookType,
        accountId: l.accountId,
        debit: r2(l.debit),
        credit: r2(l.credit),
        amount: r2(l.amount),
        lineDescription: l.lineDescription,
        title: l.title,
        reference: l.reference,
        billType: l.billType,
        taxRate: l.taxRate,
        taxAmount: l.taxAmount,
        chequeNo: l.chequeNo,
        chequeAmount: l.chequeAmount ?? (l.chequeNo ? r2(l.amount) : null), // cheque amount synced with amount
        chequeBankName: l.chequeBankName,
        chequeStatus: l.chequeNo ? 'Hold' : null,
        status: l.status,
      },
    })
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
    // auto book-account line on the opposite side (no tax on book line)
    const totalDetail = r2(finalLines.reduce((s, l) => s + l.debit + l.credit, 0))
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
    // JV / OTV — explicit debit/credit per line; bill type may force the side
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
        chequeAmount: l.chequeNo ? r2(l.amount ?? debit || credit) : null,
        chequeBankName: l.chequeBankName,
        status: l.status || 'Active',
      }
    })
  }

  const totalDebit = r2(finalLines.reduce((s, l) => s + l.debit, 0))
  const totalCredit = r2(finalLines.reduce((s, l) => s + l.credit, 0))
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

  return await db.$transaction(async (tx) => {
    if (isEdit) {
      // ensure exists + still editable (only non-reversed)
      const table = bookTable(bookType)
      const existing = await (tx as any)[table].findUnique({ where: { id: voucherId } })
      if (!existing) throw new Error('Voucher not found for edit')
      if (existing.status === 'Reversed') throw new Error('Reversed vouchers cannot be edited')
      await tx.bookVoucherLine.deleteMany({ where: { voucherId } })
      await (tx as any)[table].update({
        where: { id: voucherId },
        data: {
          voucherDate: input.voucherDate,
          description: input.description,
          reference: input.reference,
          paymentMode: input.paymentMode,
          totalAmount: usesBookAccount(input.voucherType) ? totalDebit : undefined,
          totalDebit: usesBookAccount(input.voucherType) ? undefined : totalDebit,
          totalCredit: usesBookAccount(input.voucherType) ? undefined : totalCredit,
          difference: isOTV ? r2(totalDebit - totalCredit) : undefined,
          isBalanced: isOTV ? balanced : undefined,
          postedById: input.postedById ?? existing.postedById,
          updatedAt: new Date(),
        },
      })
      await persistLines(tx, voucherId, input.voucherType, bookType, finalLines)
      const updated = await (tx as any)[table].findUnique({
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
      data.totalAmount = totalDebit
    } else {
      data.totalDebit = totalDebit
      data.totalCredit = totalCredit
      if (isOTV) {
        data.difference = r2(totalDebit - totalCredit)
        data.isBalanced = balanced
      }
    }

    const table = bookTable(bookType)
    const voucher = await (tx as any)[table].create({ data })
    await persistLines(tx, voucherId, input.voucherType, bookType, finalLines)
    await tx.auditLog.create({
      data: { userId: input.postedById, action: 'POST', module: 'book-vouchers', details: JSON.stringify({ voucherId, voucherType: input.voucherType, totalDebit, totalCredit }) },
    })
    const created = await (tx as any)[table].findUnique({
      where: { id: voucherId },
      include: { lines: { include: { account: true } } },
    })
    return created
  })
}

function bookTable(bookType: BookType): 'cashbookVoucher' | 'bankbookVoucher' | 'journalVoucher' | 'openTbVoucher' {
  switch (bookType) {
    case 'CASHBOOK': return 'cashbookVoucher'
    case 'BANKBOOK': return 'bankbookVoucher'
    case 'JV': return 'journalVoucher'
    default: return 'openTbVoucher'
  }
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
  const table = bookTable(bookType)
  const reversalId = `${voucherId}-R`

  return await db.$transaction(async (tx) => {
    const v: any = await (tx as any)[table].findUnique({ where: { id: voucherId }, include: { lines: true } })
    if (!v) throw new Error('Voucher not found')
    if (v.status === 'Reversed') throw new Error('Voucher already reversed')
    const dupe = await (tx as any)[table].findUnique({ where: { id: reversalId } })
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
    await (tx as any)[table].create({ data })

    for (const l of v.lines) {
      await tx.bookVoucherLine.create({
        data: {
          voucherId: reversalId,
          voucherType: v.voucherType,
          bookType,
          accountId: l.accountId,
          debit: l.credit,
          credit: l.debit,
          amount: l.amount,
          lineDescription: `Reversal: ${l.lineDescription || ''}`.slice(0, 250),
          title: l.title,
          reference: l.reference,
          billType: l.billType,
          taxRate: l.taxRate,
          taxAmount: l.taxAmount,
          chequeNo: l.chequeNo,
          chequeAmount: l.chequeAmount,
          chequeBankName: l.chequeBankName,
          chequeStatus: l.chequeStatus,
          status: 'Active',
        },
      })
    }

    await (tx as any)[table].update({ where: { id: voucherId }, data: { status: 'Reversed', reversedById: userId, reversedAt: new Date(), reversalReason: reason } })
    await tx.auditLog.create({ data: { userId, action: 'REVERSE', module: 'book-vouchers', details: JSON.stringify({ voucherId, reversalId, reason }) } })

    return reversalId
  })
}

// =================================================================
// Ledger/balance helpers over BookVoucherLine
// =================================================================

export async function getChartBalance(chartId: string, asOf?: Date): Promise<{ debit: number; credit: number; balance: number }> {
  // Vouchers posted (not reversed) up to asOf
  const dateFilter = asOf ? { voucherDate: { lte: asOf } } : {}
  const [c, b, j, o] = await Promise.all([
    db.cashbookVoucher.findMany({ where: { status: 'Posted', ...dateFilter }, select: { id: true } }),
    db.bankbookVoucher.findMany({ where: { status: 'Posted', ...dateFilter }, select: { id: true } }),
    db.journalVoucher.findMany({ where: { status: 'Posted', ...dateFilter }, select: { id: true } }),
    db.openTbVoucher.findMany({ where: { status: 'Posted', ...dateFilter }, select: { id: true } }),
  ])
  const voucherIds = [...c, ...b, ...j, ...o].map((x: any) => x.id)
  if (!voucherIds.length) return { debit: 0, credit: 0, balance: 0 }
  const lines = await db.bookVoucherLine.findMany({
    where: { accountId: chartId, status: 'Active', voucherId: { in: voucherIds } },
    select: { debit: true, credit: true },
  })
  const debit = r2(lines.reduce((s, l) => s + l.debit, 0))
  const credit = r2(lines.reduce((s, l) => s + l.credit, 0))
  return { debit, credit, balance: r2(debit - credit) }
}

/** Opening (before `from`) + period movement + closing balance for one chart account. */
export async function getChartBalanceBetween(
  chartId: string,
  from: Date,
  to: Date,
): Promise<{ opening: number; debit: number; credit: number; balance: number }> {
  const idsBefore = await postedVoucherIdsBefore(from)
  const idsIn = await postedVoucherIdsBetween(from, to)
  const [openingLines, periodLines] = await Promise.all([
    db.bookVoucherLine.findMany({
      where: { accountId: chartId, status: 'Active', voucherId: { in: idsBefore } },
      select: { debit: true, credit: true },
    }),
    db.bookVoucherLine.findMany({
      where: { accountId: chartId, status: 'Active', voucherId: { in: idsIn } },
      select: { debit: true, credit: true },
    }),
  ])
  const opening = r2(openingLines.reduce((s, l) => s + l.debit - l.credit, 0))
  const debit = r2(periodLines.reduce((s, l) => s + l.debit, 0))
  const credit = r2(periodLines.reduce((s, l) => s + l.credit, 0))
  return { opening, debit, credit, balance: r2(opening + debit - credit) }
}

async function postedVoucherIdsBefore(date: Date): Promise<string[]> {
  const [c, b, j, o] = await Promise.all([
    db.cashbookVoucher.findMany({ where: { status: 'Posted', voucherDate: { lt: date } }, select: { id: true } }),
    db.bankbookVoucher.findMany({ where: { status: 'Posted', voucherDate: { lt: date } }, select: { id: true } }),
    db.journalVoucher.findMany({ where: { status: 'Posted', voucherDate: { lt: date } }, select: { id: true } }),
    db.openTbVoucher.findMany({ where: { status: 'Posted', voucherDate: { lt: date } }, select: { id: true } }),
  ])
  return [...c, ...b, ...j, ...o].map((x: any) => x.id)
}

async function postedVoucherIdsBetween(from: Date, to: Date): Promise<string[]> {
  const [c, b, j, o] = await Promise.all([
    db.cashbookVoucher.findMany({ where: { status: 'Posted', voucherDate: { gte: from, lte: to } }, select: { id: true } }),
    db.bankbookVoucher.findMany({ where: { status: 'Posted', voucherDate: { gte: from, lte: to } }, select: { id: true } }),
    db.journalVoucher.findMany({ where: { status: 'Posted', voucherDate: { gte: from, lte: to } }, select: { id: true } }),
    db.openTbVoucher.findMany({ where: { status: 'Posted', voucherDate: { gte: from, lte: to } }, select: { id: true } }),
  ])
  return [...c, ...b, ...j, ...o].map((x: any) => x.id)
}
