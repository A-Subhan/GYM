import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'
import { makeProspectId } from '@/lib/ids'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const status = url.searchParams.get('status')
  const source = url.searchParams.get('source')
  const search = url.searchParams.get('q')
  const allowed = getSelectedBranchIds(session, url.searchParams.get('branches'))

  const prospects = await db.prospect.findMany({
    where: {
      ...(status ? { status } : {}),
      ...(source ? { source } : {}),
      ...(allowed ? { OR: [{ branchId: { in: allowed } }, { branchId: null }] } : {}),
      ...(search ? {
        OR: [
          { id: { contains: search } },
          { name: { contains: search } },
          { phone: { contains: search } },
        ]
      } : {}),
    },
    include: { branch: true },
    orderBy: { createdAt: 'desc' },
    take: 200,
  })
  return NextResponse.json({ prospects })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('prospects.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  if (!data.name) return NextResponse.json({ error: 'Name required' }, { status: 400 })

  // Business id: {branchCode}/p-00001 (the prospect id IS the business id —
  // there is no separate prospectId column). A branch is required to build it.
  const branchId = (data.branchId as string) || session.branchId
  if (!branchId) return NextResponse.json({ error: 'Branch is required' }, { status: 400 })
  const branch = await db.branch.findUnique({ where: { id: branchId } })
  if (!branch) return NextResponse.json({ error: 'Invalid branch' }, { status: 400 })
  const prospectId = await makeProspectId(branch.code)

  const prospect = await db.prospect.create({
    data: {
      id: prospectId,
      name: data.name,
      phone: data.phone,
      whatsapp: data.whatsapp,
      gender: data.gender,
      age: data.age ? Number(data.age) : null,
      dob: data.dob ? new Date(data.dob) : null,
      interestedMembership: data.interestedMembership,
      branchId: branchId || null,
      source: data.source || 'WalkIn',
      status: data.status || 'New',
      inquiryDate: data.inquiryDate ? new Date(data.inquiryDate) : new Date(),
      followUpDate: data.followUpDate ? new Date(data.followUpDate) : null,
      assignedTo: data.assignedTo || session.id,
      notes: data.notes,
    },
  })
  await db.auditLog.create({
    data: { userId: session.id, action: 'CREATE', module: 'prospects', details: JSON.stringify({ id: prospect.id, prospectId }) },
  })
  return NextResponse.json({ prospect })
}
