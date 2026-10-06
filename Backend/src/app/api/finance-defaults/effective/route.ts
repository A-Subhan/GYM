import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

// GET /api/finance-defaults/effective?branchId=…
//
// Returns the effective FinanceDefaults for a branch (branch-specific row
// wins over the company-wide row with branchId NULL). Used by voucher forms
// to pre-select the default book account and payment mode.
//
// SAFE FOR PRE-MIGRATION: if the expanded columns don't exist yet, the
// Prisma query fails and we fall back to raw SQL selecting only the base
// columns (the expanded fields will be returned as null/default in the
// response).
export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const branchId = url.searchParams.get('branchId') || null

  let defaults: any = null
  try {
    // Try branch-specific first, then fall back to company-wide.
    defaults = await db.financeDefaults.findFirst({
      where: { OR: [{ branchId }, { branchId: null }] },
      orderBy: [{ branchId: 'desc' }],
    })
  } catch {
    // Fallback: only base columns exist (pre-migration)
    if (branchId) {
      const rows = await db.$queryRawUnsafe(
        'SELECT TOP 1 id, branchId, defaultCashAccountId, defaultBankAccountId, defaultTaxHeadId, financialYearId, createdAt, updatedAt FROM FinanceDefaults WHERE branchId = ? OR branchId IS NULL ORDER BY CASE WHEN branchId IS NOT NULL THEN 0 ELSE 1 END',
        branchId,
      )
      defaults = (rows as any[])[0] || null
    } else {
      const rows = await db.$queryRawUnsafe(
        'SELECT TOP 1 id, branchId, defaultCashAccountId, defaultBankAccountId, defaultTaxHeadId, financialYearId, createdAt, updatedAt FROM FinanceDefaults WHERE branchId IS NULL',
      )
      defaults = (rows as any[])[0] || null
    }
  }

  return NextResponse.json({ defaults })
}
