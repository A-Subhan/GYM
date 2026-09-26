import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

const BILL_TYPES = [
  { type: 'Sales Bill', isDebit: false },
  { type: 'Purchase Bill', isDebit: true },
  { type: 'Credit Note', isDebit: false },
  { type: 'Debit Note', isDebit: true },
  { type: 'Sales Credit Note', isDebit: false },
  { type: 'Sales Debit Note', isDebit: true },
  { type: 'Opening Adjustment Debit', isDebit: true },
  { type: 'Opening Adjustment Credit', isDebit: false },
  { type: 'Purchase Debit Note', isDebit: true },
  { type: 'Purchase Credit Note', isDebit: false },
]

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const accountId = url.searchParams.get('accountId')
  const bills = await db.knockOffBill.findMany({
    where: { ...(accountId ? { accountId } : {}) },
    include: { account: true, branch: true },
    orderBy: { createdAt: 'desc' },
  })
  return NextResponse.json({ bills, billTypes: BILL_TYPES })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('vouchers.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  if (!data.accountId || !data.branchId || !data.billNumber || !data.billType || !data.amount) {
    return NextResponse.json({ error: 'accountId, branchId, billNumber, billType, amount required' }, { status: 400 })
  }

  // Auto-determine debit/credit from bill type
  const billTypeMap = BILL_TYPES.find(b => b.type === data.billType)
  if (!billTypeMap) return NextResponse.json({ error: 'Invalid bill type' }, { status: 400 })

  // Validate description max 20 chars
  if (data.description && String(data.description).length > 20) {
    return NextResponse.json({ error: 'Description must be max 20 characters' }, { status: 400 })
  }

  // Generate bill ID: OTB/BranchID/000001
  const count = await db.knockOffBill.count({ where: { branchId: data.branchId } })
  const billId = `OTB/${data.branchId}/${String(count + 1).padStart(6, '0')}`

  const bill = await db.knockOffBill.create({
    data: {
      billId,
      accountId: data.accountId,
      branchId: data.branchId,
      billNumber: data.billNumber,
      referenceNumber: data.referenceNumber || null,
      billType: data.billType,
      amount: Number(data.amount),
      referenceDate: data.referenceDate ? new Date(data.referenceDate) : null,
      dueDate: data.dueDate ? new Date(data.dueDate) : null,
      description: data.description ? String(data.description).slice(0, 20) : null,
      isDebit: billTypeMap.isDebit,
      outstandingAmount: Number(data.amount),
      adjustedAmount: 0,
      status: 'Open',
    },
    include: { account: true },
  })

  await db.auditLog.create({
    data: { userId: session.id, action: 'CREATE', module: 'knockoff', details: JSON.stringify({ billId, accountId: data.accountId }) },
  })

  return NextResponse.json({ bill })
}

export async function DELETE(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const id = url.searchParams.get('id')
  if (!id) return NextResponse.json({ error: 'id required' }, { status: 400 })
  await db.knockOffBill.delete({ where: { id } })
  return NextResponse.json({ success: true })
}
