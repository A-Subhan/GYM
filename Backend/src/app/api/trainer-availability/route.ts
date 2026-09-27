import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const staffId = url.searchParams.get('staffId')
  const records = await db.trainerAvailability.findMany({
    where: { ...(staffId ? { staffId } : {}) },
    include: { staff: true, branch: true },
    orderBy: { dayOfWeek: 'asc' }
  })
  return NextResponse.json({ records })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const data = await req.json()
  const record = await db.trainerAvailability.create({
    data: {
      staffId: data.staffId,
      dayOfWeek: data.dayOfWeek,
      startTime: data.startTime,
      endTime: data.endTime,
      branchId: data.branchId || null,
      status: data.status || 'Available',
    },
    include: { staff: true }
  })
  return NextResponse.json({ record })
}
