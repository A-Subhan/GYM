import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('tax.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { id } = await params
  const data = await req.json()

  const existing = await db.taxHead.findUnique({ where: { id } })
  if (!existing) return NextResponse.json({ error: 'Tax head not found' }, { status: 404 })

  const taxHead = await db.taxHead.update({
    where: { id },
    data: {
      shortName: data.shortName,
      name: data.name,
      taxType: data.taxType,
      rate: data.rate !== undefined ? Number(data.rate) : undefined,
      isActive: data.isActive !== undefined ? data.isActive : undefined,
    },
  })
  await db.auditLog.create({
    data: { userId: session.id, action: 'UPDATE', module: 'tax', details: JSON.stringify({ id, code: existing.code }) },
  })
  return NextResponse.json({ taxHead })
}

export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('tax.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { id } = await params
  const existing = await db.taxHead.findUnique({ where: { id } })
  if (!existing) return NextResponse.json({ error: 'Tax head not found' }, { status: 404 })

  // Final schema: book lines carry tax inline (taxPercent/taxAmount) with no
  // FK back to the tax head, so there is nothing to reference-check — delete.
  await db.taxHead.delete({ where: { id } })
  await db.auditLog.create({
    data: { userId: session.id, action: 'DELETE', module: 'tax', details: JSON.stringify({ id, hardDelete: true }) },
  })
  return NextResponse.json({ success: true })
}
