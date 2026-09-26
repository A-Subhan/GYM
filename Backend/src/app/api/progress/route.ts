import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const memberId = url.searchParams.get('memberId')
  const records = await db.progressEntry.findMany({
    where: { ...(memberId ? { memberId } : {}) },
    orderBy: { date: 'desc' },
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
  const member = await db.member.findUnique({ where: { id: data.memberId } })
  if (!member) return NextResponse.json({ error: 'Member not found' }, { status: 404 })
  // Generate progress ID: BranchID/PG-000001
  const count = await db.progressEntry.count({ where: { member: { branchId: member.branchId }, progressId: { startsWith: `${member.branchId}/PG-` } } })
  const progressId = `${member.branchId}/PG-${String(count + 1).padStart(6, '0')}`
  const record = await db.progressEntry.create({
    data: {
      progressId,
      memberId: data.memberId,
      date: data.date ? new Date(data.date) : new Date(),
      weight: data.weight ? Number(data.weight) : null,
      chest: data.chest ? Number(data.chest) : null,
      waist: data.waist ? Number(data.waist) : null,
      hips: data.hips ? Number(data.hips) : null,
      biceps: data.biceps ? Number(data.biceps) : null,
      thighs: data.thighs ? Number(data.thighs) : null,
      notes: data.notes,
      photo: data.photo,
    },
  })
  return NextResponse.json({ record })
}
