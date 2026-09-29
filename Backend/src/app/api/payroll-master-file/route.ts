import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

// Payroll / HR master file — backed by dbo.payrollmasterfile after the SQL
// Server migration. Master categories: Education, Designation, Country,
// Department, Shift, Leave Type, Allowance (+ legacy earning/deduction heads).
//
// Backwards compatibility: the legacy PayrollMasterFile components shape
// (type Earning|Deduction, calcType, amount) is still accepted — such rows are
// stored as payrollmasterfile rows with masterType 'Earning'/'Deduction' and
// the calcType/amount serialized into the `extra` JSON field, e.g.
//   {"calcType":"Percent","amount":6}
// (readers should JSON.parse `extra` when masterType is Earning/Deduction).

const MASTER_TYPES = ['Education', 'Designation', 'Country', 'Department', 'Shift', 'Leave Type', 'Allowance', 'Earning', 'Deduction'] as const
const CALC_TYPES = ['Fixed', 'Percent'] as const

type MasterType = (typeof MASTER_TYPES)[number]

/** Serialize calcType/amount into the extra JSON column. */
function buildExtra(data: any): string | undefined {
  if (data.calcType === undefined && data.amount === undefined) {
    if (data.extra === undefined) return undefined
    return typeof data.extra === 'string' ? data.extra : JSON.stringify(data.extra)
  }
  const parsed = (typeof data.extra === 'string' && data.extra) ? JSON.parse(data.extra) : (data.extra || {})
  const merged = {
    ...parsed,
    ...(data.calcType !== undefined ? { calcType: String(data.calcType) } : {}),
    ...(data.amount !== undefined ? { amount: Number(data.amount) } : {}),
  }
  return JSON.stringify(merged)
}

function validateAmount(data: any): string | null {
  if (data.amount === undefined) return null
  const amount = Number(data.amount)
  if (isNaN(amount) || amount < 0) return 'Amount must be a number >= 0'
  if (data.calcType !== undefined && !CALC_TYPES.includes(data.calcType)) return 'Calc Type must be Fixed or Percent'
  return null
}

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('masters.view')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const url = new URL(req.url)
  // Accept `masterType` (final schema) or legacy `type`
  const masterType = url.searchParams.get('masterType') || url.searchParams.get('type')
  if (masterType && !MASTER_TYPES.includes(masterType as MasterType)) {
    return NextResponse.json({ error: `masterType must be one of ${MASTER_TYPES.join(', ')}` }, { status: 400 })
  }
  const branchId = url.searchParams.get('branchId')
  const isActiveParam = url.searchParams.get('isActive')

  const records = await db.payrollMasterFile.findMany({
    where: {
      // branch scoping: global rows (branchId NULL) plus the given branch
      ...(branchId ? { OR: [{ branchId: null }, { branchId }] } : {}),
      ...(masterType ? { masterType } : {}),
      ...(isActiveParam !== null && isActiveParam !== '' ? { isActive: isActiveParam === 'true' } : {}),
    },
    include: { branch: { select: { id: true, name: true } } },
    orderBy: [{ masterType: 'asc' }, { name: 'asc' }],
  })
  return NextResponse.json({ records, types: MASTER_TYPES })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('masters.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  const name = typeof data.name === 'string' ? data.name.trim() : ''
  if (!name) return NextResponse.json({ error: 'Name is required' }, { status: 400 })
  if (!MASTER_TYPES.includes(data.masterType)) {
    return NextResponse.json({ error: `masterType must be one of ${MASTER_TYPES.join(', ')}` }, { status: 400 })
  }
  const amountError = validateAmount(data)
  if (amountError) return NextResponse.json({ error: amountError }, { status: 400 })

  // Name must be unique per master type (DB unique constraint on masterType+name)
  const duplicate = await db.payrollMasterFile.findFirst({ where: { masterType: data.masterType, name } })
  if (duplicate) {
    return NextResponse.json({ error: `A "${data.masterType}" master named "${name}" already exists` }, { status: 400 })
  }

  try {
    const record = await db.payrollMasterFile.create({
      data: {
        masterType: data.masterType,
        name,
        description: data.description ?? null,
        extra: buildExtra(data) ?? null,
        isActive: data.isActive !== false,
        branchId: data.branchId || null,
      },
    })
    await db.auditLog.create({
      data: { userId: session.id, action: 'CREATE', module: 'payroll-master-file', details: JSON.stringify({ id: record.id, masterType: record.masterType, name: record.name }) },
    })
    return NextResponse.json({ record })
  } catch (e: any) {
    if (e?.code === 'P2002') return NextResponse.json({ error: 'A payroll master file with this type and name already exists' }, { status: 400 })
    throw e
  }
}
