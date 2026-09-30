import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

const STAFF_SELECT = { select: { id: true, firstName: true, lastName: true, employeeId: true } }
const BRANCH_SELECT = { select: { id: true, name: true, code: true } }

async function loadLeave(id: string) {
  return db.leave.findUnique({
    where: { id },
    include: { staff: STAFF_SELECT, branch: BRANCH_SELECT },
  })
}

export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const { id } = await params
  const leave = await loadLeave(id)
  if (!leave) return NextResponse.json({ error: 'Leave not found' }, { status: 404 })
  return NextResponse.json({ leave })
}

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const { id } = await params
  const data = await req.json()

  const leave = await loadLeave(id)
  if (!leave) return NextResponse.json({ error: 'Leave not found' }, { status: 404 })

  // --- Approve / Reject ---------------------------------------------------
  if (data.status) {
    if (!['Approved', 'Rejected'].includes(data.status)) {
      return NextResponse.json({ error: 'Invalid status' }, { status: 400 })
    }
    if (!session.permissions.includes('leaves.approve')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    if (leave.status !== 'Pending') {
      return NextResponse.json({ error: `Leave is already ${leave.status}` }, { status: 400 })
    }
    const updated = await db.leave.update({
      where: { id },
      data: {
        status: data.status,
        approvedBy: session.id,
        approvedAt: new Date(),
        reason: data.reason !== undefined ? data.reason : undefined,
      },
      include: { staff: STAFF_SELECT, branch: BRANCH_SELECT },
    })
    await db.auditLog.create({
      data: { userId: session.id, action: data.status.toUpperCase(), module: 'leaves', details: JSON.stringify({ id, leaveNo: leave.id }) },
    })
    return NextResponse.json({ leave: updated })
  }

  // --- Edit while Pending ---------------------------------------------------
  if (leave.status !== 'Pending') {
    return NextResponse.json({ error: 'Only pending leaves can be edited' }, { status: 400 })
  }
  if (!session.permissions.includes('leaves.edit') && !session.permissions.includes('leaves.approve')) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  }

  const updateData: Record<string, unknown> = {}

  if (data.staffId && data.staffId !== leave.staffId) {
    const staff = await db.staff.findUnique({ where: { id: data.staffId } })
    if (!staff || staff.isDeleted) return NextResponse.json({ error: 'Staff not found' }, { status: 404 })
    updateData.staffId = staff.id
  }

  if (data.leaveType && data.leaveType !== leave.leaveType) {
    // Payroll Master File first (payrollmaster category 'Leave Type'), then legacy table
    let leaveType: { name: string } | null = null
    const pmCategory = await db.payrollMaster.findFirst({ where: { name: 'Leave Type' } })
    if (pmCategory) {
      leaveType = await db.payrollMasterDetail.findFirst({
        where: { masterId: pmCategory.id, name: data.leaveType, isActive: true },
      })
    }
    if (!leaveType) {
      leaveType = await db.payrollMasterFile.findFirst({
        where: { masterType: 'Leave Type', name: data.leaveType, isActive: true },
      })
    }
    if (!leaveType) {
      return NextResponse.json({ error: `Invalid leave type "${data.leaveType}" — pick one from the HR Leave Type master` }, { status: 400 })
    }
    updateData.leaveType = leaveType.name
  }

  const from = data.fromDate ? new Date(data.fromDate) : leave.fromDate
  const to = data.toDate ? new Date(data.toDate) : leave.toDate
  if (isNaN(from.getTime()) || isNaN(to.getTime())) {
    return NextResponse.json({ error: 'Invalid fromDate or toDate' }, { status: 400 })
  }
  if (to < from) return NextResponse.json({ error: 'toDate must be on or after fromDate' }, { status: 400 })
  if (data.fromDate || data.toDate) {
    updateData.fromDate = from
    updateData.toDate = to
    updateData.days = Math.ceil((to.getTime() - from.getTime()) / (24 * 60 * 60 * 1000)) + 1
  }

  if (data.reason !== undefined) updateData.reason = data.reason

  const updated = await db.leave.update({
    where: { id },
    data: updateData,
    include: { staff: STAFF_SELECT, branch: BRANCH_SELECT },
  })
  await db.auditLog.create({
    data: { userId: session.id, action: 'UPDATE', module: 'leaves', details: JSON.stringify({ id, leaveNo: leave.id }) },
  })
  return NextResponse.json({ leave: updated })
}
