import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const branchId = url.searchParams.get('branchId')
  const allowed = session.accessibleBranchIds === '*' ? null : session.accessibleBranchIds.split(',')
  const exercises = await db.exercise.findMany({
    where: {
      ...(allowed ? { OR: [{ branchId: { in: allowed } }, { branchId: null }] } : {}),
      ...(branchId && branchId !== 'all' ? { OR: [{ branchId }, { branchId: null }] } : {}),
    },
    orderBy: { code: 'asc' },
  })
  return NextResponse.json({ exercises })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('workouts.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.name) return NextResponse.json({ error: 'Name required' }, { status: 400 })
  const branchId = data.branchId || session.branchId
  const existing = await db.exercise.findMany({ where: { branchId: branchId || null } })
  const existingCodes = existing.map(e => parseInt(e.code, 10)).filter(n => !isNaN(n))
  const code = String((existingCodes.length ? Math.max(...existingCodes) : 0) + 1).padStart(3, '0')
  const exercise = await db.exercise.create({
    data: {
      code,
      name: data.name,
      category: data.category,
      muscleGroup: data.muscleGroup,
      instructions: data.instructions,
      sets: data.sets ? Number(data.sets) : null,
      reps: data.reps,
      duration: data.duration,
      rest: data.rest,
      equipment: data.equipment,
      image: data.image,
      branchId: branchId || null,
      status: 'Active',
    },
  })
  return NextResponse.json({ exercise })
}
