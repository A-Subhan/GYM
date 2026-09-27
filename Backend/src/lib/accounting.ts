import { db } from './db'
import type { Prisma } from '@prisma/client'

// Voucher type → which side the book account goes on
// CRV (Cash Receipt): book/cash account is DEBITED (cash in); detail lines are CREDITED
// CPV (Cash Payment): book/cash account is CREDITED (cash out); detail lines are DEBITED
// BRV (Bank Receipt): book/bank account is DEBITED; detail lines are CREDITED
// BPV (Bank Payment): book/bank account is CREDITED; detail lines are DEBITED
// JV: no book account, lines specify both sides (user enters Dr and Cr manually)
// OTB: Opening Trial Balance — like JV (user specifies both sides)

type VoucherType = 'CRV' | 'CPV' | 'BRV' | 'BPV' | 'JV' | 'OTB' | 'POS-SALE' | 'FEE'

interface VoucherLineInput {
  accountId: string
  amount?: number        // single amount field for CRV/CPV/BRV/BPV (determines Dr/Cr by voucher type)
  debit?: number         // used for JV/OTB (manual)
  credit?: number        // used for JV/OTB (manual)
  lineDescription?: string
  title?: string
  reference?: string
  taxAccountId?: string
  taxRate?: number
  taxAmount?: number
  // cheque fields per line
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
  cheque?: { chequeNo: string; chequeDate: Date; bankName?: string; amount: number } | null
  // for edit mode: existing voucher ID to update
  existingVoucherId?: string
}

// Returns true if this voucher type uses a Book Account (and therefore auto-generates the book line)
function usesBookAccount(vt: VoucherType): boolean {
  return vt === 'CRV' || vt === 'CPV' || vt === 'BRV' || vt === 'BPV'
}

// Returns true if the book account should be DEBITED (CRV/BRV); false if CREDITED (CPV/BPV)
function bookAccountIsDebited(vt: VoucherType): boolean {
  return vt === 'CRV' || vt === 'BRV'
}

export async function postVoucher(input: PostVoucherInput) {
  const isEdit = !!input.existingVoucherId

  // Build the final lines that will be persisted.
  // For CRV/CPV/BRV/BPV: detail lines come in with `amount` only. We auto-generate the book-account line.
  // For JV/OTB: lines come in with explicit debit/credit. We do NOT add a book line.
  let finalLines: Array<{
    accountId: string
    debit: number
    credit: number
    lineDescription?: string
    title?: string
    reference?: string
    amount: number
    taxAccountId?: string
    taxRate: number
    taxAmount: number
    chequeNo?: string
    chequeAmount?: number
    chequeBankName?: string
    chequeStatus?: string
    status: string
    isBookLine?: boolean
  }> = []

  if (usesBookAccount(input.voucherType)) {
    if (!input.bookAccountId) {
      throw new Error(`Book account required for ${input.voucherType}`)
    }
    if (input.lines.length === 0) throw new Error('Voucher must have at least one detail line')

    // Convert each detail line: amount → debit or credit based on voucher type
    // For CRV/BRV: detail lines are CREDITED (book is debited)
    // For CPV/BPV: detail lines are DEBITED (book is credited)
    const detailIsCredit = bookAccountIsDebited(input.voucherType) // CRV/BRV → detail credited
    const detailLines = input.lines.map((l) => {
      const amt = Number(l.amount || 0)
      return {
        accountId: l.accountId,
        debit: detailIsCredit ? 0 : amt,
        credit: detailIsCredit ? amt : 0,
        amount: amt,
        lineDescription: l.lineDescription,
        title: l.title,
        reference: l.reference,
        taxAccountId: l.taxAccountId,
        taxRate: Number(l.taxRate) || 0,
        taxAmount: Number(l.taxAmount) || 0,
        chequeNo: l.chequeNo,
        chequeAmount: l.chequeAmount ? Number(l.chequeAmount) : null,
        chequeBankName: l.chequeBankName,
        chequeStatus: l.chequeStatus,
        status: l.status || 'Active',
      }
    })
    const totalDetail = detailLines.reduce((s, l) => s + l.debit + l.credit, 0)
    // Auto-generate the book account line on the opposite side
    const bookLine = {
      accountId: input.bookAccountId,
      debit: detailIsCredit ? totalDetail : 0,        // CRV/BRV: book debited
      credit: detailIsCredit ? 0 : totalDetail,        // CPV/BPV: book credited
      amount: totalDetail,
      lineDescription: `Book account — ${input.voucherType}`,
      title: undefined,
      reference: undefined,
      taxAccountId: undefined,
      taxRate: 0,
      taxAmount: 0,
      chequeNo: undefined,
      chequeAmount: undefined,
      chequeBankName: undefined,
      chequeStatus: undefined,
      status: 'Active',
      isBookLine: true,
    }
    finalLines = [bookLine, ...detailLines]
  } else {
    // JV / OTB / POS-SALE / FEE: lines come with explicit debit/credit
    if (input.lines.length === 0) throw new Error('Voucher must have at least one line')
    finalLines = input.lines.map((l) => ({
      accountId: l.accountId,
      debit: Number(l.debit) || 0,
      credit: Number(l.credit) || 0,
      amount: Number(l.amount) || 0,
      lineDescription: l.lineDescription,
      title: l.title,
      reference: l.reference,
      taxAccountId: l.taxAccountId,
      taxRate: Number(l.taxRate) || 0,
      taxAmount: Number(l.taxAmount) || 0,
      chequeNo: l.chequeNo,
      chequeAmount: l.chequeAmount ? Number(l.chequeAmount) : undefined,
      chequeBankName: l.chequeBankName,
      chequeStatus: l.chequeStatus,
      status: l.status || 'Active',
    }))
  }

  // validate balanced
  const totalDebit = finalLines.reduce((s, l) => s + l.debit, 0)
  const totalCredit = finalLines.reduce((s, l) => s + l.credit, 0)
  if (Math.abs(totalDebit - totalCredit) > 0.01) {
    throw new Error(`Voucher not balanced: debit=${totalDebit}, credit=${totalCredit}`)
  }

  // generate voucher number (only on create)
  let voucherNo: string
  if (isEdit) {
    const existing = await db.voucher.findUnique({ where: { id: input.existingVoucherId } })
    if (!existing) throw new Error('Voucher not found for edit')
    voucherNo = existing.voucherNo
  } else {
    const prefix = `${input.voucherType}-${new Date().getFullYear().toString().slice(-2)}-`
    const count = await db.voucher.count({ where: { voucherNo: { startsWith: prefix } } })
    voucherNo = `${prefix}${String(count + 1).padStart(5, '0')}`
  }

  return await db.$transaction(async (tx) => {
    let voucher: any
    if (isEdit) {
      // Delete old lines, then recreate
      await tx.voucherLine.deleteMany({ where: { voucherId: input.existingVoucherId } })
      await tx.cheque.deleteMany({ where: { voucherId: input.existingVoucherId } })
      voucher = await tx.voucher.update({
        where: { id: input.existingVoucherId },
        data: {
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
              title: l.title,
              reference: l.reference,
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
          cheques: input.cheque
            ? { create: { chequeNo: input.cheque.chequeNo, chequeDate: input.cheque.chequeDate, bankName: input.cheque.bankName, amount: input.cheque.amount, status: 'Hold' } }
            : undefined,
        },
        include: { lines: { include: { account: true } }, cheques: true },
      })
    } else {
      voucher = await tx.voucher.create({
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
              title: l.title,
              reference: l.reference,
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
          cheques: input.cheque
            ? { create: { chequeNo: input.cheque.chequeNo, chequeDate: input.cheque.chequeDate, bankName: input.cheque.bankName, amount: input.cheque.amount, status: 'Hold' } }
            : undefined,
        },
        include: { lines: { include: { account: true } }, cheques: true },
      })
    }

    await tx.auditLog.create({
      data: {
        userId: input.postedById,
        action: isEdit ? 'UPDATE' : 'POST',
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

// Soft-delete a Draft voucher (only Drafts can be deleted; Posted must be reversed)
export async function deleteVoucher(voucherId: string, userId: string) {
  const v = await db.voucher.findUnique({ where: { id: voucherId } })
  if (!v) throw new Error('Voucher not found')
  if (v.status === 'Posted') throw new Error('Posted vouchers cannot be deleted. Use reversal instead.')
  if (v.status === 'Reversed') throw new Error('Reversed vouchers cannot be deleted.')
  return await db.$transaction(async (tx) => {
    await tx.voucherLine.deleteMany({ where: { voucherId } })
    await tx.cheque.deleteMany({ where: { voucherId } })
    await tx.voucher.delete({ where: { id: voucherId } })
    await tx.auditLog.create({
      data: { userId, action: 'DELETE', module: 'vouchers', details: JSON.stringify({ voucherId, voucherNo: v.voucherNo }) },
    })
    return { success: true }
  })
}

// Post a Draft voucher (change status to Posted)
export async function postDraftVoucher(voucherId: string, userId: string) {
  const v = await db.voucher.findUnique({ where: { id: voucherId }, include: { lines: true } })
  if (!v) throw new Error('Voucher not found')
  if (v.status !== 'Draft') throw new Error('Only Draft vouchers can be posted')
  const totalDebit = v.lines.reduce((s, l) => s + l.debit, 0)
  const totalCredit = v.lines.reduce((s, l) => s + l.credit, 0)
  if (Math.abs(totalDebit - totalCredit) > 0.01) throw new Error('Voucher not balanced; cannot post')
  return await db.$transaction(async (tx) => {
    const updated = await tx.voucher.update({
      where: { id: voucherId },
      data: { status: 'Posted', postedById: userId, postedAt: new Date(), totalDebit, totalCredit },
    })
    await tx.auditLog.create({
      data: { userId, action: 'POST', module: 'vouchers', details: JSON.stringify({ voucherId, voucherNo: v.voucherNo }) },
    })
    return updated
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
