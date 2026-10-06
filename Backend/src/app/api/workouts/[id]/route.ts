import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('workouts.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const { id } = await params
  const data = await req.json()

  // Validate: each day must have at least 1 exercise
  const days = data.days || []
  for (const d of days) {
    if (!d.exercises || d.exercises.length === 0) {
      return NextResponse.json({ error: `Day "${d.dayName}" must have at least one exercise` }, { status: 400 })
    }
  }

  // Update plan
  await db.workoutPlan.update({
    where: { id },
    data: { name: data.name, description: data.description },
  })

  // Delete existing days + exercises, recreate
  await db.workoutDay.deleteMany({ where: { planId: id } })
  for (const d of days) {
    const day = await db.workoutDay.create({
      data: {
        planId: id,
        dayName: d.dayName,
        notes: d.notes,
      },
    })
    await db.workoutDayExercise.createMany({
      data: d.exercises.map((e: any) => ({
        dayId: day.id,
        exerciseId: e.exerciseId,
        sets: e.sets ? Number(e.sets) : null,
        reps: e.reps,
        duration: e.duration,
        rest: e.rest,
        notes: e.notes,
      })),
    })
  }

  const plan = await db.workoutPlan.findUnique({
    where: { id },
    include: { days: { include: { exercises: { include: { exercise: true } } } } },
  })
  return NextResponse.json({ plan })
}

export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('workouts.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const { id } = await params
  await db.workoutPlan.delete({ where: { id } })
  return NextResponse.json({ success: true })
}
