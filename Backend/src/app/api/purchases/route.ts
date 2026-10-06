import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const allowed = getSelectedBranchIds(session, url.searchParams.get('branches'))
  const records = await db.purchase.findMany({
    where: { ...(allowed ? { branchId: { in: allowed } } : {}) },
    include: { supplier: true, branch: true, lines: true },
    orderBy: { purchaseDate: 'desc' },
    take: 200,
  })
  return NextResponse.json({ records })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const data = await req.json()
  if (!data.branchId) return NextResponse.json({ error: 'Branch required' }, { status: 400 })
  const count = await db.purchase.count()
  const purchaseNo = `PUR-${String(count + 1).padStart(5, '0')}`
  const total = (data.lines || []).reduce((s: number, l: any) => s + (Number(l.amount) || 0), 0)
  const record = await db.purchase.create({
    data: {
      purchaseNo,
      supplierId: data.supplierId || null,
      branchId: data.branchId,
      totalAmount: total,
      status: data.status || 'Pending',
      notes: data.notes,
      lines: {
        create: (data.lines || []).map((l: any) => ({
          inventoryItemId: l.inventoryItemId || null,
          itemName: l.itemName,
          quantity: Number(l.quantity) || 0,
          unitPrice: Number(l.unitPrice) || 0,
          amount: Number(l.amount) || 0,
        }))
      }
    },
    include: { lines: true, supplier: true }
  })
  // If status is Received, add stock
  if (data.status === 'Received') {
    for (const line of (data.lines || [])) {
      if (line.inventoryItemId) {
        await db.inventoryItem.update({
          where: { id: line.inventoryItemId },
          data: { quantity: { increment: Number(line.quantity) || 0 } }
        })
        await db.stockMovement.create({
          data: {
            inventoryItemId: line.inventoryItemId,
            branchId: data.branchId,
            movementType: 'PurchaseIn',
            quantity: Number(line.quantity) || 0,
            reference: purchaseNo,
            referenceId: record.id,
          }
        })
      }
    }
  }
  return NextResponse.json({ record })
}
