import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

const TYPES = ['Earning', 'Deduction'] as const
const CALC_TYPES = ['Fixed', 'Percent'] as const

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('masters.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { id } = await params
  const data = await req.json()

  const existing = await db.payrollMasterFile.findUnique({ where: { id } })
  if (!existing) return NextResponse.json({ error: 'Payroll master file not found' }, { status: 404 })

  if (data.type !== undefined && !TYPES.includes(data.type)) {
    return NextResponse.json({ error: 'Type must be Earning or Deduction' }, { status: 400 })
  }
  if (data.calcType !== undefined && !CALC_TYPES.includes(data.calcType)) {
    return NextResponse.json({ error: 'Calc Type must be Fixed or Percent' }, { status: 400 })
  }
  let amount: number | undefined
  if (data.amount !== undefined) {
    amount = Number(data.amount)
    if (isNaN(amount) || amount < 0) return NextResponse.json({ error: 'Amount must be a number >= 0' }, { status: 400 })
  }
  const name = typeof data.name === 'string' ? data.name.trim() : undefined
  if (name !== undefined && !name) return NextResponse.json({ error: 'Name cannot be empty' }, { status: 400 })
  if (name) {
    const duplicate = await db.payrollMasterFile.findFirst({
      where: { name, isActive: true, id: { not: id } },
    })
    if (duplicate) {
      return NextResponse.json({ error: `An active payroll master file named "${name}" already exists (${duplicate.code})` }, { status: 400 })
    }
  }

  try {
    const record = await db.payrollMasterFile.update({
      where: { id },
      data: {
        name,
        type: data.type,
        calcType: data.calcType,
        amount,
        isActive: data.isActive,
        branchId: data.branchId !== undefined ? (data.branchId || null) : undefined,
      },
    })
    await db.auditLog.create({
      data: { userId: session.id, action: 'UPDATE', module: 'payroll-master-file', details: JSON.stringify({ id, code: record.code }) },
    })
    return NextResponse.json({ record })
  } catch (e: any) {
    if (e?.code === 'P2002') return NextResponse.json({ error: 'A payroll master file with this name or code already exists' }, { status: 400 })
    throw e
  }
}

export async function DELETE(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('masters.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { id } = await params
  const existing = await db.payrollMasterFile.findUnique({ where: { id } })
  if (!existing) return NextResponse.json({ error: 'Payroll master file not found' }, { status: 404 })

  // Soft-off: heads may be referenced by historical payroll runs — deactivate instead of delete
  await db.payrollMasterFile.update({ where: { id }, data: { isActive: false } })
  await db.auditLog.create({
    data: { userId: session.id, action: 'DELETE', module: 'payroll-master-file', details: JSON.stringify({ id, code: existing.code, softDelete: true }) },
  })
  return NextResponse.json({ success: true, message: `Payroll master file ${existing.code} deactivated` })
}
