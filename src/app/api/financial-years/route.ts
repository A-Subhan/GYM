import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET() {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const years = await db.financialYear.findMany({ orderBy: { startDate: 'desc' }, include: { periods: true } })
  return NextResponse.json({ years })
}
