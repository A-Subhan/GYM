import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

// Admin Defaults — backed by the dbo.Defaults table (the legacy Company table
// was removed by the SQL Server migration). companyName is WRITE-ONCE:
// the DB trigger trg_Defaults_CompanyNameLock blocks changes once set, and the
// API enforces the same rule up front.
export async function GET() {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const defaults = await db.defaults.findFirst()
  // keep the historical `company` response shape; mirror companyName as name
  const company = defaults ? { ...defaults, name: defaults.companyName } : null
  return NextResponse.json({ company, defaults })
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('company.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()

  let defaults = await db.defaults.findFirst()
  if (!defaults) {
    // single-row table — create on first save
    defaults = await db.defaults.create({ data: {} })
  }

  // Write-once company name: if a non-empty name is already stored and the
  // submitted value differs, reject (mirrors trg_Defaults_CompanyNameLock).
  const submittedName =
    data.companyName !== undefined && data.companyName !== null
      ? String(data.companyName).trim()
      : data.name !== undefined && data.name !== null
        ? String(data.name).trim()
        : undefined
  if (submittedName !== undefined) {
    const existingName = (defaults.companyName || '').trim()
    if (existingName && submittedName !== existingName) {
      return NextResponse.json({ error: 'Company name is locked' }, { status: 400 })
    }
  }

  const updated = await db.defaults.update({
    where: { id: defaults.id },
    data: {
      companyName: submittedName,
      address: data.address,
      phone: data.phone,
      email: data.email,
      website: data.website,
      logo: data.logo,
      strn: data.strn,
      ntn: data.ntn,
      fbr: data.fbr,
      financeType: data.financeType ?? data.accountingType,
      coaLevelDigits: data.coaLevelDigits,
      coaLocked: data.coaLocked,
    },
  })
  await db.auditLog.create({ data: { userId: session.id, action: 'UPDATE', module: 'company', details: JSON.stringify({ id: updated.id }) } })
  return NextResponse.json({ company: { ...updated, name: updated.companyName }, defaults: updated })
}
