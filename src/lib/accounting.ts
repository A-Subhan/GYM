import { db } from './db'
import type { Prisma } from '@prisma/client'

// Voucher type → which side the book account goes on
// CRV (Cash Receipt): book/cash account is DEBITED (cash in)
// CPV (Cash Payment): book/cash account is CREDITED (cash out)
// BRV (Bank Receipt): book/bank account is DEBITED
// BPV (Bank Payment): book/bank account is CREDITED
// JV: no book account, lines specify both sides

type VoucherType = 'CRV' | 'CPV' | 'BRV' | 'BPV' | 'JV' | 'POS-SALE' | 'FEE'

interface VoucherLineInput {
  accountId: string
  debit: number
  credit: number
  lineDescription?: string
  taxAccountId?: string
  taxRate?: number
  taxAmount?: number
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
  cheque?: { chequeNo: string; chequeDate: Date; bankName?: string; amount: number } | null
}

export async function postVoucher(input: PostVoucherInput) {
  // validate balanced
  const totalDebit = input.lines.reduce((s, l) => s + (l.debit || 0), 0)
  const totalCredit = input.lines.reduce((s, l) => s + (l.credit || 0), 0)
  if (Math.abs(totalDebit - totalCredit) > 0.01) {
    throw new Error(`Voucher not balanced: debit=${totalDebit}, credit=${totalCredit}`)
  }
  if (input.lines.length === 0) throw new Error('Voucher must have at least one line')

  // validate voucher type / book account rules
  if (['CRV', 'CPV', 'BRV', 'BPV'].includes(input.voucherType) && !input.bookAccountId) {
    throw new Error(`Book account required for ${input.voucherType}`)
  }

  // generate voucher number: <TYPE>-<YY>-<SEQ>
  const prefix = `${input.voucherType}-${new Date().getFullYear().toString().slice(-2)}-`
  const count = await db.voucher.count({ where: { voucherNo: { startsWith: prefix } } })
  const voucherNo = `${prefix}${String(count + 1).padStart(5, '0')}`

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
          create: input.lines.map((l) => ({
            accountId: l.accountId,
            debit: l.debit,
            credit: l.credit,
            lineDescription: l.lineDescription,
            taxAccountId: l.taxAccountId,
            taxRate: l.taxRate ?? 0,
            taxAmount: l.taxAmount ?? 0,
          })),
        },
        cheques: input.cheque
          ? { create: { chequeNo: input.cheque.chequeNo, chequeDate: input.cheque.chequeDate, bankName: input.cheque.bankName, amount: input.cheque.amount, status: 'Hold' } }
          : undefined,
      },
      include: { lines: true, cheques: true },
    })

    // For POS sales, deduct inventory
    if (input.voucherType === 'POS-SALE' && input.reference) {
      // reference carries POS sale ID; handled by caller
    }

    // Audit
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
        totalDebit: v.totalCredit, // swap sides
        totalCredit: v.totalDebit,
        lines: {
          create: v.lines.map((l) => ({
            accountId: l.accountId,
            debit: l.credit,
            credit: l.debit,
            lineDescription: `Reversal: ${l.lineDescription || ''}`,
            taxAccountId: l.taxAccountId,
            taxRate: l.taxRate,
            taxAmount: l.taxAmount,
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

// Account balance helper — sum of posted lines
export async function getAccountBalance(accountId: string, asOf?: Date): Promise<{ debit: number; credit: number; balance: number }> {
  const lines = await db.voucherLine.findMany({
    where: {
      accountId,
      voucher: {
        status: 'Posted',
        ...(asOf ? { voucherDate: { lte: asOf } } : {}),
      },
    },
  })
  const debit = lines.reduce((s, l) => s + l.debit, 0)
  const credit = lines.reduce((s, l) => s + l.credit, 0)
  return { debit, credit, balance: debit - credit }
}

// Account balance over a period
export async function getAccountBalanceBetween(
  accountId: string,
  from: Date,
  to: Date,
): Promise<{ debit: number; credit: number; balance: number; opening: number }> {
  const openingLines = await db.voucherLine.findMany({
    where: { accountId, voucher: { status: 'Posted', voucherDate: { lt: from } } },
  })
  const periodLines = await db.voucherLine.findMany({
    where: { accountId, voucher: { status: 'Posted', voucherDate: { gte: from, lte: to } } },
  })
  const openingDebit = openingLines.reduce((s, l) => s + l.debit, 0)
  const openingCredit = openingLines.reduce((s, l) => s + l.credit, 0)
  const debit = periodLines.reduce((s, l) => s + l.debit, 0)
  const credit = periodLines.reduce((s, l) => s + l.credit, 0)
  return {
    opening: openingDebit - openingCredit,
    debit,
    credit,
    balance: openingDebit - openingCredit + debit - credit,
  }
}

export type { VoucherType, PostVoucherInput, VoucherLineInput }
