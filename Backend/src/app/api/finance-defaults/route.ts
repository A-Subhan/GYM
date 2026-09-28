import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

// GET /api/finance-defaults?branchId=… — FinanceDefaults row (branchId blank = company-wide) + financial year options
export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const branchId = url.searchParams.get('branchId') || null

  const defaults = await db.financeDefaults.findFirst({ where: { branchId } })
  const financialYears = await db.financialYear.findMany({
    orderBy: { startDate: 'desc' },
    select: { id: true, name: true, startDate: true, endDate: true, isActive: true, isClosed: true },
  })
  return NextResponse.json({ defaults, financialYears })
}

// POST /api/finance-defaults — upsert { branchId?, defaultCashAccountId?, defaultBankAccountId?, defaultTaxHeadId?, financialYearId? }
export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('finance.settings')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  const branchId = data.branchId || null

  if (branchId) {
    const branch = await db.branch.findFirst({ where: { id: branchId, isDeleted: false } })
    if (!branch) return NextResponse.json({ error: 'Branch not found' }, { status: 400 })
  }
  for (const field of ['defaultCashAccountId', 'defaultBankAccountId'] as const) {
    if (data[field]) {
      const account = await db.chart.findUnique({ where: { id: data[field] } })
      if (!account) return NextResponse.json({ error: `Invalid account for ${field}` }, { status: 400 })
    }
  }
  if (data.defaultTaxHeadId) {
    const taxHead = await db.taxHead.findUnique({ where: { id: data.defaultTaxHeadId } })
    if (!taxHead) return NextResponse.json({ error: 'Invalid tax head' }, { status: 400 })
  }
  if (data.financialYearId) {
    const fy = await db.financialYear.findUnique({ where: { id: data.financialYearId } })
    if (!fy) return NextResponse.json({ error: 'Invalid financial year' }, { status: 400 })
  }

  const payload = {
    defaultCashAccountId: data.defaultCashAccountId || null,
    defaultBankAccountId: data.defaultBankAccountId || null,
    defaultTaxHeadId: data.defaultTaxHeadId || null,
    financialYearId: data.financialYearId || null,
  }

  // nullable unique column (branchId): find first, then update or create
  const existing = await db.financeDefaults.findFirst({ where: { branchId } })
  const defaults = existing
    ? await db.financeDefaults.update({ where: { id: existing.id }, data: payload })
    : await db.financeDefaults.create({ data: { branchId, ...payload } })
  await db.auditLog.create({
    data: { userId: session.id, action: 'UPDATE', module: 'company', details: JSON.stringify({ screen: 'finance-defaults', branchId }) },
  })
  return NextResponse.json({ defaults })
}
