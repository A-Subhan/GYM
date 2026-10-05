import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { makeFinanceDefaultsId } from '@/lib/ids'

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

// POST /api/finance-defaults — upsert
//   { branchId?, defaultCashAccountId?, defaultBankAccountId?, defaultTaxHeadId?, financialYearId?,
//     fiscalYearStart?, fiscalYearEnd?,
//     allowUnbalancedOTB?, allowBackDatedVouchers?, voucherApprovalRequired?,
//     allowEditPostedVouchers?, defaultCurrency?, decimalPlaces?,
//     defaultCashPaymentMode?, defaultBankPaymentMode?, allowNegativeCash?,
//     autoPostReceipts? }
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

  // Helper: convert an incoming value to a Date if truthy, else undefined (leave alone).
  const asDate = (v: any): Date | undefined => {
    if (v === undefined || v === null || v === '') return undefined
    const d = new Date(v)
    return isNaN(d.getTime()) ? undefined : d
  }

  // Build the payload. Each field is omitted when not present in the request,
  // so existing rows keep their previous values for those fields.
  const payload: any = {
    defaultCashAccountId: data.defaultCashAccountId ?? null,
    defaultBankAccountId: data.defaultBankAccountId ?? null,
    defaultTaxHeadId: data.defaultTaxHeadId ?? null,
    financialYearId: data.financialYearId ?? null,
  }
  if (data.fiscalYearStart !== undefined) payload.fiscalYearStart = asDate(data.fiscalYearStart) ?? null
  if (data.fiscalYearEnd !== undefined) payload.fiscalYearEnd = asDate(data.fiscalYearEnd) ?? null
  if (data.allowUnbalancedOTB !== undefined) payload.allowUnbalancedOTB = !!data.allowUnbalancedOTB
  if (data.allowBackDatedVouchers !== undefined) payload.allowBackDatedVouchers = !!data.allowBackDatedVouchers
  if (data.voucherApprovalRequired !== undefined) payload.voucherApprovalRequired = !!data.voucherApprovalRequired
  if (data.allowEditPostedVouchers !== undefined) payload.allowEditPostedVouchers = !!data.allowEditPostedVouchers
  if (data.allowNegativeCash !== undefined) payload.allowNegativeCash = !!data.allowNegativeCash
  if (data.autoPostReceipts !== undefined) payload.autoPostReceipts = !!data.autoPostReceipts
  if (data.defaultCurrency !== undefined) payload.defaultCurrency = data.defaultCurrency || null
  if (data.decimalPlaces !== undefined) payload.decimalPlaces = Number(data.decimalPlaces) || 0
  if (data.defaultCashPaymentMode !== undefined) payload.defaultCashPaymentMode = data.defaultCashPaymentMode || null
  if (data.defaultBankPaymentMode !== undefined) payload.defaultBankPaymentMode = data.defaultBankPaymentMode || null

  // nullable unique column (branchId): find first, then update or create
  const existing = await db.financeDefaults.findFirst({ where: { branchId } })
  const defaults = existing
    ? await db.financeDefaults.update({ where: { id: existing.id }, data: payload })
    : await db.financeDefaults.create({
        data: { id: await makeFinanceDefaultsId(), branchId, ...payload },
      })
  await db.auditLog.create({
    data: { userId: session.id, action: 'UPDATE', module: 'company', details: JSON.stringify({ screen: 'finance-defaults', branchId }) },
  })
  return NextResponse.json({ defaults })
}
