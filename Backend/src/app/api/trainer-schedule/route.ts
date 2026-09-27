import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const staffId = url.searchParams.get('staffId')
  const records = await db.trainerSchedule.findMany({
    where: { ...(staffId ? { staffId } : {}) },
    include: { staff: true, branch: true },
    orderBy: { date: 'desc' }
  })
  return NextResponse.json({ records })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const data = await req.json()
  const record = await db.trainerSchedule.create({
    data: {
      staffId: data.staffId,
      branchId: data.branchId || null,
      date: new Date(data.date),
      dayOfWeek: data.dayOfWeek,
      startTime: data.startTime,
      endTime: data.endTime,
      sessionType: data.sessionType || 'PersonalTraining',
      memberId: data.memberId || null,
      classId: data.classId || null,
      status: data.status || 'Scheduled',
      notes: data.notes,
    },
    include: { staff: true }
  })
  return NextResponse.json({ record })
}
