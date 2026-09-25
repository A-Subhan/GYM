import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'

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

  const member = await db.member.findUnique({ where: { id: data.memberId } })
  if (!member) return NextResponse.json({ error: 'Member not found' }, { status: 404 })

  const date = data.date ? new Date(data.date) : new Date()
  date.setHours(0, 0, 0, 0)

  const existing = await db.attendance.findUnique({ where: { memberId_date: { memberId: data.memberId, date } } })
  if (existing) {
    return NextResponse.json({ error: 'Already checked in today', record: existing }, { status: 400 })
  }

  // Generate attendance ID: BranchID/MonthYear/00001
  const monthYear = String(date.getMonth() + 1).padStart(2, '0') + String(date.getFullYear()).slice(-2)
  const count = await db.attendance.count({ where: { branchId: member.branchId, attendanceId: { startsWith: `${member.branchId}/${monthYear}/` } } })
  const attendanceId = `${member.branchId}/${monthYear}/${String(count + 1).padStart(5, '0')}`

  const record = await db.attendance.create({
    data: {
      attendanceId,
      memberId: data.memberId,
      branchId: member.branchId,
      date,
      checkIn: data.checkIn ? new Date(data.checkIn) : new Date(),
      checkOut: data.checkOut ? new Date(data.checkOut) : null,
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
