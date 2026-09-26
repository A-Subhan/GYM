import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const memberId = url.searchParams.get('memberId')
  const freezes = await db.membershipFreeze.findMany({
    where: { ...(memberId ? { memberId } : {}) },
    include: { member: true, branch: true },
    orderBy: { createdAt: 'desc' },
    take: 200,
  })
  return NextResponse.json({ freezes })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('freeze.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  if (!data.memberId || !data.freezeFrom || !data.freezeTo) return NextResponse.json({ error: 'memberId, freezeFrom, freezeTo required' }, { status: 400 })

  const member = await db.member.findUnique({ where: { id: data.memberId } })
  if (!member) return NextResponse.json({ error: 'Member not found' }, { status: 404 })

  const from = new Date(data.freezeFrom)
  const to = new Date(data.freezeTo)
  if (to < from) return NextResponse.json({ error: 'freezeTo must be after freezeFrom' }, { status: 400 })
  const days = Math.ceil((to.getTime() - from.getTime()) / (24 * 60 * 60 * 1000)) + 1

  // Check overlapping freezes
  const overlapping = await db.membershipFreeze.findFirst({
    where: { memberId: data.memberId, status: 'Active', freezeFrom: { lte: to }, freezeTo: { gte: from } },
  })
  if (overlapping) return NextResponse.json({ error: 'Overlapping freeze exists' }, { status: 400 })

  // Generate freeze ID: F-000001
  const count = await db.membershipFreeze.count()
  const freezeId = `F-${String(count + 1).padStart(6, '0')}`

  const freeze = await db.membershipFreeze.create({
    data: {
      freezeId,
      memberId: data.memberId,
      branchId: member.branchId,
      freezeFrom: from,
      freezeTo: to,
      days,
      reason: data.reason,
      approvedBy: session.id,
      status: 'Active',
    },
  })
  await db.auditLog.create({ data: { userId: session.id, action: 'CREATE', module: 'freeze', details: JSON.stringify({ id: freeze.id }) } })
  return NextResponse.json({ freeze })
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const { id, action } = await req.json()
  if (action === 'lift') {
    const freeze = await db.membershipFreeze.update({ where: { id }, data: { status: 'Lifted' } })
    await db.auditLog.create({ data: { userId: session.id, action: 'UPDATE', module: 'freeze', details: JSON.stringify({ id, action: 'lift' }) } })
    return NextResponse.json({ freeze })
  }
  return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
}
