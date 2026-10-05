import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { makeFinanceDefaultsId } from '@/lib/ids'
import { Prisma } from '@prisma/client'

// GET /api/finance-defaults?branchId=… — FinanceDefaults row (branchId blank = company-wide) + financial year options
//
// SAFE FOR PRE-MIGRATION: if the FinanceDefaults table doesn't have the 12
// expanded columns yet (migration 13 not run), the Prisma query fails
// because it tries to SELECT all schema columns. We catch the error and
// fall back to raw SQL that only selects the base columns.
export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const branchId = url.searchParams.get('branchId') || null

  let defaults: any = null
  try {
    defaults = await db.financeDefaults.findFirst({ where: { branchId } })
  } catch {
    // Fallback: only base columns exist (pre-migration)
    if (branchId) {
      defaults = await db.$queryRawUnsafe(
        'SELECT id, branchId, defaultCashAccountId, defaultBankAccountId, defaultTaxHeadId, financialYearId, createdAt, updatedAt FROM FinanceDefaults WHERE branchId = ?',
        branchId,
      )
      defaults = (defaults as any[])[0] || null
    } else {
      defaults = await db.$queryRawUnsafe(
        'SELECT id, branchId, defaultCashAccountId, defaultBankAccountId, defaultTaxHeadId, financialYearId, createdAt, updatedAt FROM FinanceDefaults WHERE branchId IS NULL',
      )
      defaults = (defaults as any[])[0] || null
    }
  }

  const financialYears = await db.financialYear.findMany({
    orderBy: { startDate: 'desc' },
    select: { id: true, name: true, startDate: true, endDate: true, isActive: true, isClosed: true },
  })
  return NextResponse.json({ defaults, financialYears })
}

// POST /api/finance-defaults — upsert
//   { branchId?, defaultCashAccountId?, defaultBankAccountId?, defaultTaxHeadId?, financialYearId?,
//     fiscalYearStart?, fiscalYearEnd?,
//     allowUnbalancedOTB?, allowBackDatedVouchers?, voucherApprovalRequired?,
//     allowEditPostedVouchers?, defaultCurrency?, decimalPlaces?,
//     defaultCashPaymentMode?, defaultBankPaymentMode?, allowNegativeCash?,
//     autoPostReceipts? }
//
// SAFE FOR PRE-MIGRATION: detects which columns exist via INFORMATION_SCHEMA
// and only includes existing columns in the payload. Pre-migration saves
// silently drop the expanded fields (DB defaults apply).
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

  // Detect which columns exist in the FinanceDefaults table (pre-migration safety)
  const existingCols = new Set<string>(
    (await db.$queryRawUnsafe(
      "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = 'dbo' AND TABLE_NAME = 'FinanceDefaults'",
    ) as { COLUMN_NAME: string }[]).map((r) => r.COLUMN_NAME),
  )

  const asDate = (v: any): Date | undefined => {
    if (v === undefined || v === null || v === '') return undefined
    const d = new Date(v)
    return isNaN(d.getTime()) ? undefined : d
  }

  // Build the payload — only include fields that exist in the DB
  const payload: any = {}
  payload.defaultCashAccountId = data.defaultCashAccountId ?? null
  payload.defaultBankAccountId = data.defaultBankAccountId ?? null
  payload.defaultTaxHeadId = data.defaultTaxHeadId ?? null
  payload.financialYearId = data.financialYearId ?? null

  const safeSet = (col: string, val: any) => {
    if (existingCols.has(col) && val !== undefined) payload[col] = val
  }
  safeSet('fiscalYearStart', data.fiscalYearStart !== undefined ? asDate(data.fiscalYearStart) ?? null : undefined)
  safeSet('fiscalYearEnd', data.fiscalYearEnd !== undefined ? asDate(data.fiscalYearEnd) ?? null : undefined)
  safeSet('allowUnbalancedOTB', data.allowUnbalancedOTB !== undefined ? !!data.allowUnbalancedOTB : undefined)
  safeSet('allowBackDatedVouchers', data.allowBackDatedVouchers !== undefined ? !!data.allowBackDatedVouchers : undefined)
  safeSet('voucherApprovalRequired', data.voucherApprovalRequired !== undefined ? !!data.voucherApprovalRequired : undefined)
  safeSet('allowEditPostedVouchers', data.allowEditPostedVouchers !== undefined ? !!data.allowEditPostedVouchers : undefined)
  safeSet('allowNegativeCash', data.allowNegativeCash !== undefined ? !!data.allowNegativeCash : undefined)
  safeSet('autoPostReceipts', data.autoPostReceipts !== undefined ? !!data.autoPostReceipts : undefined)
  safeSet('defaultCurrency', data.defaultCurrency !== undefined ? data.defaultCurrency || null : undefined)
  safeSet('decimalPlaces', data.decimalPlaces !== undefined ? Number(data.decimalPlaces) || 0 : undefined)
  safeSet('defaultCashPaymentMode', data.defaultCashPaymentMode !== undefined ? data.defaultCashPaymentMode || null : undefined)
  safeSet('defaultBankPaymentMode', data.defaultBankPaymentMode !== undefined ? data.defaultBankPaymentMode || null : undefined)

  // nullable unique column (branchId): find first, then update or create
  const existing = await db.financeDefaults.findFirst({ where: { branchId } })
  let defaults: any
  if (existing) {
    defaults = await db.financeDefaults.update({ where: { id: existing.id }, data: payload })
  } else {
    defaults = await db.financeDefaults.create({
      data: { id: await makeFinanceDefaultsId(), branchId, ...payload },
    })
  }
  await db.auditLog.create({
    data: { userId: session.id, action: 'UPDATE', module: 'company', details: JSON.stringify({ screen: 'finance-defaults', branchId }) },
  })
  return NextResponse.json({ defaults })
}
