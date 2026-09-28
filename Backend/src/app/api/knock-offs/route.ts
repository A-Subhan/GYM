import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { makeKnockOffBillId } from '@/lib/ids'

// Knock-off entries reduce the outstanding difference of an (unbalanced)
// Opening Trial Balance voucher. Each entry gets an auto Bill ID:
//   OTB-{branchCode}/{0000001}
export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const openTbVoucherId = url.searchParams.get('openTbVoucherId')

  const knockOffs = await db.knockOff.findMany({
    where: { ...(openTbVoucherId ? { openTbVoucherId } : {}) },
    include: {
      account: { select: { id: true, name: true, accountType: true } },
      openTbVoucher: { select: { id: true, totalDebit: true, totalCredit: true, difference: true, status: true } },
    },
    orderBy: { knockedOffAt: 'asc' },
    take: 500,
  })

  let outstanding: number | null = null
  if (openTbVoucherId) {
    const voucher = await db.openTbVoucher.findUnique({ where: { id: openTbVoucherId } })
    if (voucher) {
      const knocked = knockOffs.reduce((s, k) => s + k.amount, 0)
      outstanding = Math.max(0, Math.round((Math.abs(voucher.difference) - knocked) * 100) / 100)
    }
  }
  return NextResponse.json({ knockOffs, outstanding })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('vouchers.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  const { openTbVoucherId, accountId, description, amount, side } = data
  if (!openTbVoucherId || !accountId || !description || !amount || !side) {
    return NextResponse.json({ error: 'openTbVoucherId, accountId, description, amount, side are required' }, { status: 400 })
  }
  if (String(description).trim().length > 20) {
    return NextResponse.json({ error: 'Description must be 20 characters or less' }, { status: 400 })
  }
  if (!['Debit', 'Credit'].includes(side)) {
    return NextResponse.json({ error: 'side must be Debit or Credit' }, { status: 400 })
  }
  const amt = Number(amount)
  if (!(amt > 0)) return NextResponse.json({ error: 'Amount must be greater than zero' }, { status: 400 })

  const voucher = await db.openTbVoucher.findUnique({ where: { id: openTbVoucherId } })
  if (!voucher) return NextResponse.json({ error: 'Opening TB voucher not found' }, { status: 404 })
  if (voucher.status === 'Reversed') return NextResponse.json({ error: 'Cannot knock off a reversed voucher' }, { status: 400 })

  const account = await db.chart.findUnique({ where: { id: accountId } })
  if (!account) return NextResponse.json({ error: 'Account not found' }, { status: 400 })
  if (account.isControl) return NextResponse.json({ error: 'Knock-off account must be a detail account' }, { status: 400 })

  // Enforce: sum(knockOffs.amount) <= |difference| of the voucher
  const existing = await db.knockOff.findMany({ where: { openTbVoucherId } })
  const knocked = existing.reduce((s, k) => s + k.amount, 0)
  const outstanding = Math.round((Math.abs(voucher.difference) - knocked) * 100) / 100
  if (amt > outstanding + 0.009) {
    return NextResponse.json({ error: `Knock-off exceeds the outstanding difference (remaining ${outstanding.toFixed(2)})` }, { status: 400 })
  }

  const branch = await db.branch.findUnique({ where: { id: voucher.branchId } })
  const billId = await makeKnockOffBillId(branch?.code || 'MAIN')

  const knockOff = await db.knockOff.create({
    data: {
      billId,
      openTbVoucherId,
      accountId,
      description: String(description).trim().slice(0, 20),
      amount: amt,
      side,
      createdById: data.createdById || session.id,
    },
    include: { account: { select: { id: true, name: true, accountType: true } } },
  })
  await db.auditLog.create({
    data: { userId: session.id, action: 'CREATE', module: 'knock-offs', details: JSON.stringify({ id: knockOff.id, billId, openTbVoucherId, amount: amt, side }) },
  })

  const newOutstanding = Math.max(0, Math.round((outstanding - amt) * 100) / 100)
  return NextResponse.json({ knockOff, outstanding: newOutstanding })
}
