import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const classId = url.searchParams.get('classId')
  const records = await db.classEnrollment.findMany({
    where: { ...(classId ? { classId } : {}) },
    include: { member: true, gymClass: true },
    orderBy: { createdAt: 'desc' }
  })
  return NextResponse.json({ records })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const data = await req.json()
  if (!data.classId || !data.memberId) return NextResponse.json({ error: 'classId and memberId required' }, { status: 400 })
  const record = await db.classEnrollment.create({
    data: { classId: data.classId, memberId: data.memberId, notes: data.notes },
    include: { member: true, gymClass: true }
  })
  return NextResponse.json({ record })
}
