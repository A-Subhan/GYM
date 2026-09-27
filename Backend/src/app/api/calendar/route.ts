import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

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

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('calendar.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.date || !data.dayType) return NextResponse.json({ error: 'Date and dayType required' }, { status: 400 })
  const date = new Date(data.date)
  date.setHours(0, 0, 0, 0)
  const record = await db.calendarDay.upsert({
    where: { date },
    update: { dayType: data.dayType, notes: data.notes, branchId: data.branchId || null },
    create: { date, dayType: data.dayType, notes: data.notes, branchId: data.branchId || null },
  })
  return NextResponse.json({ record })
}

export async function PUT(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('calendar.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const { year } = await req.json()
  const y = Number(year) || new Date().getFullYear()
  // Generate full year of working days / Sundays
  for (let m = 0; m < 12; m++) {
    for (let d = 1; d <= 31; d++) {
      const date = new Date(y, m, d)
      if (date.getMonth() !== m || date.getDate() !== d) continue
      const dow = date.getDay() // 0 = Sunday
      const dayType = dow === 0 ? 'Sunday' : 'Working'
      const existing = await db.calendarDay.findUnique({ where: { date } })
      if (!existing) await db.calendarDay.create({ data: { date, dayType } })
    }
  }
  return NextResponse.json({ success: true, year: y })
}
