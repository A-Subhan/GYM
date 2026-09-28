import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'
import { validateAttendanceDate, validateCheckOutAfterCheckIn } from '@/lib/attendance'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const allowed = getSelectedBranchIds(session, url.searchParams.get('branches'))
  const date = url.searchParams.get('date')
  const memberId = url.searchParams.get('memberId')

  const records = await db.attendance.findMany({
    where: {
      ...(allowed ? { branchId: { in: allowed } } : {}),
      ...(date ? { date: new Date(date) } : {}),
      ...(memberId ? { memberId } : {}),
      member: { isDeleted: false },
    },
    include: { member: true, branch: true },
    orderBy: { date: 'desc' },
    take: 200,
  })
  return NextResponse.json({ records })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('attendance.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  if (!data.memberId) return NextResponse.json({ error: 'Member required' }, { status: 400 })

  const member = await db.member.findFirst({ where: { id: data.memberId, isDeleted: false } })
  if (!member) return NextResponse.json({ error: 'Member not found' }, { status: 404 })

  const date = data.date ? new Date(data.date) : new Date()
  date.setHours(0, 0, 0, 0)

  const dateError = validateAttendanceDate(date)
  if (dateError) return NextResponse.json({ error: dateError }, { status: 400 })

  const checkIn = data.checkIn ? new Date(data.checkIn) : new Date()
  const checkInErr = validateAttendanceDate(checkIn)
  if (checkInErr) return NextResponse.json({ error: checkInErr }, { status: 400 })

  const checkOut = data.checkOut ? new Date(data.checkOut) : null
  if (checkOut) {
    const outErr = validateAttendanceDate(checkOut)
    if (outErr) return NextResponse.json({ error: `Check-out: ${outErr}` }, { status: 400 })
  }
  const orderErr = validateCheckOutAfterCheckIn(checkIn, checkOut)
  if (orderErr) return NextResponse.json({ error: orderErr }, { status: 400 })

  const existing = await db.attendance.findUnique({ where: { memberId_date: { memberId: data.memberId, date } } })
  if (existing) {
    return NextResponse.json({ error: 'Already checked in for this date', record: existing }, { status: 400 })
  }

  const record = await db.attendance.create({
    data: {
      memberId: data.memberId,
      branchId: member.branchId,
      date,
      checkIn,
      checkOut,
      notes: data.notes,
    },
  })
  return NextResponse.json({ record })
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('attendance.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { id, checkOut, notes } = await req.json()
  const record = await db.attendance.update({
    where: { id },
    data: { checkOut: checkOut ? new Date(checkOut) : new Date(), notes },
  })
  return NextResponse.json({ record })
}
