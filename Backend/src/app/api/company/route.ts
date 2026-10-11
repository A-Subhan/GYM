import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { makeDefaultsId } from '@/lib/ids'
import { existsSync } from 'fs'
import path from 'path'

// Admin Defaults — backed by the dbo.Defaults table.
// The company name is controlled by trg_Defaults_CompanyNameLock which
// blocks direct SQL updates unless SESSION_CONTEXT 'allow_company_name_change'
// is set to 1. The API sets this flag via the usp_Defaults_ChangeCompanyName
// stored procedure when company.edit permission is verified, then the
// trigger allows the change. Every change is logged to AuditLog.
//
// LOGO VALIDATION (server-side authoritative):
//   - The logo path must start with /uploads/ and reference a file that
//     actually exists in the uploads directory.
//   - The file extension must be one of png/jpg/jpeg/webp/gif/svg.
//   - SVG is accepted but sanitized by the upload route (no script tags).
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

  // If the company name is changing, use the stored procedure to set the
  // SESSION_CONTEXT flag that trg_Defaults_CompanyNameLock honors.
  // The stored procedure also writes the audit log entry.
  if (submittedName !== undefined && submittedName !== (defaults.companyName || '').trim()) {
    try {
      await db.$executeRawUnsafe(
        `EXEC dbo.usp_Defaults_ChangeCompanyName @newName = ${submittedName}, @changedBy = ${session.id}`,
      )
    } catch (e: any) {
      // If the stored procedure doesn't exist yet (pre-migration), fall back
      // to setting the session context manually + direct update
      try {
        await db.$executeRawUnsafe(`EXEC sp_set_session_context @key = N'allow_company_name_change', @value = 1`)
        await db.$executeRawUnsafe(`UPDATE dbo.Defaults SET companyName = '${submittedName.replace(/'/g, "''")}', updatedAt = SYSDATETIME() WHERE id = '${defaults.id}'`)
        await db.$executeRawUnsafe(`EXEC sp_set_session_context @key = N'allow_company_name_change', @value = 0`)
      } catch (e2: any) {
        return NextResponse.json({ error: `Failed to change company name: ${e2.message}` }, { status: 400 })
      }
    }
    // Log the name change to AuditLog
    await db.auditLog.create({
      data: {
        userId: session.id,
        action: 'COMPANY_NAME_CHANGE',
        module: 'company',
        details: JSON.stringify({ from: defaults.companyName || null, to: submittedName, by: session.id }),
      },
    })
  }

  // Update other fields (not companyName — that's done above)
  const updated = await db.defaults.update({
    where: { id: defaults.id },
    data: {
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

  // Re-fetch to get the updated companyName (it was set by the stored proc)
  const finalDefaults = await db.defaults.findFirst()
  const company = finalDefaults ? { ...finalDefaults, name: finalDefaults.companyName } : { ...updated, name: updated.companyName }

  // Audit log for non-name changes
  const auditDetails: any = { id: defaults.id }
  if (logoValue !== undefined && logoValue !== defaults.logo) {
    auditDetails.logoChanged = { from: defaults.logo || null, to: logoValue }
  }
  if (data.address !== undefined || data.phone !== undefined || data.email !== undefined || data.website !== undefined) {
    auditDetails.contactInfoUpdated = true
  }
  await db.auditLog.create({ data: { userId: session.id, action: 'UPDATE', module: 'company', details: JSON.stringify(auditDetails) } })

  return NextResponse.json({ company, defaults: finalDefaults || updated })
}
