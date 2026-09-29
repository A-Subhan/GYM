import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'
import { makeProgressEntryId } from '@/lib/ids'

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

  const branch = await db.branch.findUnique({ where: { id: member.branchId } })
  if (!branch) return NextResponse.json({ error: 'Member branch not found' }, { status: 400 })

  // Business id: {branchCode}/Pg-000001 (branchId is NOT NULL in the final schema)
  const id = await makeProgressEntryId(branch.code)

  const record = await db.progressEntry.create({
    data: {
      id,
      memberId: data.memberId,
      branchId: member.branchId,
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
