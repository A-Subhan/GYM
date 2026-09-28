import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { postBookVoucher } from '@/lib/accounting'

// Pay a fee — posts an auto CRV (Cash) or BRV (Card/Bank Transfer/Online) book
// voucher and links it to the fee via bookVoucherId.
//   Cash               → CRV, book account = mapped `cashAccount`
//   Card / Bank / Online → BRV, book account = mapped `bankAccount`
// Detail line (auto-credited by the book lib): mapped `feeReceivable`
// (fallback: mapped `feeIncome`). Tax heads are NOT applied on fee payments.
export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('fees.post')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { feeId, amount, method, accountId, reference, paymentDate, cardTypeId, bankMasterId } = await req.json()
  if (!feeId || !amount || !method) {
    return NextResponse.json({ error: 'feeId, amount, method required' }, { status: 400 })
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

  // Account mappings (branch-scoped first, then global null-branch)
  const mappings = await db.accountMapping.findMany({ where: { OR: [{ branchId: fee.branchId }, { branchId: null }] } })
  const pickMapping = (key: string) => {
    const branchSpecific = mappings.find(m => m.key === key && m.branchId === fee.branchId)
    return branchSpecific || mappings.find(m => m.key === key && m.branchId === null)
  }
  const cashMapping = pickMapping('cashAccount')
  const bankMapping = pickMapping('bankAccount')
  const feeIncomeMapping = pickMapping('feeIncome')
  const feeReceivableMapping = pickMapping('feeReceivable')

  // Book account: Cash → cashAccount; Card/Bank Transfer/Online → bankAccount
  const voucherType = method === 'Cash' ? 'CRV' as const : 'BRV' as const
  const bookMapping = method === 'Cash' ? cashMapping : bankMapping
  if (!bookMapping) {
    return NextResponse.json({ error: `Account mapping "${method === 'Cash' ? 'cashAccount' : 'bankAccount'}" not configured` }, { status: 500 })
  }
  const bookChartId = bookMapping.accountId

  // Counter (detail) line: feeReceivable if configured, else feeIncome
  const detailMapping = feeReceivableMapping || feeIncomeMapping
  if (!detailMapping) {
    return NextResponse.json({ error: 'Account mapping "feeReceivable" (or "feeIncome") not configured' }, { status: 500 })
  }

  try {
    const voucher = await postBookVoucher({
      voucherType,
      voucherDate: paymentDate ? new Date(paymentDate) : new Date(),
      branchId: fee.branchId,
      branchCode: fee.branch.code,
      bookChartId,
      description: `Fee payment — ${fee.id} — ${fee.member.firstName} ${fee.member.lastName || ''} — ${method}${cardTypeName ? ` (${cardTypeName})` : ''}${bankMasterName ? ` (${bankMasterName})` : ''}`.slice(0, 250),
      reference: reference || fee.id,
      paymentMode: method === 'Cash' ? 'Cash' : 'Online Transfer',
      lines: [
        {
          accountId: detailMapping.accountId,
          amount: payAmount,
          lineDescription: `Fee payment ${fee.id}`,
          billType: 'Receipt',
        },
      ],
      postedById: session.id,
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
        paymentAccountId: bookChartId,
        paymentDate: paymentDate ? new Date(paymentDate) : new Date(),
        reference: reference || fee.reference,
        bookVoucherId: voucher.id,
        payments: {
          create: {
            bookVoucherId: voucher.id,
            amount: payAmount,
            method,
            accountId: bookChartId,
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
