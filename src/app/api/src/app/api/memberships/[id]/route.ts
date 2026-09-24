import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('memberships.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const { id } = await params
  const data = await req.json()
  const plan = await db.membershipPlan.update({
    where: { id },
    data: {
      name: data.name ? String(data.name) : undefined,
      durationDays: data.durationDays ? Number(data.durationDays) : undefined,
      amount: data.amount !== undefined ? Number(data.amount) : undefined,
      description: data.description !== undefined ? (data.description ? String(data.description) : null) : undefined,
      isActive: data.isActive !== undefined ? data.isActive : undefined,
    },
  })
  return NextResponse.json({ plan })
}

export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('memberships.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const { id } = await params
  await db.membershipPlan.delete({ where: { id } })
  return NextResponse.json({ success: true })
}
