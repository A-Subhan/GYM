import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

const DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
const MEALS = ['Breakfast', 'Brunch', 'Lunch', 'Snack', 'Dinner', 'Late Night', 'Pre Workout', 'Post Workout']
const MAX_FOODS_LEN = 60

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('diet.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const { id } = await params
  const data = await req.json()

  // Validate meals
  const meals = data.meals || []
  for (const m of meals) {
    if (m.foods && String(m.foods).length > MAX_FOODS_LEN) {
      return NextResponse.json({ error: `Diet cell for ${m.dayOfWeek} / ${m.timing} exceeds ${MAX_FOODS_LEN} characters` }, { status: 400 })
    }
  }

  // Update plan name/description
  await db.dietPlan.update({
    where: { id },
    data: {
      name: String(data.name),
      description: data.description ? String(data.description) : null,
    },
  })

  // Replace all meals (delete + recreate)
  await db.dietMeal.deleteMany({ where: { planId: id } })
  await db.dietMeal.createMany({
    data: meals
      .filter((m: any) => m.foods && String(m.foods).trim())
      .map((m: any) => ({
        planId: id,
        dayOfWeek: m.dayOfWeek,
        timing: m.timing,
        foods: String(m.foods).slice(0, MAX_FOODS_LEN),
      })),
  })

  const plan = await db.dietPlan.findUnique({ where: { id }, include: { meals: true } })
  return NextResponse.json({ plan })
}

export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('diet.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const { id } = await params
  await db.dietPlan.delete({ where: { id } })
  return NextResponse.json({ success: true })
}
