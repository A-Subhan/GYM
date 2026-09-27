import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const status = url.searchParams.get('status')
  const staffId = url.searchParams.get('staffId')
  const leaves = await db.leave.findMany({
    where: { ...(status ? { status } : {}), ...(staffId ? { staffId } : {}) },
    include: { staff: true },
    orderBy: { createdAt: 'desc' },
    take: 200,
  })
  return NextResponse.json({ leaves })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('leaves.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.staffId || !data.leaveType || !data.fromDate || !data.toDate) return NextResponse.json({ error: 'staffId, leaveType, fromDate, toDate required' }, { status: 400 })
  const from = new Date(data.fromDate)
  const to = new Date(data.toDate)
  if (to < from) return NextResponse.json({ error: 'toDate must be after fromDate' }, { status: 400 })
  const days = Math.ceil((to.getTime() - from.getTime()) / (24 * 60 * 60 * 1000)) + 1
  const leave = await db.leave.create({
    data: {
      staffId: data.staffId,
      leaveType: data.leaveType,
      fromDate: from,
      toDate: to,
      days,
      reason: data.reason,
      status: 'Pending',
    },
    include: { staff: true },
  })
  return NextResponse.json({ leave })
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('leaves.approve')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const { id, status, reason } = await req.json()
  if (!['Approved', 'Rejected'].includes(status)) return NextResponse.json({ error: 'Invalid status' }, { status: 400 })
  const leave = await db.leave.update({
    where: { id },
    data: { status, approvedBy: session.id, approvedAt: new Date(), reason: reason || undefined },
  })
  await db.auditLog.create({ data: { userId: session.id, action: status.toUpperCase(), module: 'leaves', details: JSON.stringify({ id }) } })
  return NextResponse.json({ leave })
}
