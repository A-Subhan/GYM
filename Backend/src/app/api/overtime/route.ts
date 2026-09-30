import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'

// Overtime — full CRUD + approval.
//   amount = hours × rate (rate defaults to the staff overtime rate)
//   Pending rows may be edited / deleted; Approved/Rejected rows are final.

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const allowed = getSelectedBranchIds(session, url.searchParams.get('branches'))
  const status = url.searchParams.get('status')
  const staffId = url.searchParams.get('staffId')
  const records = await db.overtime.findMany({
    where: {
      ...(status ? { status } : {}),
      ...(staffId ? { staffId } : {}),
      ...(allowed ? { staff: { branchId: { in: allowed } } } : { staff: { isDeleted: false } }),
    },
    include: { staff: true },
    orderBy: [{ date: 'desc' }],
    take: 300,
  })
  return NextResponse.json({ records })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('overtime.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.staffId || !data.date) return NextResponse.json({ error: 'staffId and date required' }, { status: 400 })
  if (!(Number(data.hours) > 0)) return NextResponse.json({ error: 'Hours must be greater than zero' }, { status: 400 })
  const staff = await db.staff.findUnique({ where: { id: data.staffId } })
  if (!staff || staff.isDeleted) return NextResponse.json({ error: 'Staff not found' }, { status: 404 })
  if (!staff.overtimeAllowed) return NextResponse.json({ error: 'Overtime not allowed for this staff member' }, { status: 400 })

  const hours = Number(data.hours)
  const rate = Number(data.rate) || staff.overtimeRate || 0
  const amount = Math.round(hours * rate * 100) / 100

  const record = await db.overtime.create({
    data: {
      staffId: data.staffId,
      date: new Date(data.date),
      hours,
      rate,
      amount,
      status: 'Pending',
      notes: data.notes,
    },
    include: { staff: true },
  })
  await db.auditLog.create({ data: { userId: session.id, action: 'CREATE', module: 'overtime', details: JSON.stringify({ id: record.id, staffId: staff.id, amount }) } })
  return NextResponse.json({ record })
}

// PATCH — approve/reject an overtime row, OR edit it while still Pending
export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const data = await req.json()
  if (!data.id) return NextResponse.json({ error: 'id required' }, { status: 400 })
  const existing = await db.overtime.findUnique({ where: { id: data.id } })
  if (!existing) return NextResponse.json({ error: 'Overtime not found' }, { status: 404 })

  // --- Approve / Reject ----------------------------------------------------
  if (data.status) {
    if (!['Approved', 'Rejected'].includes(data.status)) return NextResponse.json({ error: 'Invalid status' }, { status: 400 })
    if (!session.permissions.includes('overtime.approve')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    if (existing.status !== 'Pending') return NextResponse.json({ error: `Overtime is already ${existing.status}` }, { status: 400 })
    const record = await db.overtime.update({
      where: { id: data.id },
      data: { status: data.status, approvedBy: session.id, approvedAt: new Date() },
    })
    await db.auditLog.create({ data: { userId: session.id, action: data.status.toUpperCase(), module: 'overtime', details: JSON.stringify({ id: data.id }) } })
    return NextResponse.json({ record })
  }

  // --- Edit while Pending ----------------------------------------------------
  if (existing.status !== 'Pending') return NextResponse.json({ error: 'Only pending overtime can be edited' }, { status: 400 })
  if (!session.permissions.includes('overtime.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const hours = data.hours !== undefined ? Number(data.hours) : existing.hours
  const rate = data.rate !== undefined ? Number(data.rate) : existing.rate
  if (!(hours > 0)) return NextResponse.json({ error: 'Hours must be greater than zero' }, { status: 400 })
  let staffId = existing.staffId
  if (data.staffId && data.staffId !== existing.staffId) {
    const staff = await db.staff.findUnique({ where: { id: data.staffId } })
    if (!staff || staff.isDeleted) return NextResponse.json({ error: 'Staff not found' }, { status: 404 })
    if (!staff.overtimeAllowed) return NextResponse.json({ error: 'Overtime not allowed for this staff member' }, { status: 400 })
    staffId = staff.id
  }
  const record = await db.overtime.update({
    where: { id: data.id },
    data: {
      staffId,
      hours,
      rate,
      amount: Math.round(hours * rate * 100) / 100,
      date: data.date ? new Date(data.date) : existing.date,
      notes: data.notes !== undefined ? data.notes : existing.notes,
    },
    include: { staff: true },
  })
  await db.auditLog.create({ data: { userId: session.id, action: 'UPDATE', module: 'overtime', details: JSON.stringify({ id: data.id }) } })
  return NextResponse.json({ record })
}

// DELETE — pending rows only (approved overtime feeds payroll and is kept)
export async function DELETE(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('overtime.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const url = new URL(req.url)
  const id = url.searchParams.get('id')
  if (!id) return NextResponse.json({ error: 'id required' }, { status: 400 })
  const existing = await db.overtime.findUnique({ where: { id } })
  if (!existing) return NextResponse.json({ error: 'Overtime not found' }, { status: 404 })
  if (existing.status !== 'Pending') return NextResponse.json({ error: 'Only pending overtime can be deleted' }, { status: 400 })
  await db.overtime.delete({ where: { id } })
  await db.auditLog.create({ data: { userId: session.id, action: 'DELETE', module: 'overtime', details: JSON.stringify({ id }) } })
  return NextResponse.json({ success: true })
}
