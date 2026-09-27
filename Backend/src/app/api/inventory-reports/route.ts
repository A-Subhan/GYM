import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const report = url.searchParams.get('report')
  const allowed = getSelectedBranchIds(session, url.searchParams.get('branches'))
  const branchFilter = allowed ? { branchId: { in: allowed } } : {}

  if (!report) {
    return NextResponse.json({ reports: [
      { key: 'current-stock', name: 'Current Stock' },
      { key: 'stock-movement', name: 'Stock Movement' },
      { key: 'low-stock', name: 'Low Stock' },
      { key: 'purchases', name: 'Purchases' },
      { key: 'supplier-purchases', name: 'Supplier Purchases' },
      { key: 'branch-wise-stock', name: 'Branch Wise Stock' },
      { key: 'inventory-valuation', name: 'Inventory Valuation' },
    ]})
  }

  if (report === 'current-stock') {
    const items = await db.inventoryItem.findMany({
      where: branchFilter,
      include: { branch: true },
      orderBy: { name: 'asc' }
    })
    return NextResponse.json({ report: { title: 'Current Stock', rows: items } })
  }

  if (report === 'low-stock') {
    const items = await db.inventoryItem.findMany({
      where: branchFilter,
      include: { branch: true },
    })
    const lowStock = items.filter(i => i.quantity <= i.reorderLevel)
    return NextResponse.json({ report: { title: 'Low Stock', rows: lowStock } })
  }

  if (report === 'purchases') {
    const purchases = await db.purchase.findMany({
      where: branchFilter,
      include: { supplier: true, branch: true, lines: true },
      orderBy: { purchaseDate: 'desc' }
    })
    return NextResponse.json({ report: { title: 'Purchases', rows: purchases } })
  }

  if (report === 'stock-movement') {
    const movements = await db.stockMovement.findMany({
      where: branchFilter,
      include: { inventoryItem: true, branch: true },
      orderBy: { date: 'desc' },
      take: 200,
    })
    return NextResponse.json({ report: { title: 'Stock Movement', rows: movements } })
  }

  if (report === 'inventory-valuation') {
    const items = await db.inventoryItem.findMany({
      where: branchFilter,
      include: { branch: true },
    })
    const rows = items.map(i => ({
      code: i.code,
      name: i.name,
      quantity: i.quantity,
      purchasePrice: i.purchasePrice || 0,
      salePrice: i.salePrice || 0,
      stockValue: (i.quantity || 0) * (i.purchasePrice || 0),
      saleValue: (i.quantity || 0) * (i.salePrice || 0),
      branch: i.branch?.name,
    }))
    return NextResponse.json({ report: { title: 'Inventory Valuation', rows } })
  }

  return NextResponse.json({ report: { title: 'Report not implemented', rows: [] } })
}
