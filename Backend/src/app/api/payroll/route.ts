import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const allowed = getSelectedBranchIds(session, url.searchParams.get('branches'))
  const status = url.searchParams.get('status')
  const records = await db.payroll.findMany({
    where: { ...(status ? { status } : {}), ...(allowed ? { branchId: { in: allowed } } : {}) },
    include: { staff: true, branch: true },
    orderBy: { createdAt: 'desc' },
    take: 200,
  })
  return NextResponse.json({ records })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('payroll.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const { staffId, month, year } = await req.json()
  if (!staffId || !month || !year) return NextResponse.json({ error: 'staffId, month, year required' }, { status: 400 })

  const staff = await db.staff.findUnique({ where: { id: staffId } })
  if (!staff) return NextResponse.json({ error: 'Staff not found' }, { status: 404 })

  // Check duplicate
  const existing = await db.payroll.findUnique({ where: { staffId_month_year: { staffId, month: Number(month), year: Number(year) } } })
  if (existing) return NextResponse.json({ error: 'Payroll already exists for this period', payroll: existing }, { status: 400 })

  // Calculate
  const basicSalary = staff.basicSalary
  const totalAllowances = staff.fuelAllowance + staff.rentAllowance + staff.houseAllowance + staff.otherAllowance
  // Approved overtime for the month
  const overtimeRecords = await db.overtime.findMany({ where: { staffId, status: 'Approved', date: { gte: new Date(Number(year), Number(month) - 1, 1), lte: new Date(Number(year), Number(month), 0, 23, 59, 59) } } })
  const overtimeAmount = overtimeRecords.reduce((s, o) => s + o.amount, 0)
  // Approved unpaid leaves → deduction
  const leaves = await db.leave.findMany({ where: { staffId, status: 'Approved', leaveType: 'Unpaid', fromDate: { gte: new Date(Number(year), Number(month) - 1, 1) }, toDate: { lte: new Date(Number(year), Number(month), 0, 23, 59, 59) } } })
  const unpaidDays = leaves.reduce((s, l) => s + l.days, 0)
  const dailyRate = basicSalary / 30
  const totalDeductions = unpaidDays * dailyRate + staff.sessi + staff.eobi

  const totalEarnings = basicSalary + totalAllowances + overtimeAmount
  const netPay = totalEarnings - totalDeductions

  const payrollNo = `PAY-${year}-${String(month).padStart(2, '0')}-${staff.employeeId}`

  const payroll = await db.payroll.create({
    data: {
      payrollNo,
      staffId,
      branchId: staff.branchId,
      month: Number(month),
      year: Number(year),
      basicSalary,
      totalAllowances,
      overtimeAmount,
      totalEarnings,
      totalDeductions,
      netPay,
      status: 'Draft',
    },
    include: { staff: true },
  })
  await db.auditLog.create({ data: { userId: session.id, action: 'CREATE', module: 'payroll', details: JSON.stringify({ id: payroll.id, payrollNo }) } })
  return NextResponse.json({ payroll })
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const { id, action } = await req.json()
  if (action === 'approve') {
    const payroll = await db.payroll.update({ where: { id }, data: { status: 'Approved' } })
    await db.auditLog.create({ data: { userId: session.id, action: 'APPROVE', module: 'payroll', details: JSON.stringify({ id }) } })
    return NextResponse.json({ payroll })
  }
  return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
}
