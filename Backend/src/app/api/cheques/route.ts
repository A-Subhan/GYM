import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'
import { reverseBookVoucher, type BookVoucherType } from '@/lib/book-vouchers'

// ============================================================================
// Cheque management after the final-schema migration.
// The legacy dbo.Cheque table was REMOVED — cheque data now lives directly on
// dbo.BankBookLine (chequeNo / chequeAmount / chequeBankName / chequeStatus).
// This route reads and updates those line fields. Status history is no longer
// persisted (the new line table has no history columns); the audit log keeps
// the status-change trail instead.
//
// BOUNCE / CANCEL RULES:
//   When a cheque status is set to "Bounced" or "Cancelled", the parent bank
//   voucher is REVERSED through reverseBookVoucher (creates a traceable
//   reversal entry with swapped debit/credit sides, and marks the original
//   as "Reversed"). This reverses the effect on the bank balance and the
//   ledger — the original posting stays in the database for the audit trail
//   (never a raw delete).
//
//   If the voucher is already Reversed (e.g. it was manually reversed
//   before the cheque bounced), the cheque status is still updated but no
//   duplicate reversal is created.
//
//   When status is set to "Cleared" or "Hold", only the chequeStatus field
//   is updated — no voucher reversal is created. If the voucher was
//   previously reversed by a bounce, re-clearing the cheque does NOT
//   un-reverse the voucher (the reversal stays as a traceable entry).
// ============================================================================

const CHEQUE_STATUSES = ['Hold', 'Cleared', 'Bounced', 'Cancelled']
const REVERSAL_STATUSES = ['Bounced', 'Cancelled']

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
  const reversals: any[] = []
  const errors: string[] = []

  for (const id of ids) {
    const line = await db.bankBookLine.findUnique({
      where: { id },
      include: { voucher: { select: { id: true, voucherType: true, status: true, branchId: true } } },
    })
    if (!line || !line.chequeNo) continue

    // Update the chequeStatus on the line
    const updatedLine = await db.bankBookLine.update({
      where: { id },
      data: { chequeStatus: status },
    })

    const result: any = {
      id: updatedLine.id,
      voucherId: updatedLine.voucherId,
      chequeNo: updatedLine.chequeNo,
      amount: updatedLine.chequeAmount ?? updatedLine.amount,
      status: updatedLine.chequeStatus,
    }

    // If the new status requires a reversal (Bounced or Cancelled), reverse
    // the parent voucher so the bank balance and ledger are corrected.
    // The reversal is a traceable entry — the original voucher stays in the
    // database (never a raw delete).
    if (REVERSAL_STATUSES.includes(status)) {
      const voucher = line.voucher
      if (voucher && voucher.status === 'Posted') {
        try {
          const reversalReason = `Cheque ${status.toLowerCase()}: ${line.chequeNo}${reason ? ` — ${reason}` : ''}`
          const reversalId = await reverseBookVoucher(
            voucher.id,
            voucher.voucherType as BookVoucherType,
            session.id,
            reversalReason,
          )
          result.reversalId = reversalId
          result.voucherReversed = true
          reversals.push({ voucherId: voucher.id, reversalId, chequeNo: line.chequeNo })
        } catch (e: any) {
          // If the reversal fails (e.g. voucher already has a reversal),
          // log the error but still update the cheque status.
          errors.push(`Cheque ${line.chequeNo}: cheque status updated to ${status} but voucher reversal failed: ${e.message}`)
          result.voucherReversed = false
          result.reversalError = e.message
        }
      } else if (voucher && voucher.status === 'Reversed') {
        // Voucher already reversed — no duplicate reversal needed
        result.voucherAlreadyReversed = true
      }
    }

    updated.push(result)
  }

  await db.auditLog.create({
    data: {
      userId: session.id,
      action: 'STATUS',
      module: 'cheques',
      details: JSON.stringify({ ids, status, reason, reversals, errors }),
    },
  })
  return NextResponse.json({ updated, reversals, errors: errors.length ? errors : undefined })
}
