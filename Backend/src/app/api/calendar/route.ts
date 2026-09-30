import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { makeCalendarDayId } from '@/lib/ids'

// HR Calendar — marks days as Off / PaidHoliday / GymClosed etc.
// PAYROLL CONTRACT: any day marked here (and Sundays) is PAID — it must
// never reduce anyone's salary (see /api/payroll holiday handling).

const DAY_TYPES = ['Working', 'Sunday', 'PublicHoliday', 'GymClosed', 'PaidHoliday', 'Off']

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const year = parseInt(url.searchParams.get('year') || String(new Date().getFullYear()))
  const records = await db.calendarDay.findMany({
    where: { date: { gte: new Date(year, 0, 1), lte: new Date(year, 11, 31, 23, 59, 59) } },
    orderBy: { date: 'asc' },
  })
  return NextResponse.json({ records })
}

/**
 * POST /api/calendar — three modes:
 *   { date, dayType, notes? }              → mark a single day (upsert)
 *   { year, markSundays: true }            → mark every Sunday of the year as off
 *   { year }                               → generate the whole year (Sundays off, rest Working)
 */
export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('calendar.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()

  // --- whole year generation ------------------------------------------------
  if (data.year && (data.markSundays || data.generate === true)) {
    const y = Number(data.year)
    const sundaysOnly = data.markSundays === true && data.generate !== true
    let count = 0
    for (let m = 0; m < 12; m++) {
      for (let d = 1; d <= 31; d++) {
        const date = new Date(y, m, d)
        if (date.getMonth() !== m || date.getDate() !== d) continue
        const isSunday = date.getDay() === 0
        if (sundaysOnly && !isSunday) continue
        const dayType = isSunday ? 'Sunday' : 'Working'
        const existing = await db.calendarDay.findUnique({ where: { date } })
        if (!existing) {
          await db.calendarDay.create({ data: { id: await makeCalendarDayId(), date, dayType } })
          count++
        } else if (isSunday && !sundaysOnly && existing.dayType === 'Working') {
          await db.calendarDay.update({ where: { id: existing.id }, data: { dayType } })
          count++
        }
      }
    }
    await db.auditLog.create({ data: { userId: session.id, action: 'UPDATE', module: 'calendar', details: JSON.stringify({ year: y, markSundays: !!data.markSundays, touched: count }) } })
    return NextResponse.json({ success: true, year: y, touched: count })
  }

  // --- single day mark -------------------------------------------------------
  if (!data.date || !data.dayType) return NextResponse.json({ error: 'Date and dayType required' }, { status: 400 })
  if (!DAY_TYPES.includes(data.dayType)) return NextResponse.json({ error: `dayType must be one of ${DAY_TYPES.join(', ')}` }, { status: 400 })
  const date = new Date(data.date)
  if (isNaN(date.getTime())) return NextResponse.json({ error: 'Invalid date' }, { status: 400 })
  date.setHours(0, 0, 0, 0)
  const existing = await db.calendarDay.findUnique({ where: { date } })
  let record
  if (existing) {
    record = await db.calendarDay.update({
      where: { id: existing.id },
      data: { dayType: data.dayType, notes: data.notes, branchId: data.branchId || existing.branchId || null },
    })
  } else {
    record = await db.calendarDay.create({
      data: { id: await makeCalendarDayId(), date, dayType: data.dayType, notes: data.notes, branchId: data.branchId || null },
    })
  }
  await db.auditLog.create({ data: { userId: session.id, action: 'UPDATE', module: 'calendar', details: JSON.stringify({ date: data.date, dayType: data.dayType }) } })
  return NextResponse.json({ record })
}

export async function PUT(req: NextRequest) {
  // Kept for compatibility with the older "Generate Year" button
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('calendar.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const { year } = await req.json()
  const y = Number(year) || new Date().getFullYear()
  for (let m = 0; m < 12; m++) {
    for (let d = 1; d <= 31; d++) {
      const date = new Date(y, m, d)
      if (date.getMonth() !== m || date.getDate() !== d) continue
      const dow = date.getDay() // 0 = Sunday
      const dayType = dow === 0 ? 'Sunday' : 'Working'
      const existing = await db.calendarDay.findUnique({ where: { date } })
      if (!existing) await db.calendarDay.create({ data: { id: await makeCalendarDayId(), date, dayType } })
    }
  }
  return NextResponse.json({ success: true, year: y })
}

// DELETE ?date=YYYY-MM-DD — reset a marked day back to a plain working day
export async function DELETE(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('calendar.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const url = new URL(req.url)
  const dateStr = url.searchParams.get('date')
  if (!dateStr) return NextResponse.json({ error: 'date required' }, { status: 400 })
  const date = new Date(dateStr)
  if (isNaN(date.getTime())) return NextResponse.json({ error: 'Invalid date' }, { status: 400 })
  date.setHours(0, 0, 0, 0)
  const existing = await db.calendarDay.findUnique({ where: { date } })
  if (!existing) return NextResponse.json({ success: true, message: 'Day was not marked — nothing to clear' })
  await db.calendarDay.delete({ where: { id: existing.id } })
  await db.auditLog.create({ data: { userId: session.id, action: 'DELETE', module: 'calendar', details: JSON.stringify({ date: dateStr }) } })
  return NextResponse.json({ success: true, message: 'Day cleared' })
}
