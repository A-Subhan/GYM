import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const status = url.searchParams.get('status')
  const branchId = url.searchParams.get('branchId')
  const allowed = session.accessibleBranchIds === '*' ? null : session.accessibleBranchIds.split(',')

  const cheques = await db.cheque.findMany({
    where: {
      ...(status ? { status } : {}),
      ...(branchId && branchId !== 'all' ? { voucher: { branchId } } : {}),
      ...(allowed ? { voucher: { branchId: { in: allowed } } } : {}),
    },
    include: { voucher: { include: { branch: true, bookAccount: true } } },
    orderBy: { chequeDate: 'desc' },
    take: 200,
  })
  return NextResponse.json({ cheques })
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('cheques.status')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { ids, status, reason } = await req.json()
  if (!Array.isArray(ids) || !ids.length || !status) return NextResponse.json({ error: 'ids[] and status required' }, { status: 400 })
  if (!['Hold', 'Clear', 'Bounced', 'Deposited'].includes(status)) return NextResponse.json({ error: 'Invalid status' }, { status: 400 })

  const now = new Date()
  const updated = []
  for (const id of ids) {
    const cheque = await db.cheque.findUnique({ where: { id } })
    if (!cheque) continue
    const history = cheque.statusHistory ? JSON.parse(cheque.statusHistory) : []
    history.push({ from: cheque.status, to: status, at: now.toISOString(), by: session.id, reason })
    const updatedCheque = await db.cheque.update({
      where: { id },
      data: { status, statusChangedAt: now, statusChangedBy: session.id, statusHistory: JSON.stringify(history) },
    })
    updated.push(updatedCheque)
  }
  await db.auditLog.create({
    data: { userId: session.id, action: 'STATUS', module: 'cheques', details: JSON.stringify({ ids, status, reason }) },
  })
  return NextResponse.json({ updated })
}
