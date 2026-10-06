import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const memberId = url.searchParams.get('memberId')
  const records = await db.fitnessGoal.findMany({
    where: { ...(memberId ? { memberId } : {}) },
    include: { member: true },
    orderBy: { createdAt: 'desc' },
    take: 200,
  })
  return NextResponse.json({ records })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('progress.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.memberId) return NextResponse.json({ error: 'Member required' }, { status: 400 })
  if (!data.goalType) return NextResponse.json({ error: 'Goal type is required' }, { status: 400 })
  const member = await db.member.findFirst({ where: { id: data.memberId, isDeleted: false } })
  if (!member) return NextResponse.json({ error: 'Member not found' }, { status: 404 })
  const record = await db.fitnessGoal.create({
    data: {
      memberId: data.memberId,
      goalType: data.goalType,
      targetValue: data.targetValue !== undefined && data.targetValue !== null && data.targetValue !== '' ? Number(data.targetValue) : null,
      unit: data.unit || null,
      startDate: data.startDate ? new Date(data.startDate) : new Date(),
      targetDate: data.targetDate ? new Date(data.targetDate) : null,
      status: data.status || 'Active',
      notes: data.notes || null,
    },
    include: { member: true },
  })
  await db.auditLog.create({ data: { userId: session.id, action: 'CREATE', module: 'progress', details: JSON.stringify({ id: record.id, memberId: data.memberId, goalType: data.goalType }) } })
  return NextResponse.json({ record })
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('progress.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.id) return NextResponse.json({ error: 'Goal id required' }, { status: 400 })
  const existing = await db.fitnessGoal.findUnique({ where: { id: data.id } })
  if (!existing) return NextResponse.json({ error: 'Goal not found' }, { status: 404 })
  const record = await db.fitnessGoal.update({
    where: { id: data.id },
    data: {
      ...(data.goalType !== undefined ? { goalType: data.goalType } : {}),
      ...(data.targetValue !== undefined ? { targetValue: data.targetValue === null || data.targetValue === '' ? null : Number(data.targetValue) } : {}),
      ...(data.unit !== undefined ? { unit: data.unit || null } : {}),
      ...(data.startDate !== undefined ? { startDate: data.startDate ? new Date(data.startDate) : new Date() } : {}),
      ...(data.targetDate !== undefined ? { targetDate: data.targetDate ? new Date(data.targetDate) : null } : {}),
      ...(data.status !== undefined ? { status: data.status } : {}),
      ...(data.notes !== undefined ? { notes: data.notes || null } : {}),
    },
    include: { member: true },
  })
  await db.auditLog.create({ data: { userId: session.id, action: 'UPDATE', module: 'progress', details: JSON.stringify({ id: data.id }) } })
  return NextResponse.json({ record })
}

export async function DELETE(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('progress.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const url = new URL(req.url)
  const id = url.searchParams.get('id')
  if (!id) return NextResponse.json({ error: 'Goal id required' }, { status: 400 })
  await db.fitnessGoal.delete({ where: { id } })
  await db.auditLog.create({ data: { userId: session.id, action: 'DELETE', module: 'progress', details: JSON.stringify({ id }) } })
  return NextResponse.json({ success: true })
}
