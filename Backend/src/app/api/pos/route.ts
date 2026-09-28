import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'
import { postBookVoucher } from '@/lib/accounting'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const allowed = getSelectedBranchIds(session, url.searchParams.get('branches'))
  const sales = await db.posSale.findMany({
    where: { ...(allowed ? { branchId: { in: allowed } } : {}) },
    include: { branch: true, lines: { include: { inventoryItem: true } } },
    orderBy: { date: 'desc' },
    take: 100,
  })
  return NextResponse.json({ sales })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('pos.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { branchId, lines, paymentMethod, paymentAccountId, notes } = await req.json()
  if (!branchId || !lines?.length || !paymentMethod) {
    return NextResponse.json({ error: 'branchId, lines, paymentMethod required' }, { status: 400 })
  }
  if (!['Cash', 'Bank', 'Online'].includes(paymentMethod)) {
    return NextResponse.json({ error: 'paymentMethod must be Cash, Bank, or Online' }, { status: 400 })
  }

  // Compute total + reduce inventory
  const total = lines.reduce((s: number, l: any) => s + (Number(l.unitPrice) * Number(l.quantity)), 0)

  // Generate sale number
  const saleCount = await db.posSale.count()
  const saleNo = `POS-${String(saleCount + 1).padStart(5, '0')}`

  // Account mappings
  const mappings = await db.accountMapping.findMany({ where: { OR: [{ branchId }, { branchId: null }] } })
  const pickMapping = (key: string) => mappings.find(m => m.key === key && m.branchId === branchId) || mappings.find(m => m.key === key && m.branchId === null)
  const posIncomeMapping = pickMapping('posIncome')
  const cashMapping = pickMapping('cashAccount') || pickMapping('posCash')
  const bankMapping = pickMapping('bankAccount') || pickMapping('posBank')

  if (!posIncomeMapping) return NextResponse.json({ error: 'Account mapping "posIncome" not configured' }, { status: 500 })

  // Book account (debited by the book voucher): Cash → cashAccount, Bank/Online → bankAccount
  const bookMapping = paymentMethod === 'Cash' ? cashMapping : bankMapping
  if (!bookMapping && !paymentAccountId) {
    return NextResponse.json({ error: `Account mapping "${paymentMethod === 'Cash' ? 'cashAccount' : 'bankAccount'}" not configured` }, { status: 500 })
  }
  const bookChartId = bookMapping?.accountId || paymentAccountId

  try {
    // Reduce inventory + create sale (atomic)
    const sale = await db.$transaction(async (tx) => {
      // reduce inventory quantities
      for (const l of lines) {
        const item = await tx.inventoryItem.findUnique({ where: { id: l.inventoryItemId } })
        if (!item) throw new Error(`Inventory item ${l.inventoryItemId} not found`)
        if (item.quantity < Number(l.quantity)) throw new Error(`Insufficient stock for ${item.name} (have ${item.quantity}, need ${l.quantity})`)
        await tx.inventoryItem.update({ where: { id: l.inventoryItemId }, data: { quantity: { decrement: Number(l.quantity) } } })
      }
      // create sale
      const s = await tx.posSale.create({
        data: {
          saleNo,
          branchId,
          cashierId: session.id,
          total,
          paymentMethod,
          paymentAccountId: bookChartId,
          status: 'Completed',
          notes,
          lines: { create: lines.map((l: any) => ({ inventoryItemId: l.inventoryItemId, quantity: Number(l.quantity), unitPrice: Number(l.unitPrice), amount: Number(l.unitPrice) * Number(l.quantity) })) },
        },
        include: { lines: true },
      })
      return s
    })

    // Post the book voucher (CRV for cash, BRV for bank/online); detail line credited to posIncome
    const branch = await db.branch.findUnique({ where: { id: branchId } })
    if (!branch) throw new Error('Invalid branch')
    const voucher = await postBookVoucher({
      voucherType: paymentMethod === 'Cash' ? 'CRV' : 'BRV',
      voucherDate: new Date(),
      branchId,
      branchCode: branch.code,
      bookChartId,
      description: `POS Sale ${saleNo}`,
      reference: sale.id,
      paymentMode: paymentMethod === 'Cash' ? 'Cash' : 'Online Transfer',
      lines: [
        { accountId: posIncomeMapping.accountId, amount: total, lineDescription: `POS income`, billType: 'Sales Bill' },
      ],
      postedById: session.id,
    })

    // link book voucher to sale
    await db.posSale.update({ where: { id: sale.id }, data: { bookVoucherId: voucher.id } })

    return NextResponse.json({ sale, voucher })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'POS sale failed' }, { status: 400 })
  }
}
