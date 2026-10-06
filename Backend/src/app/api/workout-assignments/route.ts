import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

// Workout Assignment — assign workout plans to members (fully functional CRUD).
export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const memberId = url.searchParams.get('memberId')
  const assignments = await db.workoutAssignment.findMany({
    where: {
      ...(memberId ? { memberId } : {}),
      member: { isDeleted: false },
    },
    include: { member: true, plan: true },
    orderBy: { createdAt: 'desc' },
    take: 200,
  })
  return NextResponse.json({ assignments })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('workouts.assign')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  if (!data.memberId) return NextResponse.json({ error: 'Member is required' }, { status: 400 })
  if (!data.planId) return NextResponse.json({ error: 'Workout plan is required' }, { status: 400 })

  const member = await db.member.findFirst({ where: { id: data.memberId, isDeleted: false } })
  if (!member) return NextResponse.json({ error: 'Member not found' }, { status: 404 })
  const plan = await db.workoutPlan.findUnique({ where: { id: data.planId } })
  if (!plan) return NextResponse.json({ error: 'Workout plan not found' }, { status: 400 })
  if (data.trainerId) {
    const trainer = await db.staff.findUnique({ where: { id: data.trainerId } })
    if (!trainer) return NextResponse.json({ error: 'Trainer not found' }, { status: 400 })
  }

  const assignment = await db.workoutAssignment.create({
    data: {
      memberId: data.memberId,
      planId: data.planId,
      trainerId: data.trainerId || member.assignedTrainerId || null,
      startDate: data.startDate ? new Date(data.startDate) : new Date(),
      endDate: data.endDate ? new Date(data.endDate) : null,
      notes: data.notes || null,
    },
    include: { member: true, plan: true },
  })
  await db.auditLog.create({
    data: { userId: session.id, action: 'CREATE', module: 'workouts', details: JSON.stringify({ id: assignment.id, memberId: data.memberId, planId: data.planId }) },
  })
  return NextResponse.json({ assignment })
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('workouts.assign')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  if (!data.id) return NextResponse.json({ error: 'Assignment id required' }, { status: 400 })
  const existing = await db.workoutAssignment.findUnique({ where: { id: data.id } })
  if (!existing) return NextResponse.json({ error: 'Assignment not found' }, { status: 404 })

  if (data.planId) {
    const plan = await db.workoutPlan.findUnique({ where: { id: data.planId } })
    if (!plan) return NextResponse.json({ error: 'Workout plan not found' }, { status: 400 })
  }
  if (data.trainerId) {
    const trainer = await db.staff.findUnique({ where: { id: data.trainerId } })
    if (!trainer) return NextResponse.json({ error: 'Trainer not found' }, { status: 400 })
  }

  const assignment = await db.workoutAssignment.update({
    where: { id: data.id },
    data: {
      ...(data.planId !== undefined ? { planId: data.planId || null } : {}),
      ...(data.trainerId !== undefined ? { trainerId: data.trainerId || null } : {}),
      ...(data.startDate !== undefined ? { startDate: data.startDate ? new Date(data.startDate) : new Date() } : {}),
      ...(data.endDate !== undefined ? { endDate: data.endDate ? new Date(data.endDate) : null } : {}),
      ...(data.notes !== undefined ? { notes: data.notes || null } : {}),
    },
    include: { member: true, plan: true },
  })
  await db.auditLog.create({
    data: { userId: session.id, action: 'UPDATE', module: 'workouts', details: JSON.stringify({ id: data.id }) },
  })
  return NextResponse.json({ assignment })
}

export async function DELETE(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('workouts.assign')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const url = new URL(req.url)
  const id = url.searchParams.get('id')
  if (!id) return NextResponse.json({ error: 'Assignment id required' }, { status: 400 })
  await db.workoutAssignment.delete({ where: { id } })
  await db.auditLog.create({
    data: { userId: session.id, action: 'DELETE', module: 'workouts', details: JSON.stringify({ id }) },
  })
  return NextResponse.json({ success: true })
}
