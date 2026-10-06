import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const { id } = await params
  const shift = await db.shift.findUnique({ where: { id }, include: { branch: true } })
  if (!shift) return NextResponse.json({ error: 'Shift not found' }, { status: 404 })
  return NextResponse.json({ shift })
}

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('shifts.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { id } = await params
  const data = await req.json()

  const existing = await db.shift.findUnique({ where: { id } })
  if (!existing) return NextResponse.json({ error: 'Shift not found' }, { status: 404 })

  if (data.name !== undefined && !String(data.name).trim()) {
    return NextResponse.json({ error: 'Name cannot be empty' }, { status: 400 })
  }
  if (data.timeIn !== undefined && !String(data.timeIn).trim()) {
    return NextResponse.json({ error: 'Time In is required' }, { status: 400 })
  }
  if (data.timeOut !== undefined && !String(data.timeOut).trim()) {
    return NextResponse.json({ error: 'Time Out is required' }, { status: 400 })
  }

  const shift = await db.shift.update({
    where: { id },
    data: {
      name: data.name,
      timeIn: data.timeIn,
      timeOut: data.timeOut,
      workingDays: data.workingDays,
      branchId: data.branchId !== undefined ? (data.branchId || null) : undefined,
      isActive: data.isActive,
    },
    include: { branch: true },
  })
  await db.auditLog.create({
    data: { userId: session.id, action: 'UPDATE', module: 'shifts', details: JSON.stringify({ id, name: shift.name }) },
  })
  return NextResponse.json({ shift })
}

export async function DELETE(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('shifts.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const { id } = await params
  const existing = await db.shift.findUnique({ where: { id } })
  if (!existing) return NextResponse.json({ error: 'Shift not found' }, { status: 404 })

  // Hard delete only when no staff member is attached to this shift
  const staffCount = await db.staff.count({ where: { shiftId: id, isDeleted: false } })
  if (staffCount > 0) {
    return NextResponse.json({ error: `Cannot delete shift "${existing.name}" — ${staffCount} staff member(s) are assigned to it` }, { status: 400 })
  }

  await db.shift.delete({ where: { id } })
  await db.auditLog.create({
    data: { userId: session.id, action: 'DELETE', module: 'shifts', details: JSON.stringify({ id, name: existing.name }) },
  })
  return NextResponse.json({ success: true, message: `Shift "${existing.name}" deleted` })
}
