import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

// Payroll / HR master file — dbo.payrollmasterfile after the migration.
// The legacy calcType/amount component shape is still accepted for
// Earning/Deduction rows and stored inside `extra` (JSON) — see route.ts.

const MASTER_TYPES = ['Education', 'Designation', 'Country', 'Department', 'Shift', 'Leave Type', 'Allowance', 'Earning', 'Deduction'] as const
const CALC_TYPES = ['Fixed', 'Percent'] as const

type MasterType = (typeof MASTER_TYPES)[number]

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('masters.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { id } = await params
  const data = await req.json()

  const existing = await db.payrollMasterFile.findUnique({ where: { id } })
  if (!existing) return NextResponse.json({ error: 'Payroll master file not found' }, { status: 404 })

  if (data.masterType !== undefined || data.type !== undefined) {
    const mt = data.masterType ?? data.type
    if (!MASTER_TYPES.includes(mt as MasterType)) {
      return NextResponse.json({ error: `masterType must be one of ${MASTER_TYPES.join(', ')}` }, { status: 400 })
    }
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
    const masterType = data.masterType ?? data.type ?? existing.masterType
    const duplicate = await db.payrollMasterFile.findFirst({
      where: { masterType, name, id: { not: id } },
    })
    if (duplicate) {
      return NextResponse.json({ error: `A "${masterType}" master named "${name}" already exists` }, { status: 400 })
    }
  }

  // merge calcType/amount into the extra JSON when provided
  let extra: string | undefined
  if (data.calcType !== undefined || data.amount !== undefined || data.extra !== undefined) {
    const parsed = (typeof existing.extra === 'string' && existing.extra) ? JSON.parse(existing.extra) : {}
    const merged = {
      ...parsed,
      ...(data.calcType !== undefined ? { calcType: String(data.calcType) } : {}),
      ...(amount !== undefined ? { amount } : {}),
      ...(data.extra !== undefined ? (typeof data.extra === 'string' ? JSON.parse(data.extra) : data.extra) : {}),
    }
    extra = JSON.stringify(merged)
  }

  try {
    const record = await db.payrollMasterFile.update({
      where: { id },
      data: {
        name,
        masterType: data.masterType ?? data.type,
        description: data.description,
        extra,
        isActive: data.isActive,
        branchId: data.branchId !== undefined ? (data.branchId || null) : undefined,
      },
    })
    await db.auditLog.create({
      data: { userId: session.id, action: 'UPDATE', module: 'payroll-master-file', details: JSON.stringify({ id, name: record.name }) },
    })
    return NextResponse.json({ record })
  } catch (e: any) {
    if (e?.code === 'P2002') return NextResponse.json({ error: 'A payroll master file with this type and name already exists' }, { status: 400 })
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

  // Soft-off: masters may be referenced by historical data (leaves, staff, payroll) — deactivate instead of delete
  await db.payrollMasterFile.update({ where: { id }, data: { isActive: false } })
  await db.auditLog.create({
    data: { userId: session.id, action: 'DELETE', module: 'payroll-master-file', details: JSON.stringify({ id, name: existing.name, softDelete: true }) },
  })
  return NextResponse.json({ success: true, message: `Payroll master file ${existing.name} deactivated` })
}
