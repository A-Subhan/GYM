import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

// Exercises master — now served from the Gym Master File:
//   gymmaster      category '001' = "Exercises"
//   gymmasterdetail items      = individual exercises (0010001, 0010002, ...)
// The response keeps the legacy { exercises: [...] } shape so the workout
// plan editor and other consumers continue to work unchanged.
const EXERCISE_CATEGORY = '001'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const branchId = url.searchParams.get('branchId')
  const allowed = session.accessibleBranchIds === '*' ? null : session.accessibleBranchIds.split(',')

  const category = await db.gymMaster.findUnique({ where: { id: EXERCISE_CATEGORY } })
  if (!category) return NextResponse.json({ exercises: [] })

  const details = await db.gymMasterDetail.findMany({
    where: {
      masterId: EXERCISE_CATEGORY,
      ...(branchId && branchId !== 'all' ? { OR: [{ branchId }, { branchId: null }] } : {}),
      ...(allowed ? { OR: [{ branchId: { in: allowed } }, { branchId: null }] } : {}),
    },
    include: { branch: { select: { id: true, name: true, code: true } } },
    orderBy: { id: 'asc' },
  })

  // Legacy-compatible exercise shape (code merged into a single `name` field)
  const exercises = details.map(d => ({
    id: d.id,
    code: d.id,
    name: d.name,
    description: d.description,
    branchId: d.branchId,
    branch: d.branch,
    status: d.isActive ? 'Active' : 'Inactive',
    isActive: d.isActive,
    createdAt: d.createdAt,
    updatedAt: d.updatedAt,
  }))
  return NextResponse.json({ exercises })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('workouts.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.name || !String(data.name).trim()) return NextResponse.json({ error: 'Name required' }, { status: 400 })

  // ensure the Exercises category exists
  let category = await db.gymMaster.findUnique({ where: { id: EXERCISE_CATEGORY } })
  if (!category) {
    category = await db.gymMaster.create({ data: { id: EXERCISE_CATEGORY, name: 'Exercises' } })
  }

  // item code = master code + 3-digit sequence
  const siblings = await db.gymMasterDetail.findMany({ where: { masterId: EXERCISE_CATEGORY }, select: { id: true } })
  let max = 0
  for (const s of siblings) {
    if (s.id.startsWith(EXERCISE_CATEGORY)) {
      const suffix = s.id.slice(EXERCISE_CATEGORY.length)
      if (/^\d{1,3}$/.test(suffix)) max = Math.max(max, parseInt(suffix, 10))
    }
  }
  const id = `${EXERCISE_CATEGORY}${String(max + 1).padStart(3, '0')}`

  try {
    const detail = await db.gymMasterDetail.create({
      data: {
        id,
        masterId: EXERCISE_CATEGORY,
        name: String(data.name).trim(),
        description: data.description || data.instructions || null,
        branchId: data.branchId || session.branchId || null,
        isActive: true,
      },
    })
    await db.auditLog.create({
      data: { userId: session.id, action: 'CREATE', module: 'masters', details: JSON.stringify({ kind: 'gym', id: detail.id, name: detail.name }) },
    })
    return NextResponse.json({
      exercise: {
        id: detail.id,
        code: detail.id,
        name: detail.name,
        status: 'Active',
      },
    })
  } catch (e: any) {
    if (e?.code === 'P2002') return NextResponse.json({ error: `Exercise code ${id} already exists` }, { status: 400 })
    throw e
  }
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('workouts.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.id) return NextResponse.json({ error: 'Exercise id required' }, { status: 400 })
  const existing = await db.gymMasterDetail.findUnique({ where: { id: data.id } })
  if (!existing || existing.masterId !== EXERCISE_CATEGORY) return NextResponse.json({ error: 'Exercise not found' }, { status: 404 })
  if (data.name !== undefined && !String(data.name).trim()) return NextResponse.json({ error: 'Name cannot be empty' }, { status: 400 })
  const detail = await db.gymMasterDetail.update({
    where: { id: data.id },
    data: {
      ...(data.name !== undefined ? { name: String(data.name).trim() } : {}),
      ...(data.description !== undefined ? { description: data.description || null } : {}),
      ...(data.isActive !== undefined ? { isActive: !!data.isActive } : {}),
    },
  })
  return NextResponse.json({ exercise: { id: detail.id, code: detail.id, name: detail.name, status: detail.isActive ? 'Active' : 'Inactive' } })
}

export async function DELETE(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('workouts.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const url = new URL(req.url)
  const id = url.searchParams.get('id')
  if (!id) return NextResponse.json({ error: 'Exercise id required' }, { status: 400 })
  const existing = await db.gymMasterDetail.findUnique({ where: { id } })
  if (!existing || existing.masterId !== EXERCISE_CATEGORY) return NextResponse.json({ error: 'Exercise not found' }, { status: 404 })
  const used = await db.workoutDayExercise.count({ where: { exerciseId: id } })
  if (used > 0) return NextResponse.json({ error: `Cannot delete — used in ${used} workout day(s)` }, { status: 400 })
  await db.gymMasterDetail.delete({ where: { id } })
  await db.auditLog.create({ data: { userId: session.id, action: 'DELETE', module: 'masters', details: JSON.stringify({ kind: 'gym', id }) } })
  return NextResponse.json({ success: true })
}
