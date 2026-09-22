import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

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
  const plan = await db.workoutPlan.create({
    data: {
      name: data.name,
      description: data.description,
      isGeneral: data.isGeneral !== false,
      branchId: data.branchId || session.branchId,
      isActive: true,
      days: { create: (data.days || []).map((d: any) => ({ dayName: d.dayName, notes: d.notes, exercises: { create: (d.exercises || []).map((e: any) => ({ exerciseId: e.exerciseId, sets: e.sets, reps: e.reps, duration: e.duration, rest: e.rest, notes: e.notes })) } })) },
    },
    include: { days: { include: { exercises: true } } },
  })
  return NextResponse.json({ plan })
}
