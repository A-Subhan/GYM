import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

// Payroll master file — earning/deduction heads used by the payroll engine.
// Codes are auto-generated PMF-001, PMF-002, … via IdSequence key 'PAYROLLMASTER'.

const TYPES = ['Earning', 'Deduction'] as const
const CALC_TYPES = ['Fixed', 'Percent'] as const

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('masters.view')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const url = new URL(req.url)
  const branchId = url.searchParams.get('branchId')
  const type = url.searchParams.get('type')
  const isActiveParam = url.searchParams.get('isActive')

  if (type && !TYPES.includes(type as (typeof TYPES)[number])) {
    return NextResponse.json({ error: 'type must be Earning or Deduction' }, { status: 400 })
  }

  const records = await db.payrollMasterFile.findMany({
    where: {
      // branch scoping: global rows (branchId NULL) plus the given branch
      ...(branchId ? { OR: [{ branchId: null }, { branchId }] } : {}),
      ...(type ? { type } : {}),
      ...(isActiveParam !== null && isActiveParam !== '' ? { isActive: isActiveParam === 'true' } : {}),
    },
    include: { branch: { select: { id: true, name: true } } },
    orderBy: [{ type: 'asc' }, { code: 'asc' }],
  })
  return NextResponse.json({ records })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('masters.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  const name = typeof data.name === 'string' ? data.name.trim() : ''
  if (!name) return NextResponse.json({ error: 'Name is required' }, { status: 400 })
  if (!TYPES.includes(data.type)) return NextResponse.json({ error: 'Type must be Earning or Deduction' }, { status: 400 })
  const calcType = data.calcType ? data.calcType : 'Fixed'
  if (!CALC_TYPES.includes(calcType)) return NextResponse.json({ error: 'Calc Type must be Fixed or Percent' }, { status: 400 })
  const amount = Number(data.amount)
  if (isNaN(amount) || amount < 0) return NextResponse.json({ error: 'Amount must be a number >= 0' }, { status: 400 })

  // Name must be unique within the active set
  const duplicate = await db.payrollMasterFile.findFirst({ where: { name, isActive: true } })
  if (duplicate) {
    return NextResponse.json({ error: `An active payroll master file named "${name}" already exists (${duplicate.code})` }, { status: 400 })
  }

  try {
    // Reserve PMF-0xx sequence and create the row atomically
    const record = await db.$transaction(async (tx) => {
      const seqRow = await tx.idSequence.upsert({
        where: { key: 'PAYROLLMASTER' },
        update: { next: { increment: 1 } },
        create: { key: 'PAYROLLMASTER', next: 2 },
      })
      const code = `PMF-${String(seqRow.next - 1).padStart(3, '0')}`
      return tx.payrollMasterFile.create({
        data: {
          code,
          name,
          type: data.type,
          calcType,
          amount,
          isActive: data.isActive !== false,
          branchId: data.branchId || null,
        },
      })
    })
    await db.auditLog.create({
      data: { userId: session.id, action: 'CREATE', module: 'payroll-master-file', details: JSON.stringify({ id: record.id, code: record.code }) },
    })
    return NextResponse.json({ record })
  } catch (e: any) {
    if (e?.code === 'P2002') return NextResponse.json({ error: 'A payroll master file with this name or code already exists' }, { status: 400 })
    throw e
  }
}
