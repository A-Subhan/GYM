import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET() {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('vouchers.view')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const accounts = await db.account.findMany({
    where: { isDetail: true },
    orderBy: { code: 'asc' },
    include: { branch: true, parent: true },
  })

  const hasExisting = accounts.some(a => a.openingBalance && a.openingBalance > 0)

  return NextResponse.json({
    accounts: accounts.map(a => ({
      id: a.id,
      code: a.code,
      name: a.name,
      accountType: a.accountType,
      isActive: a.isActive,
      debit: a.openingBalanceType === 'Dr' ? a.openingBalance : 0,
      credit: a.openingBalanceType === 'Cr' ? a.openingBalance : 0,
    })),
    hasExisting,
  })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('vouchers.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { entries } = await req.json() as { entries: Array<{ id: string; debit: number; credit: number }> }

  if (!Array.isArray(entries)) {
    return NextResponse.json({ error: 'entries must be an array' }, { status: 400 })
  }

  // Validate: no negative, no both Dr and Cr
  for (const e of entries) {
    const dr = Number(e.debit) || 0
    const cr = Number(e.credit) || 0
    if (dr < 0 || cr < 0) {
      return NextResponse.json({ error: 'Negative opening amounts are not allowed' }, { status: 400 })
    }
    if (dr > 0 && cr > 0) {
      return NextResponse.json({ error: 'Account cannot have both Debit and Credit' }, { status: 400 })
    }
  }

  // NO balance requirement — OTB is allowed to save unbalanced

  await db.$transaction(async (tx) => {
    await tx.account.updateMany({
      where: { openingBalance: { gt: 0 } },
      data: { openingBalance: 0, openingBalanceType: null },
    })
    for (const e of entries) {
      const dr = Number(e.debit) || 0
      const cr = Number(e.credit) || 0
      if (dr > 0) {
        await tx.account.update({ where: { id: e.id }, data: { openingBalance: dr, openingBalanceType: 'Dr' } })
      } else if (cr > 0) {
        await tx.account.update({ where: { id: e.id }, data: { openingBalance: cr, openingBalanceType: 'Cr' } })
      } else {
        await tx.account.update({ where: { id: e.id }, data: { openingBalance: 0, openingBalanceType: null } })
      }
    }
  })

  await db.auditLog.create({
    data: {
      userId: session.id,
      action: 'UPDATE',
      module: 'opening-balance',
      details: JSON.stringify({ accountCount: entries.filter(e => (Number(e.debit) || Number(e.credit)) > 0).length }),
    },
  })

  return NextResponse.json({ success: true })
}
