import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { makeDietPlanId } from '@/lib/ids'

const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
const MEALS = ['Breakfast', 'Brunch', 'Lunch', 'Snack', 'Dinner', 'Late Night', 'Pre Workout', 'Post Workout']
const MAX_FOODS_LEN = 60

export async function GET() {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const plans = await db.dietPlan.findMany({
    include: { meals: true },
    orderBy: { name: 'asc' },
  })
  return NextResponse.json({ plans, days: DAYS, meals: MEALS, maxFoodsLen: MAX_FOODS_LEN })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('diet.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.name) return NextResponse.json({ error: 'Name required' }, { status: 400 })

  // Validate meals structure: array of { dayOfWeek, timing, foods }
  // foods must be ≤ 60 chars
  const meals = data.meals || []
  for (const m of meals) {
    if (m.foods && String(m.foods).length > MAX_FOODS_LEN) {
      return NextResponse.json({ error: `Diet cell for ${m.dayOfWeek} / ${m.timing} exceeds ${MAX_FOODS_LEN} characters (got ${String(m.foods).length})` }, { status: 400 })
    }
    if (m.dayOfWeek && !DAYS.includes(m.dayOfWeek)) {
      return NextResponse.json({ error: `Invalid day of week: ${m.dayOfWeek}` }, { status: 400 })
    }
    if (m.timing && !MEALS.includes(m.timing)) {
      return NextResponse.json({ error: `Invalid meal timing: ${m.timing}` }, { status: 400 })
    }
  }

  // Business id: DP-000001 (global sequence; the plan id IS the business id)
  const id = await makeDietPlanId()
  const plan = await db.dietPlan.create({
    data: {
      id,
      name: String(data.name),
      description: data.description ? String(data.description) : null,
      branchId: data.branchId || session.branchId,
      isActive: true,
      meals: {
        create: meals
          .filter((m: any) => m.foods && String(m.foods).trim()) // only save non-empty cells
          .map((m: any) => ({
            dayOfWeek: String(m.dayOfWeek),
            timing: String(m.timing),
            foods: String(m.foods).slice(0, MAX_FOODS_LEN),
          })),
      },
    },
    include: { meals: true },
  })
  return NextResponse.json({ plan })
}
