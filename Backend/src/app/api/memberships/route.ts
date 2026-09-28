import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { makeMembershipPlanId } from '@/lib/ids'

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
  if (!data.name || !String(data.name).trim()) return NextResponse.json({ error: 'Name is required' }, { status: 400 })
  const durationDays = Number(data.durationDays)
  if (!durationDays || durationDays < 1) return NextResponse.json({ error: 'Duration must be at least 1 day' }, { status: 400 })
  const amount = Number(data.amount)
  if (isNaN(amount) || amount < 0) return NextResponse.json({ error: 'Amount must be a non-negative number' }, { status: 400 })

  // Auto-generate the plan code (MP-0001, MP-0002, …) unless explicitly supplied.
  // Previously a count-based code was used, which collided with existing rows and
  // made plan creation fail with a unique-constraint error — that is the add bug.
  const code = (data.code && String(data.code).trim()) || await makeMembershipPlanId()

  try {
    const plan = await db.membershipPlan.create({
      data: {
        code,
        name: String(data.name).trim(),
        durationDays,
        amount,
        description: data.description,
        isActive: data.isActive !== false,
      },
    })
    return NextResponse.json({ plan })
  } catch (e: any) {
    if (e?.code === 'P2002') {
      return NextResponse.json({ error: `Plan code "${code}" already exists — please try again` }, { status: 400 })
    }
    throw e
  }
}
