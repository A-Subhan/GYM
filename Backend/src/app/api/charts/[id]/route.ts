import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { getChartBalance } from '@/lib/accounting'

// GET /api/charts/[id] — one account + children + current balance
export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const { id } = await params
  const chart = await db.chart.findUnique({
    where: { id },
    include: {
      parent: { select: { id: true, name: true, accountType: true, isControl: true } },
      branch: { select: { id: true, name: true, code: true } },
    },
  })
  if (!chart) return NextResponse.json({ error: 'Account not found' }, { status: 404 })
  const children = await db.chart.findMany({ where: { parentId: id }, orderBy: { id: 'asc' } })
  const balance = await getChartBalance(id)
  return NextResponse.json({ chart, children, balance })
}

// PATCH /api/charts/[id]
// COA hierarchy hard-lock: once any voucher line exists for the account, only
// name / contact info / strn / ntn / fbr / paymentTerms / isActive may change.
export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('finance.coa')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { id } = await params
  const data = await req.json()
  const existing = await db.chart.findUnique({ where: { id } })
  if (!existing) return NextResponse.json({ error: 'Account not found' }, { status: 404 })

  const lineCount = await db.bookVoucherLine.count({ where: { accountId: id } })
  const hasLines = lineCount > 0

  if (hasLines) {
    // Locked: parentId, accountType, isControl/isDetail, bookType, accountTag
    const chart = await db.chart.update({
      where: { id },
      data: {
        name: data.name !== undefined ? String(data.name).trim() : undefined,
        contactName: data.contactName,
        phone: data.phone,
        email: data.email,
        address: data.address,
        strn: data.strn,
        ntn: data.ntn,
        fbr: data.fbr,
        paymentTerms: data.paymentTerms,
        isActive: data.isActive !== undefined ? data.isActive : undefined,
      },
    })
    await db.auditLog.create({
      data: { userId: session.id, action: 'UPDATE', module: 'coa', details: JSON.stringify({ id, locked: true, reason: 'account has voucher lines' }) },
    })
    return NextResponse.json({ chart, locked: true, message: 'Account is in use — only name, contact info, STRN/NTN/FBR, payment terms and status can be changed.' })
  }

  // No lines yet — structural fields may still change
  let parentId = existing.parentId
  if (data.parentId !== undefined) {
    parentId = data.parentId || null
    if (parentId === id) return NextResponse.json({ error: 'Account cannot be its own parent' }, { status: 400 })
    if (parentId) {
      // walk up the hierarchy to prevent cycles
      let p = await db.chart.findUnique({ where: { id: parentId } })
      if (!p) return NextResponse.json({ error: 'Parent account not found' }, { status: 400 })
      let guard = 0
      while (p) {
        if (p.id === id) return NextResponse.json({ error: 'Cannot move an account under one of its own descendants' }, { status: 400 })
        p = p.parentId ? await db.chart.findUnique({ where: { id: p.parentId } }) : null
        if (++guard > 20) return NextResponse.json({ error: 'Invalid parent hierarchy' }, { status: 400 })
      }
    }
  }

  const isControl = data.isControl !== undefined ? data.isControl === true : existing.isControl
  const isDetail = data.isControl !== undefined ? !isControl : (data.isDetail !== undefined ? data.isDetail === true : existing.isDetail)

  if (isDetail && parentId) {
    const parent = await db.chart.findUnique({ where: { id: parentId } })
    if (parent && !parent.isControl) {
      return NextResponse.json({ error: 'Detail accounts must sit under a control account' }, { status: 400 })
    }
  }

  try {
    const chart = await db.chart.update({
      where: { id },
      data: {
        name: data.name !== undefined ? String(data.name).trim() : undefined,
        parentId,
        accountType: data.accountType,
        bookType: data.bookType,
        accountTag: data.accountTag,
        isControl,
        isDetail,
        isActive: data.isActive !== undefined ? data.isActive : undefined,
        branchId: data.branchId,
        contactName: data.contactName,
        phone: data.phone,
        email: data.email,
        address: data.address,
        bankName: data.bankName,
        bankAccountNo: data.bankAccountNo,
        bankBranch: data.bankBranch,
        cnic: data.cnic,
        strn: data.strn,
        ntn: data.ntn,
        fbr: data.fbr,
        paymentTerms: data.paymentTerms,
        description: data.description,
      },
    })
    await db.auditLog.create({
      data: { userId: session.id, action: 'UPDATE', module: 'coa', details: JSON.stringify({ id }) },
    })
    return NextResponse.json({ chart })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Failed to update account' }, { status: 400 })
  }
}

// DELETE /api/charts/[id] — hard delete ONLY when the account has no voucher
// lines and no children; otherwise rejected with 400.
export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('finance.coa')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { id } = await params
  const existing = await db.chart.findUnique({ where: { id } })
  if (!existing) return NextResponse.json({ error: 'Account not found' }, { status: 404 })

  const childCount = await db.chart.count({ where: { parentId: id } })
  if (childCount > 0) {
    return NextResponse.json({ error: `Cannot delete: ${childCount} child account(s) exist. Move or delete children first.` }, { status: 400 })
  }

  const lineCount = await db.bookVoucherLine.count({ where: { accountId: id } })
  if (lineCount > 0) {
    return NextResponse.json({ error: 'Account has voucher lines and cannot be deleted. Set it inactive instead.' }, { status: 400 })
  }

  // Referential guards (book account usage, knock-offs, mappings)
  const [cashUse, bankUse, knockUse] = await Promise.all([
    db.cashbookVoucher.count({ where: { bookChartId: id } }),
    db.bankbookVoucher.count({ where: { bookChartId: id } }),
    db.knockOff.count({ where: { accountId: id } }),
  ])
  if (cashUse + bankUse + knockUse > 0) {
    return NextResponse.json({ error: 'Account is referenced by vouchers or knock-offs and cannot be deleted. Set it inactive instead.' }, { status: 400 })
  }

  try {
    await db.accountMapping.deleteMany({ where: { accountId: id } })
    await db.chart.delete({ where: { id } })
    await db.auditLog.create({
      data: { userId: session.id, action: 'DELETE', module: 'coa', details: JSON.stringify({ id, hardDelete: true }) },
    })
    return NextResponse.json({ success: true })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Cannot delete account (referenced by other records)' }, { status: 400 })
  }
}
