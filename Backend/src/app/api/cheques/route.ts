import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'

// ============================================================================
// Cheque management after the final-schema migration.
// The legacy dbo.Cheque table was REMOVED — cheque data now lives directly on
// dbo.BankBookLine (chequeNo / chequeAmount / chequeBankName / chequeStatus).
// This route reads and updates those line fields. Status history is no longer
// persisted (the new line table has no history columns); the audit log keeps
// the status-change trail instead.
// ============================================================================

const CHEQUE_STATUSES = ['Hold', 'Cleared', 'Bounced', 'Cancelled']

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const status = url.searchParams.get('status')
  const allowed = getSelectedBranchIds(session, url.searchParams.get('branches') || url.searchParams.get('branchId'))

  const lines = await db.bankBookLine.findMany({
    where: {
      chequeNo: { not: null },
      ...(status && status !== 'all' ? { chequeStatus: status } : {}),
      ...(allowed ? { voucher: { branchId: { in: allowed } } } : {}),
    },
    include: {
      account: { select: { id: true, name: true } },
      voucher: { include: { branch: true, bookChart: true } },
    },
    orderBy: { createdAt: 'desc' },
    take: 300,
  })

  // Flattened shape keeps the old "cheques" contract for callers.
  const cheques = lines.map((l) => ({
    id: l.id,
    lineId: l.id,
    voucherId: l.voucherId,
    voucher: l.voucher,
    chequeNo: l.chequeNo,
    chequeDate: l.voucher.voucherDate,
    bankName: l.chequeBankName,
    amount: l.chequeAmount ?? l.amount,
    status: l.chequeStatus || 'Hold',
    accountId: l.accountId,
    account: l.account,
    lineDescription: l.lineDescription,
    createdAt: l.createdAt,
  }))
  return NextResponse.json({ cheques })
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('cheques.status')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { ids, status, reason } = await req.json()
  if (!Array.isArray(ids) || !ids.length || !status) return NextResponse.json({ error: 'ids[] and status required' }, { status: 400 })
  if (!CHEQUE_STATUSES.includes(status)) return NextResponse.json({ error: `Invalid status (allowed: ${CHEQUE_STATUSES.join(', ')})` }, { status: 400 })

  const updated: any[] = []
  for (const id of ids) {
    const line = await db.bankBookLine.findUnique({ where: { id } })
    if (!line || !line.chequeNo) continue
    const updatedLine = await db.bankBookLine.update({
      where: { id },
      data: { chequeStatus: status },
    })
    updated.push({
      id: updatedLine.id,
      voucherId: updatedLine.voucherId,
      chequeNo: updatedLine.chequeNo,
      amount: updatedLine.chequeAmount ?? updatedLine.amount,
      status: updatedLine.chequeStatus,
    })
  }
  await db.auditLog.create({
    data: { userId: session.id, action: 'STATUS', module: 'cheques', details: JSON.stringify({ ids, status, reason }) },
  })
  return NextResponse.json({ updated })
}
