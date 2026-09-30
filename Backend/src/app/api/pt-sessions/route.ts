import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const memberId = url.searchParams.get('memberId')
  const records = await db.personalTrainingSession.findMany({
    where: { ...(memberId ? { memberId } : {}), member: { isDeleted: false } },
    include: { member: true },
    orderBy: { createdAt: 'desc' },
    take: 200,
  })
  return NextResponse.json({ records })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const data = await req.json()
  if (!data.memberId || !data.trainerId) {
    return NextResponse.json({ error: 'Member and trainer are required' }, { status: 400 })
  }
  const member = await db.member.findFirst({ where: { id: data.memberId, isDeleted: false } })
  if (!member) return NextResponse.json({ error: 'Member not found' }, { status: 404 })
  const purchased = Math.max(0, Number(data.sessionsPurchased) || 0)
  const used = Math.max(0, Number(data.sessionsUsed) || 0)
  const record = await db.personalTrainingSession.create({
    data: {
      memberId: data.memberId,
      trainerId: data.trainerId,
      branchId: data.branchId || member.branchId,
      sessionsPurchased: purchased,
      sessionsUsed: used,
      sessionsRemaining: data.sessionsRemaining !== undefined ? Math.max(0, Number(data.sessionsRemaining) || 0) : purchased - used,
      sessionDate: data.sessionDate ? new Date(data.sessionDate) : null,
      sessionStatus: data.sessionStatus || 'Scheduled',
      startDate: data.startDate ? new Date(data.startDate) : null,
      endDate: data.endDate ? new Date(data.endDate) : null,
      notes: data.notes || null,
    },
    include: { member: true },
  })
  await db.auditLog.create({ data: { userId: session.id, action: 'CREATE', module: 'progress', details: JSON.stringify({ id: record.id, memberId: data.memberId, trainerId: data.trainerId }) } })
  return NextResponse.json({ record })
}

// PATCH — update a PT package; action: 'use-session' consumes one session,
// action: 'complete-session' / 'cancel-session' updates the session status.
export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('progress.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.id) return NextResponse.json({ error: 'PT session id required' }, { status: 400 })
  const existing = await db.personalTrainingSession.findUnique({ where: { id: data.id } })
  if (!existing) return NextResponse.json({ error: 'PT session not found' }, { status: 404 })

  if (data.action === 'use-session') {
    if (existing.sessionsRemaining <= 0) {
      return NextResponse.json({ error: 'No sessions remaining in this package' }, { status: 400 })
    }
    const record = await db.personalTrainingSession.update({
      where: { id: data.id },
      data: {
        sessionsUsed: existing.sessionsUsed + 1,
        sessionsRemaining: existing.sessionsRemaining - 1,
        sessionDate: data.sessionDate ? new Date(data.sessionDate) : new Date(),
        sessionStatus: 'Completed',
      },
      include: { member: true },
    })
    return NextResponse.json({ record })
  }

  const record = await db.personalTrainingSession.update({
    where: { id: data.id },
    data: {
      ...(data.trainerId !== undefined ? { trainerId: data.trainerId } : {}),
      ...(data.sessionsPurchased !== undefined ? { sessionsPurchased: Math.max(0, Number(data.sessionsPurchased) || 0) } : {}),
      ...(data.sessionsUsed !== undefined ? { sessionsUsed: Math.max(0, Number(data.sessionsUsed) || 0) } : {}),
      ...(data.sessionsRemaining !== undefined ? { sessionsRemaining: Math.max(0, Number(data.sessionsRemaining) || 0) } : {}),
      ...(data.sessionDate !== undefined ? { sessionDate: data.sessionDate ? new Date(data.sessionDate) : null } : {}),
      ...(data.sessionStatus !== undefined ? { sessionStatus: data.sessionStatus } : {}),
      ...(data.startDate !== undefined ? { startDate: data.startDate ? new Date(data.startDate) : null } : {}),
      ...(data.endDate !== undefined ? { endDate: data.endDate ? new Date(data.endDate) : null } : {}),
      ...(data.notes !== undefined ? { notes: data.notes || null } : {}),
      ...(data.status !== undefined ? { status: data.status } : {}),
    },
    include: { member: true },
  })
  return NextResponse.json({ record })
}

export async function DELETE(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('progress.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const url = new URL(req.url)
  const id = url.searchParams.get('id')
  if (!id) return NextResponse.json({ error: 'PT session id required' }, { status: 400 })
  await db.personalTrainingSession.delete({ where: { id } })
  await db.auditLog.create({ data: { userId: session.id, action: 'DELETE', module: 'progress', details: JSON.stringify({ id }) } })
  return NextResponse.json({ success: true })
}
