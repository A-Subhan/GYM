import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

// PATCH — Edit account (only certain fields; code is NOT editable once created)
export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('finance.coa')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { id } = await params
  const data = await req.json()

  const existing = await db.account.findUnique({ where: { id } })
  if (!existing) return NextResponse.json({ error: 'Account not found' }, { status: 404 })

  // If changing parent, re-validate depth <= 7 and re-generate code if needed
  let newCode = existing.code
  let newParentId = existing.parentId
  if (data.parentId !== undefined && data.parentId !== existing.parentId) {
    newParentId = data.parentId || null
    // depth check
    let depth = 1
    let p = newParentId ? await db.account.findUnique({ where: { id: newParentId } }) : null
    while (p) {
      depth++
      p = p.parentId ? await db.account.findUnique({ where: { id: p.parentId } }) : null
    }
    if (depth > 7) return NextResponse.json({ error: 'Maximum hierarchy depth (7) exceeded' }, { status: 400 })

    // prevent making account a child of itself
    if (newParentId === id) return NextResponse.json({ error: 'Account cannot be its own parent' }, { status: 400 })

    // re-generate code under new parent
    if (newParentId) {
      const parent = await db.account.findUnique({ where: { id: newParentId } })
      if (!parent) return NextResponse.json({ error: 'Invalid parent' }, { status: 400 })
      const siblingCount = await db.account.count({ where: { parentId: newParentId, NOT: { id } } })
      newCode = `${parent.code}${String(siblingCount + 1).padStart(3, '0')}`
      if (newCode.length > 12) return NextResponse.json({ error: 'Account code exceeds 12 digits' }, { status: 400 })
    } else {
      // root — keep existing root code but verify
      const rootHeads = await db.account.findMany({ where: { parentId: null, NOT: { id } } })
      newCode = String(rootHeads.length + 1).padStart(2, '0')
    }
  }

  // If changing isControl, isDetail must flip
  let isDetail = existing.isDetail
  let isControl = existing.isControl
  if (data.isControl !== undefined) {
    isControl = !!data.isControl
    isDetail = !isControl
  }

  const account = await db.account.update({
    where: { id },
    data: {
      name: data.name,
      parentId: newParentId,
      code: newCode,
      accountType: data.accountType,
      bookType: data.bookType,
      accountTag: data.accountTag,
      isControl,
      isDetail,
      isActive: data.isActive !== undefined ? data.isActive : existing.isActive,
      branchId: data.branchId,
      contactName: data.contactName,
      phone: data.phone,
      email: data.email,
      address: data.address,
      bankName: data.bankName,
      bankAccountNo: data.bankAccountNo,
      bankBranch: data.bankBranch,
      cnic: data.cnic,
      ntn: data.ntn,
      description: data.description,
      openingBalance: data.openingBalance !== undefined ? Number(data.openingBalance) : undefined,
      openingBalanceType: data.openingBalanceType,
    },
  })
  await db.auditLog.create({
    data: { userId: session.id, action: 'UPDATE', module: 'coa', details: JSON.stringify({ id, code: newCode }) },
  })
  return NextResponse.json({ account })
}

// DELETE — Soft delete (deactivate) if account has no posted transactions; hard delete if no children & no lines
export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('finance.coa')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { id } = await params
  const account = await db.account.findUnique({ where: { id } })
  if (!account) return NextResponse.json({ error: 'Account not found' }, { status: 404 })

  // Check for children
  const childCount = await db.account.count({ where: { parentId: id } })
  if (childCount > 0) {
    return NextResponse.json({ error: `Cannot delete: ${childCount} child account(s) exist. Move or delete children first.` }, { status: 400 })
  }

  // Check for posted voucher lines
  const lineCount = await db.voucherLine.count({
    where: { accountId: id, voucher: { status: 'Posted' } },
  })
  if (lineCount > 0) {
    // Soft delete (deactivate) — account remains in COA but is inactive
    await db.account.update({ where: { id }, data: { isActive: false } })
    await db.auditLog.create({
      data: { userId: session.id, action: 'DELETE', module: 'coa', details: JSON.stringify({ id, softDelete: true, reason: 'Has posted transactions' }) },
    })
    return NextResponse.json({ account: { id }, softDeleted: true, message: 'Account has posted transactions — deactivated (soft delete) instead of hard delete.' })
  }

  // Hard delete (no children, no posted lines)
  // Also delete any draft voucher lines referencing it
  await db.voucherLine.deleteMany({ where: { accountId: id } })
  await db.accountMapping.deleteMany({ where: { accountId: id } })
  await db.account.delete({ where: { id } })
  await db.auditLog.create({
    data: { userId: session.id, action: 'DELETE', module: 'coa', details: JSON.stringify({ id, hardDelete: true }) },
  })
  return NextResponse.json({ success: true, hardDeleted: true })
}
