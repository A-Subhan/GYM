import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'
import { makeEquipmentId } from '@/lib/ids'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const allowed = getSelectedBranchIds(session, url.searchParams.get('branches'))
  const condition = url.searchParams.get('condition')
  const search = url.searchParams.get('q')

  const equipment = await db.equipment.findMany({
    where: {
      ...(allowed ? { branchId: { in: allowed } } : {}),
      ...(condition ? { condition } : {}),
      ...(search ? { OR: [{ code: { contains: search } }, { name: { contains: search } }] } : {}),
    },
    include: { branch: true, maintenance: true },
    orderBy: { createdAt: 'desc' },
    take: 200,
  })
  return NextResponse.json({ equipment })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('equipment.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.name || !data.branchId) return NextResponse.json({ error: 'Name and branch required' }, { status: 400 })

  // Business ID: EQ-00001, EQ-00002, … (IdSequence-backed)
  const code = await makeEquipmentId()

  const equipment = await db.equipment.create({
    data: {
      code,
      name: data.name,
      category: data.category || 'Machine',
      description: data.description,
      purchaseDate: data.purchaseDate ? new Date(data.purchaseDate) : null,
      purchasePrice: Number(data.purchasePrice) || 0,
      quantity: Number(data.quantity) || 1,
      condition: data.condition || 'Working',
      status: data.status || 'Active',
      branchId: data.branchId,
      billReference: data.billReference,
      billImage: data.billImage,
      image: data.image,
    },
  })
  await db.auditLog.create({ data: { userId: session.id, action: 'CREATE', module: 'equipment', details: JSON.stringify({ id: equipment.id, code }) } })
  return NextResponse.json({ equipment })
}
