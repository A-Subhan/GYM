import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { makeLeaveId } from '@/lib/ids'

// Staff fields included on every leave row
const STAFF_SELECT = { select: { id: true, firstName: true, lastName: true, employeeId: true } }

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const status = url.searchParams.get('status')
  const staffId = url.searchParams.get('staffId')
  const branchId = url.searchParams.get('branchId')

  const leaves = await db.leave.findMany({
    where: {
      ...(status ? { status } : {}),
      ...(staffId ? { staffId } : {}),
      ...(branchId ? { branchId } : {}),
      // never show leaves of soft-deleted staff
      staff: { isDeleted: false },
    },
    include: { staff: STAFF_SELECT, branch: { select: { id: true, name: true, code: true } } },
    orderBy: { createdAt: 'desc' },
    take: 200,
  })
  return NextResponse.json({ leaves })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('leaves.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.staffId || !data.leaveType || !data.fromDate || !data.toDate) {
    return NextResponse.json({ error: 'staffId, leaveType, fromDate, toDate required' }, { status: 400 })
  }

  // Staff must exist and not be soft-deleted
  const staff = await db.staff.findUnique({ where: { id: data.staffId } })
  if (!staff || staff.isDeleted) return NextResponse.json({ error: 'Staff not found' }, { status: 404 })

  const from = new Date(data.fromDate)
  const to = new Date(data.toDate)
  if (isNaN(from.getTime()) || isNaN(to.getTime())) {
    return NextResponse.json({ error: 'Invalid fromDate or toDate' }, { status: 400 })
  }
  if (to < from) return NextResponse.json({ error: 'toDate must be on or after fromDate' }, { status: 400 })
  const days = Math.ceil((to.getTime() - from.getTime()) / (24 * 60 * 60 * 1000)) + 1

  // Leave types now live in universal MasterFile (masterType='LeaveType')
  const leaveType = await db.masterFile.findFirst({
    where: { masterType: 'LeaveType', name: data.leaveType, isActive: true },
  })
  if (!leaveType) {
    return NextResponse.json({ error: `Invalid leave type "${data.leaveType}" — pick one from Leave Type master` }, { status: 400 })
  }

  // Branch: explicit body branchId wins, otherwise the staff member's branch
  const branchId = (data.branchId as string) || staff.branchId

  const leaveNo = await makeLeaveId()
  const leave = await db.leave.create({
    data: {
      leaveNo,
      staffId: staff.id,
      branchId,
      leaveType: leaveType.name,
      fromDate: from,
      toDate: to,
      days,
      reason: data.reason,
      status: 'Pending',
    },
    include: { staff: STAFF_SELECT, branch: { select: { id: true, name: true, code: true } } },
  })
  await db.auditLog.create({
    data: { userId: session.id, action: 'CREATE', module: 'leaves', details: JSON.stringify({ id: leave.id, leaveNo }) },
  })
  return NextResponse.json({ leave })
}
