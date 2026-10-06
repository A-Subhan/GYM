import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const staffId = url.searchParams.get('staffId')
  const records = await db.trainerSchedule.findMany({
    where: { ...(staffId ? { staffId } : {}) },
    include: { staff: true, branch: true },
    orderBy: { date: 'desc' }
  })
  return NextResponse.json({ records })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('staff.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.staffId) return NextResponse.json({ error: 'Trainer is required' }, { status: 400 })
  if (!data.date || !data.dayOfWeek) return NextResponse.json({ error: 'Date and day are required' }, { status: 400 })
  if (!data.startTime || !data.endTime) return NextResponse.json({ error: 'Start and end time are required' }, { status: 400 })
  if (String(data.endTime) <= String(data.startTime)) {
    return NextResponse.json({ error: 'End time must be after start time' }, { status: 400 })
  }
  const staff = await db.staff.findUnique({ where: { id: data.staffId } })
  if (!staff) return NextResponse.json({ error: 'Trainer not found' }, { status: 404 })
  const record = await db.trainerSchedule.create({
    data: {
      staffId: data.staffId,
      branchId: data.branchId || null,
      date: new Date(data.date),
      dayOfWeek: data.dayOfWeek,
      startTime: data.startTime,
      endTime: data.endTime,
      sessionType: data.sessionType || 'PersonalTraining',
      memberId: data.memberId || null,
      classId: data.classId || null,
      status: data.status || 'Scheduled',
      notes: data.notes,
    },
    include: { staff: true }
  })
  await db.auditLog.create({ data: { userId: session.id, action: 'CREATE', module: 'staff', details: JSON.stringify({ id: record.id, staffId: data.staffId, date: data.date }) } })
  return NextResponse.json({ record })
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('staff.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.id) return NextResponse.json({ error: 'Schedule id required' }, { status: 400 })
  const existing = await db.trainerSchedule.findUnique({ where: { id: data.id } })
  if (!existing) return NextResponse.json({ error: 'Schedule not found' }, { status: 404 })
  if (data.startTime && data.endTime && String(data.endTime) <= String(data.startTime)) {
    return NextResponse.json({ error: 'End time must be after start time' }, { status: 400 })
  }
  const record = await db.trainerSchedule.update({
    where: { id: data.id },
    data: {
      ...(data.staffId !== undefined ? { staffId: data.staffId } : {}),
      ...(data.branchId !== undefined ? { branchId: data.branchId || null } : {}),
      ...(data.date !== undefined ? { date: new Date(data.date) } : {}),
      ...(data.dayOfWeek !== undefined ? { dayOfWeek: data.dayOfWeek } : {}),
      ...(data.startTime !== undefined ? { startTime: data.startTime } : {}),
      ...(data.endTime !== undefined ? { endTime: data.endTime } : {}),
      ...(data.sessionType !== undefined ? { sessionType: data.sessionType } : {}),
      ...(data.memberId !== undefined ? { memberId: data.memberId || null } : {}),
      ...(data.status !== undefined ? { status: data.status } : {}),
      ...(data.notes !== undefined ? { notes: data.notes } : {}),
    },
    include: { staff: true },
  })
  return NextResponse.json({ record })
}

export async function DELETE(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('staff.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const url = new URL(req.url)
  const id = url.searchParams.get('id')
  if (!id) return NextResponse.json({ error: 'Schedule id required' }, { status: 400 })
  await db.trainerSchedule.delete({ where: { id } })
  await db.auditLog.create({ data: { userId: session.id, action: 'DELETE', module: 'staff', details: JSON.stringify({ id }) } })
  return NextResponse.json({ success: true })
}
