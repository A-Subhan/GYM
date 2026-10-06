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
  const children = await db.chart.findMany({ where: { parentCode: id }, orderBy: { id: 'asc' } })
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

  const lineCount = await countChartLines(id)
  const hasLines = lineCount > 0

  if (hasLines) {
    // Locked: parentCode, accountType, isControl/isDetail, bookType, accountTag
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
        otherName: data.otherName,
        referenceNumber: data.referenceNumber,
        faxNumber: data.faxNumber,
        city: data.city,
        country: data.country,
        website: data.website,
        paymentTerms: data.paymentTerms,
        registrationNumber: data.registrationNumber,
        isActive: data.isActive !== undefined ? data.isActive : undefined,
      },
    })
    await db.auditLog.create({
      data: { userId: session.id, action: 'UPDATE', module: 'coa', details: JSON.stringify({ id, locked: true, reason: 'account has voucher lines' }) },
    })
    return NextResponse.json({ chart, locked: true, message: 'Account is in use — only name, contact info, STRN/NTN/FBR, payment terms and status can be changed.' })
  }

  // No lines yet — structural fields may still change
  // Final schema: single NOT NULL parentCode column ('ROOT' = tree root);
  // `parentId` is still accepted from callers and mapped onto parentCode.
  let parentCode = existing.parentCode
  if (data.parentCode !== undefined || data.parentId !== undefined) {
    parentCode = String(data.parentCode ?? data.parentId ?? '').trim().toUpperCase() || 'ROOT'
    if (parentCode === id) return NextResponse.json({ error: 'Account cannot be its own parent' }, { status: 400 })
    if (parentCode !== 'ROOT') {
      // walk up the hierarchy to prevent cycles
      let p = await db.chart.findUnique({ where: { id: parentCode } })
      if (!p) return NextResponse.json({ error: 'Parent account not found' }, { status: 400 })
      let guard = 0
      while (p) {
        if (p.id === id) return NextResponse.json({ error: 'Cannot move an account under one of its own descendants' }, { status: 400 })
        p = p.parentCode !== 'ROOT' ? await db.chart.findUnique({ where: { id: p.parentCode } }) : null
        if (++guard > 20) return NextResponse.json({ error: 'Invalid parent hierarchy' }, { status: 400 })
      }
    }
  }

  const isControl = data.isControl !== undefined ? data.isControl === true : existing.isControl
  const isDetail = data.isControl !== undefined ? !isControl : (data.isDetail !== undefined ? data.isDetail === true : existing.isDetail)

  if (isDetail && parentCode && parentCode !== 'ROOT') {
    const parent = await db.chart.findUnique({ where: { id: parentCode } })
    if (parent && !parent.isControl) {
      return NextResponse.json({ error: 'Detail accounts must sit under a control account' }, { status: 400 })
    }
  }

  try {
    const chart = await db.chart.update({
      where: { id },
      data: {
        name: data.name !== undefined ? String(data.name).trim() : undefined,
        parentCode,
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
        otherName: data.otherName,
        referenceNumber: data.referenceNumber,
        faxNumber: data.faxNumber,
        city: data.city,
        country: data.country,
        website: data.website,
        paymentTerms: data.paymentTerms,
        registrationNumber: data.registrationNumber,
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

  const childCount = await db.chart.count({ where: { parentCode: id } })
  if (childCount > 0) {
    return NextResponse.json({ error: `Cannot delete: ${childCount} child account(s) exist. Move or delete children first.` }, { status: 400 })
  }

  const lineCount = await countChartLines(id)
  if (lineCount > 0) {
    return NextResponse.json({ error: 'Account has voucher lines and cannot be deleted. Set it inactive instead.' }, { status: 400 })
  }

  // Referential guards (book account usage, knock-offs, mappings)
  const [cashUse, bankUse, knockUse] = await Promise.all([
    db.cashBook.count({ where: { bookChartId: id } }),
    db.bankBook.count({ where: { bookChartId: id } }),
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

/** Total voucher lines (all four books) posted against one account. */
async function countChartLines(chartId: string): Promise<number> {
  const [c, b, j, o] = await Promise.all([
    db.cashBookLine.count({ where: { accountId: chartId } }),
    db.bankBookLine.count({ where: { accountId: chartId } }),
    db.journalVoucherLine.count({ where: { accountId: chartId } }),
    db.openingTbLine.count({ where: { accountId: chartId } }),
  ])
  return c + b + j + o
}
