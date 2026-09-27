import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET() {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const records = await db.gymClass.findMany({
    include: { branch: true, enrollments: { include: { member: true } } },
    orderBy: { name: 'asc' }
  })
  return NextResponse.json({ records })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const data = await req.json()
  if (!data.name || !data.branchId) return NextResponse.json({ error: 'Name and branch required' }, { status: 400 })
  const record = await db.gymClass.create({
    data: {
      name: data.name,
      trainerId: data.trainerId || null,
      branchId: data.branchId,
      capacity: Number(data.capacity) || 20,
      dayOfWeek: data.dayOfWeek || 'Monday',
      startTime: data.startTime || '09:00',
      endTime: data.endTime || '10:00',
      status: data.status || 'Active',
      notes: data.notes,
    },
    include: { branch: true }
  })
  return NextResponse.json({ record })
}
