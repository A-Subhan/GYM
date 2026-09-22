import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const { id } = await params
  const data = await req.json()

  if (data.action === 'convert') {
    if (!session.permissions.includes('prospects.convert')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    // mark as converted; member creation handled by separate members.create call
    const updated = await db.prospect.update({ where: { id }, data: { status: 'Converted', convertedMemberId: data.convertedMemberId || null } })
    await db.auditLog.create({ data: { userId: session.id, action: 'CONVERT', module: 'prospects', details: JSON.stringify({ id, convertedMemberId: data.convertedMemberId }) } })
    return NextResponse.json({ prospect: updated })
  }

  if (!session.permissions.includes('prospects.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const prospect = await db.prospect.update({
    where: { id },
    data: {
      name: data.name,
      phone: data.phone,
      whatsapp: data.whatsapp,
      gender: data.gender,
      age: data.age ? Number(data.age) : null,
      interestedMembership: data.interestedMembership,
      preferredBranchId: data.preferredBranchId,
      source: data.source,
      status: data.status,
      followUpDate: data.followUpDate ? new Date(data.followUpDate) : null,
      notes: data.notes,
    },
  })
  return NextResponse.json({ prospect })
}

export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('prospects.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const { id } = await params
  await db.prospect.delete({ where: { id } })
  await db.auditLog.create({ data: { userId: session.id, action: 'DELETE', module: 'prospects', details: JSON.stringify({ id }) } })
  return NextResponse.json({ success: true })
}
