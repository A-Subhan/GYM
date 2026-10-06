import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { makeWorkoutPlanId } from '@/lib/ids'

export async function GET() {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const plans = await db.workoutPlan.findMany({ include: { days: { include: { exercises: { include: { exercise: true } } } } }, orderBy: { name: 'asc' } })
  return NextResponse.json({ plans })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('workouts.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.name) return NextResponse.json({ error: 'Name required' }, { status: 400 })
  // Validate: each day must have at least 1 exercise
  const days = data.days || []
  for (const d of days) {
    if (!d.exercises || d.exercises.length === 0) {
      return NextResponse.json({ error: `Day "${d.dayName}" must have at least one exercise` }, { status: 400 })
    }
  }
  // Business id: WO-000001 (global sequence; the plan id IS the business id)
  const id = await makeWorkoutPlanId()
  const plan = await db.workoutPlan.create({
    data: {
      id,
      name: String(data.name),
      description: data.description ? String(data.description) : null,
      isGeneral: data.isGeneral !== false,
      branchId: data.branchId || session.branchId,
      isActive: true,
      days: { create: (data.days || []).map((d: any) => ({ dayName: String(d.dayName), notes: d.notes ? String(d.notes) : null, exercises: { create: (d.exercises || []).map((e: any) => ({ exerciseId: e.exerciseId, sets: e.sets ? Number(e.sets) : null, reps: e.reps ? String(e.reps) : null, duration: e.duration ? String(e.duration) : null, rest: e.rest ? String(e.rest) : null, notes: e.notes ? String(e.notes) : null })) } })) },
    },
    include: { days: { include: { exercises: true } } },
  })
  return NextResponse.json({ plan })
}
