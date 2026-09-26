import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const allowed = getSelectedBranchIds(session, url.searchParams.get('branches'))
  const records = await db.followUp.findMany({
    where: { ...(allowed ? { branchId: { in: allowed } } : {}) },
    include: { member: true },
    orderBy: { date: 'desc' },
    take: 100,
  })
  return NextResponse.json({ records })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('followups.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.type) return NextResponse.json({ error: 'Type required' }, { status: 400 })

  // branchId inferred from member if provided
  let branchId = data.branchId
  if (!branchId && data.memberId) {
    const member = await db.member.findUnique({ where: { id: data.memberId } })
    branchId = member?.branchId
  }

  // Generate follow-up ID: BranchID/FW-000001
  let followUpId: string
  if (branchId) {
    const count = await db.followUp.count({ where: { branchId, followUpId: { startsWith: `${branchId}/FW-` } } })
    followUpId = `${branchId}/FW-${String(count + 1).padStart(6, '0')}`
  } else {
    const count = await db.followUp.count()
    followUpId = `FW-${String(count + 1).padStart(6, '0')}`
  }

  const record = await db.followUp.create({
    data: {
      followUpId,
      memberId: data.memberId || null,
      prospectId: data.prospectId || null,
      branchId: branchId || null,
      date: data.date ? new Date(data.date) : new Date(),
      type: data.type,
      userId: session.id,
      notes: data.notes,
      outcome: data.outcome,
      nextFollowUpDate: data.nextFollowUpDate ? new Date(data.nextFollowUpDate) : null,
    },
  })
  return NextResponse.json({ record })
}
