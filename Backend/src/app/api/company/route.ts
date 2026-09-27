import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET() {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const company = await db.company.findFirst()
  return NextResponse.json({ company })
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('company.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  const existing = await db.company.findFirst()
  if (!existing) return NextResponse.json({ error: 'Company not initialized' }, { status: 404 })
  // companyId, accountingType are NOT changeable after setup per spec §38
  const company = await db.company.update({
    where: { id: existing.id },
    data: {
      name: data.name,
      address: data.address,
      phone: data.phone,
      email: data.email,
      website: data.website,
      logo: data.logo,
      strn: data.strn,
      ntn: data.ntn,
    },
  })
  await db.auditLog.create({ data: { userId: session.id, action: 'UPDATE', module: 'company', details: JSON.stringify({ id: company.id }) } })
  return NextResponse.json({ company })
}
