import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET() {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const defaults = await db.financeDefaults.findFirst()
  return NextResponse.json({ defaults })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('finance.settings')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  const existing = await db.financeDefaults.findFirst()

  // COA Level Detailing lock: once any Chart exists, level detailing cannot change
  if (existing && existing.coaLevelLocked && data.coaLevelDetailing !== undefined && data.coaLevelDetailing !== existing.coaLevelDetailing) {
    const chartCount = await db.charts.count()
    if (chartCount > 0) {
      return NextResponse.json({ error: 'COA Level Detailing cannot be changed after Chart accounts have been created under this configuration.' }, { status: 400 })
    }
  }

  if (existing) {
    const updated = await db.financeDefaults.update({
      where: { id: existing.id },
      data: {
        financeType: data.financeType,
        coaLevelDetailing: data.coaLevelDetailing,
        // coaLevelLocked is managed automatically by the COA creation logic
        defaultCashAccountId: data.defaultCashAccountId,
        defaultBankAccountId: data.defaultBankAccountId,
        defaultTaxHeadId: data.defaultTaxHeadId,
        financialYearId: data.financialYearId,
      },
    })
    await db.auditLog.create({ data: { userId: session.id, action: 'UPDATE', module: 'financeDefaults', details: JSON.stringify({ id: updated.id }) } })
    return NextResponse.json({ defaults: updated })
  }

  const created = await db.financeDefaults.create({
    data: {
      financeType: data.financeType || 'FIFO',
      coaLevelDetailing: data.coaLevelDetailing || 2,
      coaLevelLocked: false,
      defaultCashAccountId: data.defaultCashAccountId,
      defaultBankAccountId: data.defaultBankAccountId,
      defaultTaxHeadId: data.defaultTaxHeadId,
      financialYearId: data.financialYearId,
    },
  })
  await db.auditLog.create({ data: { userId: session.id, action: 'CREATE', module: 'financeDefaults', details: JSON.stringify({ id: created.id }) } })
  return NextResponse.json({ defaults: created })
}
