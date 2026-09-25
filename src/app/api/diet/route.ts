import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET() {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const plans = await db.dietPlan.findMany({ include: { meals: true }, orderBy: { name: 'asc' } })
  return NextResponse.json({ plans })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('diet.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.name) return NextResponse.json({ error: 'Name required' }, { status: 400 })
  // Generate diet plan ID: DP-000001
  const count = await db.dietPlan.count()
  const dietPlanId = `DP-${String(count + 1).padStart(6, '0')}`
  const plan = await db.dietPlan.create({
    data: {
      dietPlanId,
      name: data.name,
      description: data.description,
      branchId: data.branchId || session.branchId,
      isActive: true,
      meals: { create: (data.meals || []).map((m: any) => ({ timing: m.timing, foods: m.foods, quantity: m.quantity, calories: Number(m.calories) || 0, protein: Number(m.protein) || 0, carbs: Number(m.carbs) || 0, fat: Number(m.fat) || 0, notes: m.notes })) },
    },
    include: { meals: true },
  })
  return NextResponse.json({ plan })
}
