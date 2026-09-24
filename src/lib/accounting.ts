import { db } from './db'
import type { Prisma } from '@prisma/client'

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
function generateVoucherNo(vt: string, branchId: string, date: Date): string {
  const prefix = vt
  const monthYear = String(date.getMonth() + 1).padStart(2, '0') + String(date.getFullYear()).slice(-2)
  return `${prefix}/${branchId}/${monthYear}/000001` // simplified — would need counter in production
}

export async function postVoucher(input: PostVoucherInput) {
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

  const totalDebit = finalLines.reduce((s, l) => s + l.debit, 0)
  const totalCredit = finalLines.reduce((s, l) => s + l.credit, 0)
  // For OTB, don't enforce balance. For all others, enforce.
  if (input.voucherType !== 'OTB' && Math.abs(totalDebit - totalCredit) > 0.01) {
    throw new Error(`Voucher not balanced: debit=${totalDebit}, credit=${totalCredit}`)
  }

  // Generate voucher number
  const prefix = input.voucherType
  const monthYear = String(input.voucherDate.getMonth() + 1).padStart(2, '0') + String(input.voucherDate.getFullYear()).slice(-2)
  const count = await db.voucher.count({ where: { voucherNo: { startsWith: `${prefix}/${input.branchId}/${monthYear}/` } } })
  const voucherNo = `${prefix}/${input.branchId}/${monthYear}/${String(count + 1).padStart(6, '0')}`

  return await db.$transaction(async (tx) => {
    const voucher = await tx.voucher.create({
      data: {
        voucherNo,
        voucherType: input.voucherType,
        voucherDate: input.voucherDate,
        branchId: input.branchId,
        bookAccountId: input.bookAccountId ?? null,
        description: input.description,
        reference: input.reference,
        status: input.status ?? 'Posted',
        postedById: input.status === 'Draft' ? null : input.postedById,
        postedAt: input.status === 'Draft' ? null : new Date(),
        totalDebit,
        totalCredit,
        lines: {
          create: finalLines.map((l) => ({
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
          })),
        },
      },
      include: { lines: true, cheques: true },
    })

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

export async function reverseVoucher(voucherId: string, userId: string, reason: string) {
  return await db.$transaction(async (tx) => {
    const v = await tx.voucher.findUnique({ where: { id: voucherId }, include: { lines: true } })
    if (!v) throw new Error('Voucher not found')
    if (v.status === 'Reversed') throw new Error('Voucher already reversed')

    const reversalNo = `${v.voucherNo}-R`
    const existing = await tx.voucher.findUnique({ where: { voucherNo: reversalNo } })
    if (existing) throw new Error('Voucher already reversed')

    const reversed = await tx.voucher.create({
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
        lines: {
          create: v.lines.map((l) => ({
            accountId: l.accountId,
            debit: l.credit,
            credit: l.debit,
            amount: l.amount,
            lineDescription: `Reversal: ${l.lineDescription || ''}`,
            taxAccountId: l.taxAccountId,
            taxRate: l.taxRate,
            taxAmount: l.taxAmount,
            status: 'Active',
          })),
        },
      },
    })

    await tx.voucher.update({ where: { id: voucherId }, data: { status: 'Reversed', reversedById: userId, reversedAt: new Date(), reversalReason: reason } })

    await tx.auditLog.create({
      data: { userId, action: 'REVERSE', module: 'vouchers', details: JSON.stringify({ voucherId, reversalNo, reason }) },
    })

    return reversed
  })
}

export async function deleteVoucher(voucherId: string, userId: string) {
  const v = await db.voucher.findUnique({ where: { id: voucherId } })
  if (!v) throw new Error('Voucher not found')
  if (v.status === 'Posted') throw new Error('Posted vouchers cannot be deleted. Use reversal instead.')
  if (v.status === 'Reversed') throw new Error('Reversed vouchers cannot be deleted.')
  return await db.$transaction(async (tx) => {
    await tx.voucherLine.deleteMany({ where: { voucherId } })
    await tx.cheque.deleteMany({ where: { voucherId } })
    await tx.voucher.delete({ where: { id: voucherId } })
    await tx.auditLog.create({ data: { userId, action: 'DELETE', module: 'vouchers', details: JSON.stringify({ voucherId, voucherNo: v.voucherNo }) } })
    return { success: true }
  })
}

export async function getAccountBalance(accountId: string, asOf?: Date): Promise<{ debit: number; credit: number; balance: number }> {
  const lines = await db.voucherLine.findMany({
    where: { accountId, voucher: { status: 'Posted', ...(asOf ? { voucherDate: { lte: asOf } } : {}) } },
  })
  const debit = lines.reduce((s, l) => s + l.debit, 0)
  const credit = lines.reduce((s, l) => s + l.credit, 0)
  return { debit, credit, balance: debit - credit }
}

export async function getAccountBalanceBetween(accountId: string, from: Date, to: Date) {
  const openingLines = await db.voucherLine.findMany({ where: { accountId, voucher: { status: 'Posted', voucherDate: { lt: from } } } })
  const periodLines = await db.voucherLine.findMany({ where: { accountId, voucher: { status: 'Posted', voucherDate: { gte: from, lte: to } } } })
  const openingDebit = openingLines.reduce((s, l) => s + l.debit, 0)
  const openingCredit = openingLines.reduce((s, l) => s + l.credit, 0)
  const debit = periodLines.reduce((s, l) => s + l.debit, 0)
  const credit = periodLines.reduce((s, l) => s + l.credit, 0)
  return { opening: openingDebit - openingCredit, debit, credit, balance: openingDebit - openingCredit + debit - credit }
}

export type { VoucherType, PostVoucherInput, VoucherLineInput }
