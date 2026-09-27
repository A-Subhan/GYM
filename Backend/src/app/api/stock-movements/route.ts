import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const allowed = getSelectedBranchIds(session, url.searchParams.get('branches'))
  const itemId = url.searchParams.get('itemId')
  const records = await db.stockMovement.findMany({
    where: {
      ...(allowed ? { branchId: { in: allowed } } : {}),
      ...(itemId ? { inventoryItemId: itemId } : {}),
    },
    include: { inventoryItem: true, branch: true },
    orderBy: { date: 'desc' },
    take: 200,
  })
  return NextResponse.json({ records })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const data = await req.json()
  if (!data.inventoryItemId || !data.branchId || !data.movementType) {
    return NextResponse.json({ error: 'inventoryItemId, branchId, movementType required' }, { status: 400 })
  }
  const qty = Number(data.quantity) || 0
  const record = await db.stockMovement.create({
    data: {
      inventoryItemId: data.inventoryItemId,
      branchId: data.branchId,
      movementType: data.movementType,
      quantity: qty,
      reference: data.reference,
      notes: data.notes,
    }
  })
  // Update stock
  if (data.movementType === 'StockIn' || data.movementType === 'PurchaseIn') {
    await db.inventoryItem.update({ where: { id: data.inventoryItemId }, data: { quantity: { increment: qty } } })
  } else if (data.movementType === 'StockOut' || data.movementType === 'PurchaseReturn') {
    await db.inventoryItem.update({ where: { id: data.inventoryItemId }, data: { quantity: { decrement: qty } } })
  } else if (data.movementType === 'Adjustment') {
    await db.inventoryItem.update({ where: { id: data.inventoryItemId }, data: { quantity: qty } })
  }
  return NextResponse.json({ record })
}
