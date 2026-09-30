import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { makeBranchPeriodId } from '@/lib/ids'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const branchId = url.searchParams.get('branchId')
  const plans = await db.membershipPlan.findMany({
    where: { ...(branchId && branchId !== 'all' ? { branchId } : {}) },
    include: { branch: { select: { id: true, name: true, code: true } } },
    orderBy: { name: 'asc' },
  })
  return NextResponse.json({ plans })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('memberships.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.name || !String(data.name).trim()) return NextResponse.json({ error: 'Name is required' }, { status: 400 })
  if (!data.branchId) return NextResponse.json({ error: 'Branch is required' }, { status: 400 })
  const durationDays = Number(data.durationDays)
  if (!durationDays || durationDays < 1) return NextResponse.json({ error: 'Duration must be at least 1 day' }, { status: 400 })
  const amount = Number(data.amount)
  if (isNaN(amount) || amount < 0) return NextResponse.json({ error: 'Amount must be a non-negative number' }, { status: 400 })

  // Plans are branch-scoped (branchId NOT NULL in the final schema) and the
  // plan id IS the business id: {branchCode}/{MMMyy}/{00001}.
  const branch = await db.branch.findUnique({ where: { id: data.branchId } })
  if (!branch) return NextResponse.json({ error: 'Invalid branch' }, { status: 400 })

  try {
    const id = await makeBranchPeriodId('PLAN', branch.code, new Date())
    const plan = await db.membershipPlan.create({
      data: {
        id,
        name: String(data.name).trim(),
        durationDays,
        amount,
        description: data.description,
        branchId: data.branchId,
        isActive: data.isActive !== false,
      },
    })
    return NextResponse.json({ plan })
  } catch (e: any) {
    if (e?.code === 'P2002') {
      return NextResponse.json({ error: 'A plan with this id already exists — please try again' }, { status: 400 })
    }
    throw e
  }
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('memberships.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.id) return NextResponse.json({ error: 'Plan id required' }, { status: 400 })
  const existing = await db.membershipPlan.findUnique({ where: { id: data.id } })
  if (!existing) return NextResponse.json({ error: 'Plan not found' }, { status: 404 })
  const durationDays = data.durationDays !== undefined ? Number(data.durationDays) : undefined
  if (durationDays !== undefined && (!durationDays || durationDays < 1)) {
    return NextResponse.json({ error: 'Duration must be at least 1 day' }, { status: 400 })
  }
  const amount = data.amount !== undefined ? Number(data.amount) : undefined
  if (amount !== undefined && (isNaN(amount) || amount < 0)) {
    return NextResponse.json({ error: 'Amount must be a non-negative number' }, { status: 400 })
  }
  const plan = await db.membershipPlan.update({
    where: { id: data.id },
    data: {
      ...(data.name !== undefined ? { name: String(data.name).trim() } : {}),
      ...(durationDays !== undefined ? { durationDays } : {}),
      ...(amount !== undefined ? { amount } : {}),
      ...(data.description !== undefined ? { description: data.description } : {}),
      ...(data.isActive !== undefined ? { isActive: !!data.isActive } : {}),
    },
  })
  await db.auditLog.create({
    data: { userId: session.id, action: 'UPDATE', module: 'memberships', details: JSON.stringify({ id: plan.id, name: plan.name }) },
  })
  return NextResponse.json({ plan })
}

export async function DELETE(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('memberships.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const url = new URL(req.url)
  const id = url.searchParams.get('id')
  if (!id) return NextResponse.json({ error: 'Plan id required' }, { status: 400 })
  const attached = await db.member.count({ where: { membershipPlanId: id, isDeleted: false } })
  if (attached > 0) {
    return NextResponse.json({ error: `Cannot delete — ${attached} member(s) are on this plan. Deactivate it instead.` }, { status: 400 })
  }
  await db.membershipPlan.delete({ where: { id } })
  await db.auditLog.create({
    data: { userId: session.id, action: 'DELETE', module: 'memberships', details: JSON.stringify({ id }) },
  })
  return NextResponse.json({ success: true })
}
