import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { validateAttendanceDate, validateCheckOutAfterCheckIn } from '@/lib/attendance'

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const { id } = await params
  const record = await db.attendance.findUnique({ where: { id }, include: { member: true, branch: true } })
  if (!record) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  return NextResponse.json({ record })
}

/**
 * PATCH /api/attendance/[id]
 *  - { action: 'check-out' }               -> sets checkOut = now
 *  - { checkIn?, checkOut?, notes? }        -> same-day edit of times/notes
 * Validation: dates within the current month, never in the future, checkOut > checkIn.
 */
export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('attendance.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { id } = await params
  const data = await req.json()

  const record = await db.attendance.findUnique({ where: { id } })
  if (!record) return NextResponse.json({ error: 'Attendance record not found' }, { status: 404 })

  if (data.action === 'check-out') {
    const checkOut = new Date()
    const err = validateCheckOutAfterCheckIn(record.checkIn, checkOut)
    if (err) return NextResponse.json({ error: err }, { status: 400 })
    const updated = await db.attendance.update({ where: { id }, data: { checkOut } })
    return NextResponse.json({ record: updated })
  }

  const checkIn = data.checkIn !== undefined ? (data.checkIn ? new Date(data.checkIn) : null) : record.checkIn
  const checkOut = data.checkOut !== undefined ? (data.checkOut ? new Date(data.checkOut) : null) : record.checkOut

  if (checkIn) {
    const err = validateAttendanceDate(checkIn)
    if (err) return NextResponse.json({ error: `Check-in: ${err}` }, { status: 400 })
  }
  if (checkOut) {
    const err = validateAttendanceDate(checkOut)
    if (err) return NextResponse.json({ error: `Check-out: ${err}` }, { status: 400 })
  }
  const orderErr = validateCheckOutAfterCheckIn(checkIn, checkOut)
  if (orderErr) return NextResponse.json({ error: orderErr }, { status: 400 })

  const updated = await db.attendance.update({
    where: { id },
    data: {
      ...(data.checkIn !== undefined ? { checkIn } : {}),
      ...(data.checkOut !== undefined ? { checkOut } : {}),
      ...(data.notes !== undefined ? { notes: data.notes } : {}),
    },
  })
  return NextResponse.json({ record: updated })
}
