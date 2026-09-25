import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET() {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const company = await db.company.findFirst()
  return NextResponse.json({ company })
}

// POST — initial company creation (only allowed once, with name)
export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('company.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const existing = await db.company.findFirst()
  if (existing) return NextResponse.json({ error: 'Company already exists. Use PATCH to update.' }, { status: 400 })

  const data = await req.json()
  if (!data.name) return NextResponse.json({ error: 'Company Name is required' }, { status: 400 })

  const company = await db.company.create({
    data: {
      companyId: data.companyId || 'CTR-01',
      name: data.name,
      address: data.address,
      phone: data.phone,
      email: data.email,
      website: data.website,
      logo: data.logo,
      accountingType: data.accountingType || 'FIFO',
      strn: data.strn,
      ntn: data.ntn,
      fbr: data.fbr,
    },
  })
  await db.auditLog.create({ data: { userId: session.id, action: 'CREATE', module: 'company', details: JSON.stringify({ id: company.id, name: company.name }) } })
  return NextResponse.json({ company })
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('company.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  const existing = await db.company.findFirst()
  if (!existing) return NextResponse.json({ error: 'Company not initialized' }, { status: 404 })
  // Company Name cannot be changed after initial setup
  const company = await db.company.update({
    where: { id: existing.id },
    data: {
      address: data.address,
      phone: data.phone,
      email: data.email,
      website: data.website,
      logo: data.logo,
      strn: data.strn,
      ntn: data.ntn,
      fbr: data.fbr,
    },
  })
  await db.auditLog.create({ data: { userId: session.id, action: 'UPDATE', module: 'company', details: JSON.stringify({ id: company.id }) } })
  return NextResponse.json({ company })
}
