import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const allowed = getSelectedBranchIds(session, url.searchParams.get('branches'))
  const search = url.searchParams.get('q')

  const items = await db.inventoryItem.findMany({
    where: {
      ...(allowed ? { branchId: { in: allowed } } : {}),
      ...(search ? { OR: [{ code: { contains: search } }, { name: { contains: search } }] } : {}),
    },
    include: { branch: true },
    orderBy: { name: 'asc' },
    take: 200,
  })
  return NextResponse.json({ items })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('inventory.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.name || !data.branchId) return NextResponse.json({ error: 'Name and branch required' }, { status: 400 })

  const count = await db.inventoryItem.count()
  const code = `ITM-${String(count + 1).padStart(4, '0')}`

  const item = await db.inventoryItem.create({
    data: {
      code,
      name: data.name,
      category: data.category,
      description: data.description,
      unit: data.unit,
      quantity: Number(data.quantity) || 0,
      reorderLevel: Number(data.reorderLevel) || 0,
      purchasePrice: Number(data.purchasePrice) || 0,
      salePrice: Number(data.salePrice) || 0,
      branchId: data.branchId,
    },
  })
  return NextResponse.json({ item })
}
