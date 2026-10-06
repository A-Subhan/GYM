import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

// GET /api/print-settings?documentType=BPV
//   Returns one PrintSettings row for the document type, or null.
// GET /api/print-settings (no param)
//   Returns all PrintSettings rows.
export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const documentType = url.searchParams.get('documentType')

  if (documentType) {
    let settings: any = null
    try {
      settings = await db.printSettings.findUnique({ where: { documentType } })
    } catch {
      // Table might not exist yet (pre-migration)
    }
    return NextResponse.json({ settings })
  }

  let allSettings: any[] = []
  try {
    allSettings = await db.printSettings.findMany({ orderBy: { documentType: 'asc' } })
  } catch {
    // Table might not exist yet
  }
  return NextResponse.json({ settings: allSettings })
}

// PUT /api/print-settings — upsert settings for a document type
//   { documentType, ...fields }
export async function PUT(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('finance.settings')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  const documentType = data.documentType
  if (!documentType) return NextResponse.json({ error: 'documentType is required' }, { status: 400 })

  const validDocTypes = ['BPV', 'BRV', 'CPV', 'CRV', 'JV', 'OTB', 'Reports']
  if (!validDocTypes.includes(documentType)) {
    return NextResponse.json({ error: `Invalid documentType (allowed: ${validDocTypes.join(', ')})` }, { status: 400 })
  }

  // Build the payload — only fields that exist in the table
  const payload: any = {}
  const fields = [
    'sigPreparedBy', 'sigPreparedBySource', 'sigPreparedByCustom',
    'sigCheckedBy', 'sigCheckedBySource', 'sigCheckedByCustom',
    'sigApprovedBy', 'sigApprovedBySource', 'sigApprovedByCustom',
    'sigPrintBy', 'sigPrintBySource', 'sigPrintByCustom',
    'showCompanyName', 'companyNamePosition', 'companyNameVertical',
    'showCompanyAddress', 'companyAddressPosition', 'companyAddressVertical',
    'showPrintDate', 'showPartyBalance',
    'showLogo', 'logoPosition', 'logoWidth', 'logoHeight',
    'fontFamily', 'fontSize',
  ]
  for (const f of fields) {
    if (data[f] !== undefined) payload[f] = data[f]
  }

  try {
    // Check if the table exists
    const existing = await db.printSettings.findUnique({ where: { documentType } })
    let settings: any
    if (existing) {
      settings = await db.printSettings.update({ where: { id: existing.id }, data: payload })
    } else {
      const id = `PRT-${documentType.toUpperCase()}`
      settings = await db.printSettings.create({ data: { id, documentType, ...payload } })
    }
    await db.auditLog.create({
      data: { userId: session.id, action: 'UPDATE', module: 'company', details: JSON.stringify({ screen: 'print-settings', documentType }) },
    })
    return NextResponse.json({ settings })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Failed to save print settings' }, { status: 400 })
  }
}
