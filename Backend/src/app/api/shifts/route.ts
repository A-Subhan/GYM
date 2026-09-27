import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET() {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const shifts = await db.shift.findMany({ include: { branch: true }, orderBy: { name: 'asc' } })
  return NextResponse.json({ shifts })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('shifts.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.name || !data.timeIn || !data.timeOut) return NextResponse.json({ error: 'Name, timeIn, timeOut required' }, { status: 400 })
  const shift = await db.shift.create({
    data: {
      name: data.name,
      timeIn: data.timeIn,
      timeOut: data.timeOut,
      workingDays: data.workingDays || 'Mon,Tue,Wed,Thu,Fri',
      branchId: data.branchId || session.branchId,
      isActive: data.isActive !== false,
    },
  })
  return NextResponse.json({ shift })
}
