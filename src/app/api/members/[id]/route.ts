import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const { id } = await params
  const member = await db.member.findUnique({
    where: { id },
    include: {
      branch: true,
      membershipPlan: true,
      attendance: { orderBy: { date: 'desc' }, take: 30 },
      fees: { orderBy: { dueDate: 'desc' }, take: 30, include: { payments: true } },
      freezes: { orderBy: { createdAt: 'desc' } },
      followUps: { orderBy: { date: 'desc' }, take: 20 },
      workoutAssignments: { include: { plan: true } },
      dietAssignments: { include: { plan: true } },
      progress: { orderBy: { date: 'desc' }, take: 30 },
    },
  })
  if (!member) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  return NextResponse.json({ member })
}

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const { id } = await params
  const data = await req.json()
  const action = data.action

  if (action === 'status') {
    if (!session.permissions.includes('members.status')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    const member = await db.member.update({ where: { id }, data: { status: data.status } })
    await db.auditLog.create({ data: { userId: session.id, action: 'STATUS', module: 'members', details: JSON.stringify({ id, status: data.status }) } })
    return NextResponse.json({ member })
  }

  if (!session.permissions.includes('members.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const feeRelaxationDays = data.feeRelaxationDays !== undefined ? Math.max(0, Math.min(27, Number(data.feeRelaxationDays))) : undefined
  const member = await db.member.update({
    where: { id },
    data: {
      firstName: data.firstName,
      lastName: data.lastName,
      gender: data.gender,
      dob: data.dob ? new Date(data.dob) : null,
      phone: data.phone,
      whatsapp: data.whatsapp,
      email: data.email,
      address: data.address,
      emergencyContact: data.emergencyContact,
      emergencyContactNo: data.emergencyContactNo,
      cnic: data.cnic,
      billingStartDate: data.billingStartDate ? new Date(data.billingStartDate) : undefined,
      feeRelaxationDays,
      status: data.status,
      membershipPlanId: data.membershipPlanId,
      notes: data.notes,
      isActive: data.isActive,
      assignedTrainerId: data.assignedTrainerId,
    },
  })
  await db.auditLog.create({ data: { userId: session.id, action: 'UPDATE', module: 'members', details: JSON.stringify({ id }) } })
  return NextResponse.json({ member })
}

export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('members.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const { id } = await params
  await db.member.update({ where: { id }, data: { isDeleted: true, isActive: false } })
  await db.auditLog.create({ data: { userId: session.id, action: 'DELETE', module: 'members', details: JSON.stringify({ id }) } })
  return NextResponse.json({ success: true })
}
