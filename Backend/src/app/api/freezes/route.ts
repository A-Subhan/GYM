import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('freeze.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const { id, action, freezeFrom, freezeTo, reason } = await req.json()
  if (!id) return NextResponse.json({ error: 'Freeze id required' }, { status: 400 })

  if (action === 'lift') {
    const freeze = await db.membershipFreeze.update({ where: { id }, data: { status: 'Lifted' } })
    await db.auditLog.create({ data: { userId: session.id, action: 'UPDATE', module: 'freeze', details: JSON.stringify({ id, action: 'lift' }) } })
    return NextResponse.json({ freeze })
  }

  // general edit of dates/reason (days recomputed)
  const existing = await db.membershipFreeze.findUnique({ where: { id } })
  if (!existing) return NextResponse.json({ error: 'Freeze not found' }, { status: 404 })
  const from = freezeFrom ? new Date(freezeFrom) : existing.freezeFrom
  const to = freezeTo ? new Date(freezeTo) : existing.freezeTo
  if (isNaN(from.getTime()) || isNaN(to.getTime())) return NextResponse.json({ error: 'Invalid freeze dates' }, { status: 400 })
  if (to.getTime() < from.getTime()) return NextResponse.json({ error: 'Freeze To date must be on or after From date' }, { status: 400 })
  const days = Math.ceil((to.getTime() - from.getTime()) / (24 * 60 * 60 * 1000)) + 1
  const freeze = await db.membershipFreeze.update({
    where: { id },
    data: {
      freezeFrom: from,
      freezeTo: to,
      days,
      ...(reason !== undefined ? { reason } : {}),
    },
  })
  await db.auditLog.create({ data: { userId: session.id, action: 'UPDATE', module: 'freeze', details: JSON.stringify({ id }) } })
  return NextResponse.json({ freeze })
}

export async function DELETE(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('freeze.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const url = new URL(req.url)
  const id = url.searchParams.get('id')
  if (!id) return NextResponse.json({ error: 'Freeze id required' }, { status: 400 })
  await db.membershipFreeze.delete({ where: { id } })
  await db.auditLog.create({ data: { userId: session.id, action: 'DELETE', module: 'freeze', details: JSON.stringify({ id }) } })
  return NextResponse.json({ success: true })
}
