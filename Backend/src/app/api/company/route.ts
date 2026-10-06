import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { makeDefaultsId } from '@/lib/ids'

// Admin Defaults — backed by the dbo.Defaults table (the legacy Company table
// was removed by the SQL Server migration). The company name is freely
// editable (the old trg_Defaults_CompanyNameLock was dropped by
// 14_company_and_finance_options.sql). The API enforces company.edit
// permission and logs every name change to dbo.AuditLog.
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
    // single-row table — create on first save with CMP-001-style id
    const id = await makeDefaultsId()
    defaults = await db.defaults.create({ data: { id } })
  }

  // Resolve the submitted company name (accept both companyName and name)
  const submittedName =
    data.companyName !== undefined && data.companyName !== null
      ? String(data.companyName).trim()
      : data.name !== undefined && data.name !== null
        ? String(data.name).trim()
        : undefined

  // Validate logo path if provided — must be a relative /uploads/ path or null
  let logoValue = data.logo
  if (logoValue !== undefined && logoValue !== null && logoValue !== '') {
    const logoStr = String(logoValue)
    if (!logoStr.startsWith('/uploads/')) {
      return NextResponse.json({ error: 'Logo must be an uploaded file path (starts with /uploads/)' }, { status: 400 })
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
      logo: logoValue,
      strn: data.strn,
      ntn: data.ntn,
      fbr: data.fbr,
      financeType: data.financeType ?? data.accountingType,
      coaLevelDigits: data.coaLevelDigits,
      coaLocked: data.coaLocked,
    },
  })

  // Audit log — include the name change details if the name was updated
  const auditDetails: any = { id: updated.id }
  if (submittedName !== undefined && submittedName !== (defaults.companyName || '').trim()) {
    auditDetails.companyNameChanged = { from: defaults.companyName || null, to: submittedName }
  }
  if (logoValue !== undefined && logoValue !== defaults.logo) {
    auditDetails.logoChanged = { from: defaults.logo || null, to: logoValue }
  }
  await db.auditLog.create({ data: { userId: session.id, action: 'UPDATE', module: 'company', details: JSON.stringify(auditDetails) } })

  return NextResponse.json({ company: { ...updated, name: updated.companyName }, defaults: updated })
}
