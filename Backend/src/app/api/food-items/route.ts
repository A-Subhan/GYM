import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET() {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const records = await db.foodItem.findMany({ orderBy: { name: 'asc' } })
  return NextResponse.json({ records })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const data = await req.json()
  if (!data.name) return NextResponse.json({ error: 'Name required' }, { status: 400 })
  const count = await db.foodItem.count()
  const code = `FOOD-${String(count + 1).padStart(4, '0')}`
  const record = await db.foodItem.create({ data: { ...data, code } })
  return NextResponse.json({ record })
}
