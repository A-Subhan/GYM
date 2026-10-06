import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'
import { makeBranchPeriodId } from '@/lib/ids'
import { validateAttendanceDate, validateCheckOutAfterCheckIn } from '@/lib/attendance'

// Local-day bounds: parse 'yyyy-mm-dd' into a LOCAL-midnight Date (mirrors POST,
// which stores local midnight — a plain new Date('yyyy-mm-dd') is UTC midnight and
// mismatches by the UTC offset, which hid manual check-ins from the grid).
function localDayStart(dateStr: string): Date {
  const [y, m, d] = dateStr.split('-').map(Number)
  return new Date(y, (m || 1) - 1, d || 1, 0, 0, 0, 0)
}
function localDayEnd(dateStr: string): Date {
  const [y, m, d] = dateStr.split('-').map(Number)
  return new Date(y, (m || 1) - 1, d || 1, 23, 59, 59, 999)
}

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
      ...(date ? { date: { gte: localDayStart(date), lte: localDayEnd(date) } } : {}),
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

  const date = data.date ? localDayStart(String(data.date).slice(0, 10)) : new Date()
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

  // Business id: {branchCode}/{MMMyy}/{00001} (the attendance id IS the business id)
  const branch = await db.branch.findUnique({ where: { id: member.branchId } })
  if (!branch) return NextResponse.json({ error: 'Member branch not found' }, { status: 400 })
  const attendanceId = await makeBranchPeriodId('ATTENDANCE', branch.code, date)

  const record = await db.attendance.create({
    data: {
      id: attendanceId,
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
