import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const branchesParam = url.searchParams.get('branches')
  const status = url.searchParams.get('status')
  const memberId = url.searchParams.get('memberId')
  const allowed = getSelectedBranchIds(session, branchesParam)

  const fees = await db.fee.findMany({
    where: {
      ...(allowed ? { branchId: { in: allowed } } : {}),
      ...(status ? { status } : {}),
      ...(memberId ? { memberId } : {}),
    },
    include: { member: true, branch: true, voucher: true, payments: true },
    orderBy: { dueDate: 'desc' },
    take: 200,
  })
  return NextResponse.json({ fees })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('fees.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()

  const member = await db.member.findUnique({ where: { id: data.memberId }, include: { membershipPlan: true, branch: true } })
  if (!member) return NextResponse.json({ error: 'Member not found' }, { status: 404 })

  const billingPeriodStart = data.billingPeriodStart ? new Date(data.billingPeriodStart) : new Date()
  const billingPeriodEnd = data.billingPeriodEnd ? new Date(data.billingPeriodEnd) : new Date(billingPeriodStart.getTime() + 30 * 24 * 60 * 60 * 1000)
  const amount = Number(data.amount) || member.membershipPlan?.amount || 0
  const discount = Number(data.discount) || 0
  const dueDate = data.dueDate ? new Date(data.dueDate) : billingPeriodEnd

  // Generate fee number
  const count = await db.fee.count()
  const feeNo = `F-${String(count + 1).padStart(5, '0')}`

  const fee = await db.fee.create({
    data: {
      feeNo,
      memberId: member.id,
      branchId: member.branchId,
      billingPeriodStart,
      billingPeriodEnd,
      amount,
      discount,
      paidAmount: 0,
      balance: amount - discount,
      dueDate,
      status: 'Unpaid',
    },
  })

  await db.auditLog.create({
    data: { userId: session.id, action: 'CREATE', module: 'fees', details: JSON.stringify({ id: fee.id, feeNo }) },
  })
  return NextResponse.json({ fee })
}
