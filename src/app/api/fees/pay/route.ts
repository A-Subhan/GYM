import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { postVoucher } from '@/lib/accounting'

// Pay a fee — creates auto CRV/BRV and links to the fee
export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('fees.post')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { feeId, amount, method, accountId, reference, paymentDate } = await req.json()
  if (!feeId || !amount || !method || !accountId) {
    return NextResponse.json({ error: 'feeId, amount, method, accountId required' }, { status: 400 })
  }
  if (!['Cash', 'Card', 'Bank Transfer'].includes(method)) {
    return NextResponse.json({ error: 'method must be Cash, Card, or Bank Transfer' }, { status: 400 })
  }

  const fee = await db.fee.findUnique({ where: { id: feeId }, include: { member: true, branch: true } })
  if (!fee) return NextResponse.json({ error: 'Fee not found' }, { status: 404 })

  const payAmount = Number(amount)
  if (payAmount <= 0 || payAmount > fee.balance + 0.01) {
    return NextResponse.json({ error: 'Invalid payment amount' }, { status: 400 })
  }

  // Look up account mappings
  const mappings = await db.accountMapping.findMany({ where: { OR: [{ branchId: fee.branchId }, { branchId: null }] } })
  // Prefer branch-specific mapping; fallback to global
  const pickMapping = (key: string) => {
    const branchSpecific = mappings.find(m => m.key === key && m.branchId === fee.branchId)
    return branchSpecific || mappings.find(m => m.key === key && m.branchId === null)
  }
  const feeIncomeMapping = pickMapping('feeIncome')
  const feeReceivableMapping = pickMapping('feeReceivable')
  if (!feeIncomeMapping) return NextResponse.json({ error: 'Account mapping "feeIncome" not configured' }, { status: 500 })

  // Build voucher
  // Cash Receipt: Debit Cash/Bank (the account user paid into), Credit Fee Income
  // If fee already existed as receivable (member had outstanding), we debit Cash and credit Receivable
  // For simplicity, we post: Debit [account user paid into], Credit [feeIncome or feeReceivable]
  const voucherType = method === 'Cash' ? 'CRV' : 'BRV'
  const lines: Array<{ accountId: string; debit: number; credit: number; lineDescription?: string }> = []
  // Debit the cash/bank account user paid into
  lines.push({ accountId, debit: payAmount, credit: 0, lineDescription: `Fee payment: ${fee.feeNo} - ${fee.member.firstName} ${fee.member.lastName || ''}` })
  // Credit fee income (or receivable if we treat outstanding as receivable)
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
      description: `Fee payment — ${fee.feeNo} — ${fee.member.firstName} ${fee.member.lastName || ''}`,
      reference: reference || fee.feeNo,
      lines,
      postedById: session.id,
      status: 'Posted',
    })

    // Update fee
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
        voucherNo: voucher.voucherNo,
        payments: { create: { voucherNo: voucher.voucherNo, amount: payAmount, method, accountId } },
      },
      include: { payments: true },
    })

    return NextResponse.json({ fee: updatedFee, voucher })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Failed to post fee payment' }, { status: 400 })
  }
}
