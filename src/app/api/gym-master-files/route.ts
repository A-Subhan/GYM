import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

const MASTER_TYPES = ['Exercise', 'Equipment', 'ExerciseType']

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const masterType = url.searchParams.get('type')
  const branchId = url.searchParams.get('branchId')
  const records = await db.gymMasterFile.findMany({
    where: {
      ...(masterType ? { masterType } : {}),
      ...(branchId ? { OR: [{ branchId }, { branchId: null }] } : {}),
    },
    orderBy: { code: 'asc' },
  })
  return NextResponse.json({ records, types: MASTER_TYPES })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const data = await req.json()
  if (!data.masterType || !data.name) return NextResponse.json({ error: 'masterType and name required' }, { status: 400 })

  // Generate master ID and code
  // Master ID = 001 (per master type), Code = masterId + sequential (e.g. 0010001)
  const existing = await db.gymMasterFile.findMany({ where: { masterType: data.masterType } })
  const masterIds = existing.map(r => parseInt(r.masterId, 10)).filter(n => !isNaN(n))
  const nextMasterId = String((masterIds.length ? Math.max(...masterIds) : 0) + 1).padStart(3, '0')

  // For individual records under a master, code = masterId + 4-digit sequence
  const recordsUnderMaster = existing.filter(r => r.masterId === nextMasterId)
  const nextSeq = String(recordsUnderMaster.length + 1).padStart(4, '0')
  const code = `${nextMasterId}${nextSeq}`

  const record = await db.gymMasterFile.create({
    data: {
      masterType: data.masterType,
      masterId: nextMasterId,
      code,
      name: data.name,
      description: data.description,
      branchId: data.branchId || null,
      isActive: data.isActive !== false,
    },
  })
  return NextResponse.json({ record })
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const data = await req.json()
  if (!data.id) return NextResponse.json({ error: 'id required' }, { status: 400 })
  const record = await db.gymMasterFile.update({
    where: { id: data.id },
    data: { name: data.name, description: data.description, isActive: data.isActive },
  })
  return NextResponse.json({ record })
}

export async function DELETE(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const id = url.searchParams.get('id')
  if (!id) return NextResponse.json({ error: 'id required' }, { status: 400 })
  await db.gymMasterFile.delete({ where: { id } })
  return NextResponse.json({ success: true })
}
