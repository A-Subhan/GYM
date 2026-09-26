import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

// GET: list all detail-level charts + current OpenTB entries
export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('vouchers.view')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const url = new URL(req.url)
  const branchId = url.searchParams.get('branchId')

  const accounts = await db.charts.findMany({
    where: {
      isDetail: true,
      ...(branchId && branchId !== 'all' ? { branchId } : {}),
    },
    orderBy: { code: 'asc' },
    include: { branch: true, parent: true },
  })

  // Load existing OpenTB entries (one voucher with all its lines)
  const openVoucher = await db.openTB.findFirst({
    where: { ...(branchId && branchId !== 'all' ? { branchId } : {}) },
    include: { lines: true },
    orderBy: { createdAt: 'desc' },
  })
  const openByAccount: Record<string, { debit: number; credit: number }> = {}
  if (openVoucher) {
    for (const line of openVoucher.lines) {
      openByAccount[line.accountId] = { debit: line.debit, credit: line.credit }
    }
  }

  const hasExisting = accounts.some(a => openByAccount[a.id]?.debit || openByAccount[a.id]?.credit)

  return NextResponse.json({
    accounts: accounts.map(a => {
      const dr = openByAccount[a.id]?.debit || 0
      const cr = openByAccount[a.id]?.credit || 0
      return {
        id: a.id,
        code: a.code,
        name: a.name,
        accountType: a.accountType,
        accountTag: a.accountTag,
        bookType: a.bookType,
        isActive: a.isActive,
        debit: dr,
        credit: cr,
      }
    }),
    hasExisting,
    openVoucherNo: openVoucher?.voucherNo || null,
  })
}

// POST: Save opening trial balance (unbalanced allowed)
// Creates/updates a single OpenTB voucher per branch with all entries
export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('vouchers.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { entries, branchId } = await req.json() as {
    entries: Array<{ id: string; debit: number; credit: number }>
    branchId?: string
  }

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

  const targetBranchId = branchId || session.branchId
  if (!targetBranchId) return NextResponse.json({ error: 'branchId required' }, { status: 400 })

  // NO balance requirement — OTB is allowed to save unbalanced

  const date = new Date()
  const monthYear = String(date.getMonth() + 1).padStart(2, '0') + String(date.getFullYear()).slice(-2)

  await db.$transaction(async (tx) => {
    // Delete any existing OpenTB voucher for this branch
    const existing = await tx.openTB.findMany({ where: { branchId: targetBranchId }, include: { lines: true } })
    for (const v of existing) {
      await tx.openTBLine.deleteMany({ where: { voucherId: v.id } })
      await tx.openTB.delete({ where: { id: v.id } })
    }

    // Count existing OTB vouchers for voucher number generation
    const count = await tx.openTB.count({ where: { voucherNo: { startsWith: `OTV/${targetBranchId}/${monthYear}/` } } })
    const voucherNo = `OTV/${targetBranchId}/${monthYear}/${String(count + 1).padStart(6, '0')}`

    // Only create entries with non-zero debit/credit
    const validEntries = entries.filter(e => (Number(e.debit) || 0) > 0 || (Number(e.credit) || 0) > 0)

    if (validEntries.length > 0) {
      const totalDebit = validEntries.reduce((s, e) => s + (Number(e.debit) || 0), 0)
      const totalCredit = validEntries.reduce((s, e) => s + (Number(e.credit) || 0), 0)

      await tx.openTB.create({
        data: {
          voucherNo,
          voucherType: 'OTV',
          voucherDate: date,
          branchId: targetBranchId,
          status: 'Posted',
          postedById: session.id,
          postedAt: date,
          totalDebit,
          totalCredit,
          lines: {
            create: validEntries.map(e => ({
              accountId: e.id,
              debit: Number(e.debit) || 0,
              credit: Number(e.credit) || 0,
            })),
          },
        },
      })
    }
  })

  await db.auditLog.create({
    data: {
      userId: session.id,
      action: 'UPDATE',
      module: 'opening-balance',
      details: JSON.stringify({ accountCount: entries.filter(e => (Number(e.debit) || Number(e.credit)) > 0).length, branchId: targetBranchId }),
    },
  })

  return NextResponse.json({ success: true })
}
