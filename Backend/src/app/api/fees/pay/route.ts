import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { postVoucher } from '@/lib/accounting'

// Pay a fee — creates auto CRV/BRV and links to the fee
// Supports: Cash | Card | Bank Transfer | Online
// Card → cardTypeId (MasterFile ExerciseCategories? no — CardTypes) required
// Bank Transfer → bankMasterId (MasterFile Banks) required
export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('fees.post')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { feeId, amount, method, accountId, reference, paymentDate, cardTypeId, bankMasterId } = await req.json()
  if (!feeId || !amount || !method || !accountId) {
    return NextResponse.json({ error: 'feeId, amount, method, accountId required' }, { status: 400 })
  }
  if (!['Cash', 'Card', 'Bank Transfer', 'Online'].includes(method)) {
    return NextResponse.json({ error: 'method must be Cash, Card, Bank Transfer, or Online' }, { status: 400 })
  }

  // Backend validation per spec §6
  let cardTypeName: string | null = null
  let bankMasterName: string | null = null
  if (method === 'Card') {
    if (!cardTypeId) {
      return NextResponse.json({ error: 'Card Type is required when Payment Method is Card' }, { status: 400 })
    }
    const cardType = await db.masterFile.findUnique({ where: { id: cardTypeId } })
    if (!cardType || cardType.masterType !== 'CardTypes') {
      return NextResponse.json({ error: 'Invalid Card Type' }, { status: 400 })
    }
    if (!cardType.isActive) {
      return NextResponse.json({ error: 'Selected Card Type is inactive' }, { status: 400 })
    }
    cardTypeName = cardType.name
  }
  if (method === 'Bank Transfer') {
    if (!bankMasterId) {
      return NextResponse.json({ error: 'Bank is required when Payment Method is Bank Transfer' }, { status: 400 })
    }
    const bank = await db.masterFile.findUnique({ where: { id: bankMasterId } })
    if (!bank || bank.masterType !== 'Banks') {
      return NextResponse.json({ error: 'Invalid Bank' }, { status: 400 })
    }
    if (!bank.isActive) {
      return NextResponse.json({ error: 'Selected Bank is inactive' }, { status: 400 })
    }
    bankMasterName = bank.name
  }

  const fee = await db.fee.findUnique({ where: { id: feeId }, include: { member: true, branch: true } })
  if (!fee) return NextResponse.json({ error: 'Fee not found' }, { status: 404 })

  const payAmount = Number(amount)
  if (payAmount <= 0 || payAmount > fee.balance + 0.01) {
    return NextResponse.json({ error: 'Invalid payment amount' }, { status: 400 })
  }

  // Look up account mappings
  const mappings = await db.accountMapping.findMany({ where: { OR: [{ branchId: fee.branchId }, { branchId: null }] } })
  const pickMapping = (key: string) => {
    const branchSpecific = mappings.find(m => m.key === key && m.branchId === fee.branchId)
    return branchSpecific || mappings.find(m => m.key === key && m.branchId === null)
  }
  const feeIncomeMapping = pickMapping('feeIncome')
  const feeReceivableMapping = pickMapping('feeReceivable')
  if (!feeIncomeMapping) return NextResponse.json({ error: 'Account mapping "feeIncome" not configured' }, { status: 500 })

  // Determine voucher type: Cash → CRV, Card/Bank Transfer/Online → BRV
  const voucherType = method === 'Cash' ? 'CRV' : 'BRV'

  const lines: Array<{ accountId: string; debit: number; credit: number; lineDescription?: string }> = []
  lines.push({ accountId, debit: payAmount, credit: 0, lineDescription: `Fee payment: ${fee.feeNo} - ${fee.member.firstName} ${fee.member.lastName || ''}` })
  if (feeReceivableMapping && fee.status !== 'Unpaid') {
    lines.push({ accountId: feeReceivableMapping.accountId, debit: 0, credit: payAmount, lineDescription: `Receivable cleared: ${fee.feeNo}` })
  } else {
    lines.push({ accountId: feeIncomeMapping.accountId, debit: 0, credit: payAmount, lineDescription: `Fee income: ${fee.feeNo}` })
  }

  try {
    const voucher = await postVoucher({
      voucherType: voucherType as any,
      voucherDate: paymentDate ? new Date(paymentDate) : new Date(),
      branchId: fee.branchId,
      bookAccountId: accountId,
      description: `Fee payment — ${fee.feeNo} — ${fee.member.firstName} ${fee.member.lastName || ''} — ${method}${cardTypeName ? ` (${cardTypeName})` : ''}${bankMasterName ? ` (${bankMasterName})` : ''}`,
      reference: reference || fee.feeNo,
      lines,
      postedById: session.id,
      status: 'Posted',
    })

    const newPaid = fee.paidAmount + payAmount
    const newBalance = fee.amount - fee.discount - newPaid
    const newStatus = newBalance <= 0.01 ? 'Paid' : 'Partial'
    const updatedFee = await db.fee.update({
      where: { id: fee.id },
      data: {
        paidAmount: newPaid,
        balance: newBalance,
        status: newStatus,
        paymentMethod: method,
        paymentAccountId: accountId,
        paymentDate: paymentDate ? new Date(paymentDate) : new Date(),
        reference: reference || fee.reference,
        voucherId: voucher.id,
        payments: {
          create: {
            voucherId: voucher.id,
            amount: payAmount,
            method,
            accountId,
            cardTypeId: cardTypeId || null,
            cardTypeName: cardTypeName,
            bankMasterId: bankMasterId || null,
            bankMasterName: bankMasterName,
          },
        },
      },
      include: { payments: true },
    })

    return NextResponse.json({ fee: updatedFee, voucher })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Failed to post fee payment' }, { status: 400 })
  }
}
