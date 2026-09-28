import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'
import { makeFollowUpId } from '@/lib/ids'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const allowed = getSelectedBranchIds(session, url.searchParams.get('branches'))
  const records = await db.followUp.findMany({
    where: { ...(allowed ? { branchId: { in: allowed } } : {}), member: { isDeleted: false } },
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

  // branchId inferred from member/prospect if provided, else the user's branch
  let branchId = data.branchId
  if (!branchId && data.memberId) {
    const member = await db.member.findUnique({ where: { id: data.memberId } })
    branchId = member?.branchId
  }
  if (!branchId && data.prospectId) {
    const prospect = await db.prospect.findUnique({ where: { id: data.prospectId } })
    branchId = prospect?.branchId
  }
  if (!branchId) branchId = session.branchId
  if (!branchId) return NextResponse.json({ error: 'Branch is required' }, { status: 400 })

  const branch = await db.branch.findUnique({ where: { id: branchId } })
  if (!branch) return NextResponse.json({ error: 'Invalid branch' }, { status: 400 })

  // Business id: {branchCode}/fw-000001 (the follow-up id IS the business id)
  const id = await makeFollowUpId(branch.code)

  const record = await db.followUp.create({
    data: {
      id,
      memberId: data.memberId || null,
      prospectId: data.prospectId || null,
      branchId,
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
