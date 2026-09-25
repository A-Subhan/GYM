import { db } from './db'

type VoucherType = 'CRV' | 'CPV' | 'BRV' | 'BPV' | 'JV' | 'OTB' | 'POS-SALE' | 'FEE'

interface VoucherLineInput {
  accountId: string
  amount?: number
  debit?: number
  credit?: number
  lineDescription?: string
  taxAccountId?: string
  taxRate?: number
  taxAmount?: number
  chequeNo?: string
  chequeAmount?: number
  chequeBankName?: string
  chequeStatus?: string
  status?: string
}

interface PostVoucherInput {
  voucherType: VoucherType
  voucherDate: Date
  branchId: string
  bookAccountId?: string | null
  description?: string
  reference?: string
  lines: VoucherLineInput[]
  postedById: string
  status?: 'Draft' | 'Posted'
}

function usesBookAccount(vt: VoucherType): boolean {
  return vt === 'CRV' || vt === 'CPV' || vt === 'BRV' || vt === 'BPV'
}

function bookAccountIsDebited(vt: VoucherType): boolean {
  return vt === 'CRV' || vt === 'BRV'
}

// Generate voucher number: TYPE/BranchID/MonthYear/000001
// Queries the appropriate table per voucher type
async function generateVoucherNo(vt: string, branchId: string, date: Date): Promise<string> {
  const prefix = vt
  const monthYear = String(date.getMonth() + 1).padStart(2, '0') + String(date.getFullYear()).slice(-2)
  const startsWith = `${prefix}/${branchId}/${monthYear}/`

  let count = 0
  if (vt === 'CRV' || vt === 'CPV') {
    count = await db.cashBook.count({ where: { voucherNo: { startsWith } } })
  } else if (vt === 'BRV' || vt === 'BPV') {
    count = await db.bankBook.count({ where: { voucherNo: { startsWith } } })
  } else if (vt === 'JV') {
    count = await db.jV.count({ where: { voucherNo: { startsWith } } })
  } else if (vt === 'OTB') {
    count = await db.openTB.count({ where: { voucherNo: { startsWith } } })
  }
  return `${prefix}/${branchId}/${monthYear}/${String(count + 1).padStart(6, '0')}`
}

// Build the final lines array with the synthesized book-account line if applicable
function buildFinalLines(input: PostVoucherInput): Array<any> {
  let finalLines: Array<any> = []

  if (usesBookAccount(input.voucherType)) {
    if (!input.bookAccountId) throw new Error(`Book account required for ${input.voucherType}`)
    if (input.lines.length === 0) throw new Error('Voucher must have at least one detail line')

    const detailIsCredit = bookAccountIsDebited(input.voucherType)
    const detailLines = input.lines.map((l) => {
      const amt = Number(l.amount || 0)
      return {
        accountId: l.accountId,
        debit: detailIsCredit ? 0 : amt,
        credit: detailIsCredit ? amt : 0,
        amount: amt,
        lineDescription: l.lineDescription,
        taxAccountId: l.taxAccountId,
        taxRate: Number(l.taxRate) || 0,
        taxAmount: Number(l.taxAmount) || 0,
        chequeNo: l.chequeNo,
        chequeAmount: l.chequeAmount,
        chequeBankName: l.chequeBankName,
        chequeStatus: l.chequeStatus,
        status: l.status || 'Active',
      }
    })
    const totalDetail = detailLines.reduce((s, l) => s + l.debit + l.credit, 0)
    const bookLine = {
      accountId: input.bookAccountId,
      debit: detailIsCredit ? totalDetail : 0,
      credit: detailIsCredit ? 0 : totalDetail,
      amount: totalDetail,
      lineDescription: `Book account — ${input.voucherType}`,
      taxRate: 0,
      taxAmount: 0,
      status: 'Active',
    }
    finalLines = [bookLine, ...detailLines]
  } else {
    if (input.lines.length === 0) throw new Error('Voucher must have at least one line')
    finalLines = input.lines.map((l) => ({
      accountId: l.accountId,
      debit: Number(l.debit) || 0,
      credit: Number(l.credit) || 0,
      amount: Number(l.amount) || 0,
      lineDescription: l.lineDescription,
      taxAccountId: l.taxAccountId,
      taxRate: Number(l.taxRate) || 0,
      taxAmount: Number(l.taxAmount) || 0,
      chequeNo: l.chequeNo,
      chequeAmount: l.chequeAmount,
      chequeBankName: l.chequeBankName,
      chequeStatus: l.chequeStatus,
      status: l.status || 'Active',
    }))
  }
  return finalLines
}

export async function postVoucher(input: PostVoucherInput) {
  const finalLines = buildFinalLines(input)

  const totalDebit = finalLines.reduce((s, l) => s + l.debit, 0)
  const totalCredit = finalLines.reduce((s, l) => s + l.credit, 0)
  // For OTB, don't enforce balance. For all others, enforce.
  if (input.voucherType !== 'OTB' && Math.abs(totalDebit - totalCredit) > 0.01) {
    throw new Error(`Voucher not balanced: debit=${totalDebit}, credit=${totalCredit}`)
  }

  const voucherNo = await generateVoucherNo(input.voucherType, input.branchId, input.voucherDate)

  const lineData = finalLines.map((l) => ({
    accountId: l.accountId,
    debit: l.debit,
    credit: l.credit,
    amount: l.amount,
    lineDescription: l.lineDescription,
    taxAccountId: l.taxAccountId,
    taxRate: l.taxRate,
    taxAmount: l.taxAmount,
    chequeNo: l.chequeNo,
    chequeAmount: l.chequeAmount,
    chequeBankName: l.chequeBankName,
    chequeStatus: l.chequeStatus,
    status: l.status,
  }))

  return await db.$transaction(async (tx) => {
    let voucher: any
    const postedById = input.status === 'Draft' ? null : input.postedById
    const postedAt = input.status === 'Draft' ? null : new Date()

    if (input.voucherType === 'CRV' || input.voucherType === 'CPV') {
      voucher = await tx.cashBook.create({
        data: {
          voucherNo,
          voucherType: input.voucherType,
          voucherDate: input.voucherDate,
          branchId: input.branchId,
          bookAccountId: input.bookAccountId ?? null,
          description: input.description,
          reference: input.reference,
          status: input.status ?? 'Posted',
          postedById,
          postedAt,
          totalDebit,
          totalCredit,
          lines: { create: lineData },
        },
        include: { lines: true, branch: true, bookAccount: true },
      })
    } else if (input.voucherType === 'BRV' || input.voucherType === 'BPV') {
      voucher = await tx.bankBook.create({
        data: {
          voucherNo,
          voucherType: input.voucherType,
          voucherDate: input.voucherDate,
          branchId: input.branchId,
          bookAccountId: input.bookAccountId ?? null,
          description: input.description,
          reference: input.reference,
          status: input.status ?? 'Posted',
          postedById,
          postedAt,
          totalDebit,
          totalCredit,
          lines: { create: lineData },
        },
        include: { lines: true, branch: true, bookAccount: true },
      })
    } else if (input.voucherType === 'JV') {
      voucher = await tx.jV.create({
        data: {
          voucherNo,
          voucherType: 'JV',
          voucherDate: input.voucherDate,
          branchId: input.branchId,
          description: input.description,
          reference: input.reference,
          status: input.status ?? 'Posted',
          postedById,
          postedAt,
          totalDebit,
          totalCredit,
          lines: { create: lineData },
        },
        include: { lines: true, branch: true },
      })
    } else if (input.voucherType === 'OTB') {
      voucher = await tx.openTB.create({
        data: {
          voucherNo,
          voucherType: 'OTV',
          voucherDate: input.voucherDate,
          branchId: input.branchId,
          description: input.description,
          status: 'Posted',
          postedById,
          postedAt,
          totalDebit,
          totalCredit,
          lines: { create: lineData.map((l) => ({
            accountId: l.accountId,
            debit: l.debit,
            credit: l.credit,
            lineDescription: l.lineDescription,
          })) },
        },
        include: { lines: true, branch: true },
      })
    } else {
      throw new Error(`Unsupported voucher type: ${input.voucherType}`)
    }

    await tx.auditLog.create({
      data: {
        userId: input.postedById,
        action: 'POST',
        module: 'vouchers',
        details: JSON.stringify({ voucherNo, type: input.voucherType, totalDebit, totalCredit }),
      },
    })

    return voucher
  })
}

// Lookup a voucher by voucherNo across all 4 tables
export async function findVoucherByNo(voucherNo: string): Promise<{ table: string; voucher: any } | null> {
  const cash = await db.cashBook.findUnique({ where: { voucherNo }, include: { lines: { include: { account: true } }, branch: true, bookAccount: true } })
  if (cash) return { table: 'CashBook', voucher: cash }
  const bank = await db.bankBook.findUnique({ where: { voucherNo }, include: { lines: { include: { account: true } }, branch: true, bookAccount: true } })
  if (bank) return { table: 'BankBook', voucher: bank }
  const jv = await db.jV.findUnique({ where: { voucherNo }, include: { lines: { include: { account: true } }, branch: true } })
  if (jv) return { table: 'JV', voucher: jv }
  const otb = await db.openTB.findUnique({ where: { voucherNo }, include: { lines: { include: { account: true } }, branch: true } })
  if (otb) return { table: 'OpenTB', voucher: otb }
  return null
}

export async function reverseVoucher(voucherNo: string, userId: string, reason: string) {
  const found = await findVoucherByNo(voucherNo)
  if (!found) throw new Error('Voucher not found')
  const { table, voucher: v } = found
  if (v.status === 'Reversed') throw new Error('Voucher already reversed')

  const reversalNo = `${v.voucherNo}-R`
  // Check existing reversal in the same table
  let existing: any = null
  if (table === 'CashBook') existing = await db.cashBook.findUnique({ where: { voucherNo: reversalNo } })
  else if (table === 'BankBook') existing = await db.bankBook.findUnique({ where: { voucherNo: reversalNo } })
  else if (table === 'JV') existing = await db.jV.findUnique({ where: { voucherNo: reversalNo } })
  else if (table === 'OpenTB') existing = await db.openTB.findUnique({ where: { voucherNo: reversalNo } })
  if (existing) throw new Error('Voucher already reversed')

  return await db.$transaction(async (tx) => {
    let reversed: any
    const lineData = v.lines.map((l: any) => ({
      accountId: l.accountId,
      debit: l.credit,
      credit: l.debit,
      amount: l.amount,
      lineDescription: `Reversal: ${l.lineDescription || ''}`,
      taxAccountId: l.taxAccountId,
      taxRate: l.taxRate,
      taxAmount: l.taxAmount,
      status: 'Active',
    }))

    if (table === 'CashBook') {
      reversed = await tx.cashBook.create({
        data: {
          voucherNo: reversalNo,
          voucherType: v.voucherType,
          voucherDate: new Date(),
          branchId: v.branchId,
          bookAccountId: v.bookAccountId,
          description: `Reversal of ${v.voucherNo}: ${reason}`,
          reference: v.voucherNo,
          status: 'Reversed',
          reversedById: userId,
          reversedAt: new Date(),
          reversalReason: reason,
          totalDebit: v.totalCredit,
          totalCredit: v.totalDebit,
          lines: { create: lineData },
        },
      })
      await tx.cashBook.update({ where: { id: v.id }, data: { status: 'Reversed', reversedById: userId, reversedAt: new Date(), reversalReason: reason } })
    } else if (table === 'BankBook') {
      reversed = await tx.bankBook.create({
        data: {
          voucherNo: reversalNo,
          voucherType: v.voucherType,
          voucherDate: new Date(),
          branchId: v.branchId,
          bookAccountId: v.bookAccountId,
          description: `Reversal of ${v.voucherNo}: ${reason}`,
          reference: v.voucherNo,
          status: 'Reversed',
          reversedById: userId,
          reversedAt: new Date(),
          reversalReason: reason,
          totalDebit: v.totalCredit,
          totalCredit: v.totalDebit,
          lines: { create: lineData },
        },
      })
      await tx.bankBook.update({ where: { id: v.id }, data: { status: 'Reversed', reversedById: userId, reversedAt: new Date(), reversalReason: reason } })
    } else if (table === 'JV') {
      reversed = await tx.jV.create({
        data: {
          voucherNo: reversalNo,
          voucherType: 'JV',
          voucherDate: new Date(),
          branchId: v.branchId,
          description: `Reversal of ${v.voucherNo}: ${reason}`,
          reference: v.voucherNo,
          status: 'Reversed',
          reversedById: userId,
          reversedAt: new Date(),
          reversalReason: reason,
          totalDebit: v.totalCredit,
          totalCredit: v.totalDebit,
          lines: { create: lineData },
        },
      })
      await tx.jV.update({ where: { id: v.id }, data: { status: 'Reversed', reversedById: userId, reversedAt: new Date(), reversalReason: reason } })
    } else if (table === 'OpenTB') {
      // OTB doesn't support reversal; skip
      throw new Error('Opening Trial Balance vouchers cannot be reversed')
    }

    await tx.auditLog.create({
      data: { userId, action: 'REVERSE', module: 'vouchers', details: JSON.stringify({ voucherNo: v.voucherNo, reversalNo, reason }) },
    })

    return reversed
  })
}

// Get account balance from all voucher tables (Posted only)
export async function getAccountBalance(accountId: string, asOf?: Date): Promise<{ debit: number; credit: number; balance: number }> {
  const cashLines = await db.cashBookLine.findMany({
    where: { accountId, voucher: { status: 'Posted', ...(asOf ? { voucherDate: { lte: asOf } } : {}) } },
  })
  const bankLines = await db.bankBookLine.findMany({
    where: { accountId, voucher: { status: 'Posted', ...(asOf ? { voucherDate: { lte: asOf } } : {}) } },
  })
  const jvLines = await db.jVLine.findMany({
    where: { accountId, voucher: { status: 'Posted', ...(asOf ? { voucherDate: { lte: asOf } } : {}) } },
  })
  const openLines = await db.openTBLine.findMany({
    where: { accountId, voucher: { status: 'Posted', ...(asOf ? { voucherDate: { lte: asOf } } : {}) } },
  })
  const allLines = [...cashLines, ...bankLines, ...jvLines, ...openLines]
  const debit = allLines.reduce((s, l) => s + l.debit, 0)
  const credit = allLines.reduce((s, l) => s + l.credit, 0)
  return { debit, credit, balance: debit - credit }
}

export async function getAccountBalanceBetween(accountId: string, from: Date, to: Date) {
  // Opening: OTB + all posted lines before `from`
  const openLines = await db.openTBLine.findMany({ where: { accountId, voucher: { status: 'Posted' } } })
  const cashOpen = await db.cashBookLine.findMany({ where: { accountId, voucher: { status: 'Posted', voucherDate: { lt: from } } } })
  const bankOpen = await db.bankBookLine.findMany({ where: { accountId, voucher: { status: 'Posted', voucherDate: { lt: from } } } })
  const jvOpen = await db.jVLine.findMany({ where: { accountId, voucher: { status: 'Posted', voucherDate: { lt: from } } } })

  const openingDebit = [...openLines, ...cashOpen, ...bankOpen, ...jvOpen].reduce((s, l) => s + l.debit, 0)
  const openingCredit = [...openLines, ...cashOpen, ...bankOpen, ...jvOpen].reduce((s, l) => s + l.credit, 0)

  // Period
  const cashPeriod = await db.cashBookLine.findMany({ where: { accountId, voucher: { status: 'Posted', voucherDate: { gte: from, lte: to } } } })
  const bankPeriod = await db.bankBookLine.findMany({ where: { accountId, voucher: { status: 'Posted', voucherDate: { gte: from, lte: to } } } })
  const jvPeriod = await db.jVLine.findMany({ where: { accountId, voucher: { status: 'Posted', voucherDate: { gte: from, lte: to } } } })

  const debit = [...cashPeriod, ...bankPeriod, ...jvPeriod].reduce((s, l) => s + l.debit, 0)
  const credit = [...cashPeriod, ...bankPeriod, ...jvPeriod].reduce((s, l) => s + l.credit, 0)
  return { opening: openingDebit - openingCredit, debit, credit, balance: openingDebit - openingCredit + debit - credit }
}

// Unified fetch across all 4 voucher tables for listing/reporting
export async function listAllVouchers(filter: {
  voucherType?: string
  status?: string
  branchIds?: string[]
  from?: Date
  to?: Date
  search?: string
  take?: number
}): Promise<any[]> {
  const where = (modelName: string) => ({
    ...(filter.voucherType ? { voucherType: filter.voucherType } : {}),
    ...(filter.status ? { status: filter.status } : {}),
    ...(filter.branchIds ? { branchId: { in: filter.branchIds } } : {}),
    ...(filter.from || filter.to ? { voucherDate: { ...(filter.from ? { gte: filter.from } : {}), ...(filter.to ? { lte: filter.to } : {}) } } : {}),
    ...(filter.search ? { OR: [{ voucherNo: { contains: filter.search } }, { description: { contains: filter.search } }, { reference: { contains: filter.search } }] } : {}),
  })

  const [cash, bank, jv, otb] = await Promise.all([
    db.cashBook.findMany({ where: where('CashBook'), include: { branch: true, bookAccount: true, lines: { include: { account: true } } }, orderBy: { voucherDate: 'desc' }, take: filter.take ?? 200 }),
    db.bankBook.findMany({ where: where('BankBook'), include: { branch: true, bookAccount: true, lines: { include: { account: true } } }, orderBy: { voucherDate: 'desc' }, take: filter.take ?? 200 }),
    db.jV.findMany({ where: where('JV'), include: { branch: true, lines: { include: { account: true } } }, orderBy: { voucherDate: 'desc' }, take: filter.take ?? 200 }),
    db.openTB.findMany({ where: where('OpenTB'), include: { branch: true, lines: { include: { account: true } } }, orderBy: { voucherDate: 'desc' }, take: filter.take ?? 200 }),
  ])

  return [
    ...cash.map((v) => ({ ...v, _table: 'CashBook' })),
    ...bank.map((v) => ({ ...v, _table: 'BankBook' })),
    ...jv.map((v) => ({ ...v, _table: 'JV' })),
    ...otb.map((v) => ({ ...v, _table: 'OpenTB' })),
  ].sort((a, b) => b.voucherDate.getTime() - a.voucherDate.getTime())
}

export type { VoucherType, PostVoucherInput, VoucherLineInput }
