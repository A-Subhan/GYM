import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const status = url.searchParams.get('status')
  const staffId = url.searchParams.get('staffId')
  const records = await db.overtime.findMany({
    where: { ...(status ? { status } : {}), ...(staffId ? { staffId } : {}) },
    include: { staff: true },
    orderBy: { createdAt: 'desc' },
    take: 200,
  })
  return NextResponse.json({ records })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('overtime.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.staffId || !data.date || !data.hours) return NextResponse.json({ error: 'staffId, date, hours required' }, { status: 400 })
  const staff = await db.staff.findUnique({ where: { id: data.staffId } })
  if (!staff) return NextResponse.json({ error: 'Staff not found' }, { status: 404 })
  if (!staff.overtimeAllowed) return NextResponse.json({ error: 'Overtime not allowed for this staff member' }, { status: 400 })

  const rate = Number(data.rate) || staff.overtimeRate || 0
  const hours = Number(data.hours)
  const amount = hours * rate

  const record = await db.overtime.create({
    data: {
      staffId: data.staffId,
      date: new Date(data.date),
      hours,
      rate,
      amount,
      status: 'Pending',
      notes: data.notes,
    },
    include: { staff: true },
  })
  return NextResponse.json({ record })
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('overtime.approve')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const { id, status } = await req.json()
  if (!['Approved', 'Rejected'].includes(status)) return NextResponse.json({ error: 'Invalid status' }, { status: 400 })
  const record = await db.overtime.update({
    where: { id },
    data: { status, approvedBy: session.id, approvedAt: new Date() },
  })
  await db.auditLog.create({ data: { userId: session.id, action: status.toUpperCase(), module: 'overtime', details: JSON.stringify({ id }) } })
  return NextResponse.json({ record })
}
