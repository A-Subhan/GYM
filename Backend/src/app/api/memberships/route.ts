import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET() {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const plans = await db.membershipPlan.findMany({ orderBy: { code: 'asc' } })
  return NextResponse.json({ plans })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('memberships.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.name || !data.durationDays) return NextResponse.json({ error: 'Name and duration required' }, { status: 400 })
  const count = await db.membershipPlan.count()
  const code = data.code || `MP-${String(count + 1).padStart(3, '0')}`
  const plan = await db.membershipPlan.create({
    data: {
      code,
      name: data.name,
      durationDays: Number(data.durationDays),
      amount: Number(data.amount) || 0,
      description: data.description,
      isActive: data.isActive !== false,
    },
  })
  return NextResponse.json({ plan })
}
