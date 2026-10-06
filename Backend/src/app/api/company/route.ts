import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { makeDefaultsId } from '@/lib/ids'
import { existsSync } from 'fs'
import path from 'path'

// Admin Defaults — backed by the dbo.Defaults table (the legacy Company table
// was removed by the SQL Server migration). The company name is freely
// editable (the old trg_Defaults_CompanyNameLock was dropped by
// 14_company_and_finance_options.sql). The API enforces company.edit
// permission and logs every name change to dbo.AuditLog.
//
// LOGO VALIDATION (server-side authoritative):
//   - The logo path must start with /uploads/ and reference a file that
//     actually exists in the uploads directory.
//   - The file extension must be one of png/jpg/jpeg/webp/gif/svg.
//   - The 2 MB size limit is enforced by the /api/uploads route when
//     purpose=logo is passed; this route only validates the path.

const ALLOWED_LOGO_EXTS = ['png', 'jpg', 'jpeg', 'webp', 'gif', 'svg']

export async function GET() {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const defaults = await db.defaults.findFirst()
  // keep the historical `company` response shape; mirror companyName as name
  const company = defaults ? { ...defaults, name: defaults.companyName } : null

  // Also return the effective FinanceDefaults (company-wide) so the frontend
  // can format money values using defaultCurrency + decimalPlaces.
  let financeDefaults: any = null
  try {
    financeDefaults = await db.financeDefaults.findFirst({
      where: { branchId: null },
      select: { defaultCurrency: true, decimalPlaces: true },
    })
  } catch { /* pre-migration: columns may not exist */ }

  return NextResponse.json({ company, defaults, financeDefaults })
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

  // Validate logo path if provided — must be a relative /uploads/ path
  // pointing to an existing file with an allowed extension.
  let logoValue = data.logo
  if (logoValue !== undefined && logoValue !== null && logoValue !== '') {
    const logoStr = String(logoValue)
    if (!logoStr.startsWith('/uploads/')) {
      return NextResponse.json({ error: 'Logo must be an uploaded file path (starts with /uploads/)' }, { status: 400 })
    }
    const ext = logoStr.split('.').pop()?.toLowerCase() || ''
    if (!ALLOWED_LOGO_EXTS.includes(ext)) {
      return NextResponse.json({ error: `Logo must be a PNG, JPG, WebP, GIF, or SVG file (got .${ext})` }, { status: 400 })
    }
    // Verify the file exists on disk
    const filePath = path.join(process.cwd(), 'public', 'uploads', path.basename(logoStr))
    if (!existsSync(filePath)) {
      return NextResponse.json({ error: 'Logo file not found on disk. Upload the file first via /api/uploads.' }, { status: 400 })
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
