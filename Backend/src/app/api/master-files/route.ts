import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

const MASTER_TYPES = [
  'Department', 'Designation', 'Education', 'Currency', 'Allowance',
  'Shift', 'MembershipSource', 'ProspectSource', 'EquipmentCategory', 'Equipment',
  'Banks', 'CardTypes', 'ExerciseCategories', 'TrainerSpecializations', 'FoodCategories', 'ItemCategories', 'Units', 'Brands', 'Warehouses', 'MaintenanceTypes',
]
// NOTE: leave types moved to dbo.payrollmasterfile (masterType = 'Leave Type')

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('masters.view')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const url = new URL(req.url)
  // Accept both `type` and `masterType` query params
  const masterType = url.searchParams.get('type') || url.searchParams.get('masterType')
  if (masterType && !MASTER_TYPES.includes(masterType)) {
    return NextResponse.json({ error: 'Invalid master type' }, { status: 400 })
  }
  // Optional branch scoping: rows where branchId IS NULL (global) OR branchId = given
  const branchId = url.searchParams.get('branchId')
  const records = await db.masterFile.findMany({
    where: {
      ...(masterType ? { masterType } : {}),
      ...(branchId ? { OR: [{ branchId: null }, { branchId }] } : {}),
    },
    orderBy: [{ masterType: 'asc' }, { code: 'asc' }],
  })
  return NextResponse.json({ records, types: MASTER_TYPES })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('masters.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  if (!data.masterType || !data.name) return NextResponse.json({ error: 'masterType and name required' }, { status: 400 })
  if (!MASTER_TYPES.includes(data.masterType)) return NextResponse.json({ error: 'Invalid master type' }, { status: 400 })

  // auto-generate code as 3-digit per masterType
  const existing = await db.masterFile.findMany({ where: { masterType: data.masterType } })
  const existingCodes = existing.map(r => parseInt(r.code, 10)).filter(n => !isNaN(n))
  const code = String((existingCodes.length ? Math.max(...existingCodes) : 0) + 1).padStart(3, '0')

  const record = await db.masterFile.create({
    data: {
      masterType: data.masterType,
      code,
      name: data.name,
      branchId: data.branchId || null,
      description: data.description,
      isActive: data.isActive !== false,
      extra: data.extra ? JSON.stringify(data.extra) : null,
    },
  })
  await db.auditLog.create({
    data: { userId: session.id, action: 'CREATE', module: 'masters', details: JSON.stringify({ id: record.id, masterType: data.masterType, code }) },
  })
  return NextResponse.json({ record })
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('masters.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.id) return NextResponse.json({ error: 'id required' }, { status: 400 })
  const record = await db.masterFile.update({
    where: { id: data.id },
    data: {
      name: data.name,
      branchId: data.branchId !== undefined ? (data.branchId || null) : undefined,
      description: data.description,
      isActive: data.isActive,
      extra: data.extra ? JSON.stringify(data.extra) : undefined,
    },
  })
  return NextResponse.json({ record })
}

export async function DELETE(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('masters.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const url = new URL(req.url)
  const id = url.searchParams.get('id')
  if (!id) return NextResponse.json({ error: 'id required' }, { status: 400 })
  await db.masterFile.delete({ where: { id } })
  await db.auditLog.create({ data: { userId: session.id, action: 'DELETE', module: 'masters', details: JSON.stringify({ id }) } })
  return NextResponse.json({ success: true })
}
