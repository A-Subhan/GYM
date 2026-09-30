import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'

// Calendar day types that must NEVER reduce anyone's salary
// (HR requirement: marked holidays are paid, no deduction in payroll).
const PAID_DAY_TYPES = ['Sunday', 'PaidHoliday', 'PublicHoliday', 'GymClosed', 'Off']

/** Is `date` a non-working (paid holiday) day per the Calendar screen? */
function isPaidHoliday(date: Date, holidaySet: Set<string>): boolean {
  const key = new Date(date.getTime() - date.getTimezoneOffset() * 60000).toISOString().slice(0, 10)
  if (holidaySet.has(key)) return true
  return date.getDay() === 0 // Sundays are off even without a Calendar row
}

/** Working days inside a leave range after excluding Sundays + marked paid holidays. */
function chargeableLeaveDays(from: Date, to: Date, holidaySet: Set<string>): number {
  let days = 0
  const cur = new Date(from.getTime())
  cur.setHours(0, 0, 0, 0)
  const end = new Date(to.getTime())
  end.setHours(0, 0, 0, 0)
  let guard = 0
  while (cur <= end && guard++ < 400) {
    if (!isPaidHoliday(cur, holidaySet)) days++
    cur.setDate(cur.getDate() + 1)
  }
  return days
}

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const allowed = getSelectedBranchIds(session, url.searchParams.get('branches'))
  const status = url.searchParams.get('status')
  const month = url.searchParams.get('month')
  const year = url.searchParams.get('year')
  const records = await db.payroll.findMany({
    where: {
      ...(status ? { status } : {}),
      ...(month ? { month: Number(month) } : {}),
      ...(year ? { year: Number(year) } : {}),
      ...(allowed ? { branchId: { in: allowed } } : {}),
    },
    include: { staff: true, branch: true },
    orderBy: [{ year: 'desc' }, { month: 'desc' }, { payrollNo: 'asc' }],
    take: 400,
  })
  return NextResponse.json({ records })
}

/**
 * Generate a payroll run for one staff member (or ALL active staff when
 * staffId = 'all') for a month/year.
 *
 * Calculation:
 *   basic        = staff.basicSalary
 *   allowances   = fuel + rent + house + other
 *   overtime     = SUM of APPROVED overtime rows that fall in the month
 *   unpaid leave = APPROVED unpaid-leave days in the month, EXCLUDING
 *                  Sundays and Calendar marked holidays (paid — no
 *                  deduction), prorated at basicSalary / 30
 *   deductions   = prorated unpaid days + SESSI + EOBI
 *   netPay       = basic + allowances + overtime − deductions
 */
export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('payroll.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const { staffId, month, year } = await req.json()
  if (!staffId || !month || !year) return NextResponse.json({ error: 'staffId, month, year required' }, { status: 400 })

  const m = Number(month)
  const y = Number(year)
  if (!(m >= 1 && m <= 12)) return NextResponse.json({ error: 'Invalid month' }, { status: 400 })

  const monthStart = new Date(y, m - 1, 1)
  const monthEnd = new Date(y, m, 0, 23, 59, 59)

  // Paid holidays from the Calendar screen (marked days are salary-neutral)
  const calendarDays = await db.calendarDay.findMany({
    where: { date: { gte: monthStart, lte: monthEnd }, dayType: { in: PAID_DAY_TYPES } },
    select: { date: true, dayType: true },
  })
  const holidaySet = new Set<string>(
    calendarDays.map((c) => new Date(c.date.getTime() - c.date.getTimezoneOffset() * 60000).toISOString().slice(0, 10)),
  )

  // Target staff: one member or all active, non-deleted staff
  const targets = staffId === 'all'
    ? await db.staff.findMany({
        where: { isDeleted: false, isActive: true, ...(session.accessibleBranchIds !== '*' ? { branchId: { in: session.accessibleBranchIds.split(',') } } : {}) },
        orderBy: { id: 'asc' },
      })
    : await db.staff.findMany({ where: { id: staffId, isDeleted: false } })
  if (!targets.length) return NextResponse.json({ error: 'Staff not found' }, { status: 404 })

  const created: any[] = []
  const skipped: Array<{ staffId: string; reason: string }> = []

  for (const staff of targets) {
    const existing = await db.payroll.findUnique({ where: { staffId_month_year: { staffId: staff.id, month: m, year: y } } })
    if (existing) {
      skipped.push({ staffId: staff.id, reason: 'Payroll already exists for this period' })
      continue
    }

    const basicSalary = staff.basicSalary
    const totalAllowances = staff.fuelAllowance + staff.rentAllowance + staff.houseAllowance + staff.otherAllowance

    // Approved overtime for the month
    const overtimeRecords = await db.overtime.findMany({
      where: { staffId: staff.id, status: 'Approved', date: { gte: monthStart, lte: monthEnd } },
    })
    const overtimeAmount = overtimeRecords.reduce((s, o) => s + o.amount, 0)

      // Approved UNPAID leave days → deduction, but Sundays and Calendar
      // marked holidays are paid and never deducted.
      // A leave type is unpaid when its master row says so (extra.isPaid === false)
      // or its name contains "unpaid" (legacy behaviour).
      const unpaidTypeNames = new Set<string>()
      const tryParse = (s: string | null | undefined): any => { try { return s ? JSON.parse(s) : null } catch { return null } }
      const [pmCategory, legacyTypes] = await Promise.all([
        db.payrollMaster.findFirst({ where: { name: 'Leave Type' } }),
        db.payrollMasterFile.findMany({ where: { masterType: 'Leave Type' } }),
      ])
      for (const t of legacyTypes) {
        const extra = tryParse(t.extra)
        if (extra?.isPaid === false || /unpaid/i.test(t.name)) unpaidTypeNames.add(t.name.toLowerCase())
      }
      if (pmCategory) {
        const details = await db.payrollMasterDetail.findMany({ where: { masterId: pmCategory.id } })
        for (const d of details) {
          if (/unpaid/i.test(d.name)) unpaidTypeNames.add(d.name.toLowerCase())
        }
      }
      const leaves = await db.leave.findMany({
        where: {
          staffId: staff.id,
          status: 'Approved',
          fromDate: { lte: monthEnd },
          toDate: { gte: monthStart },
        },
      })
      let unpaidDays = 0
      for (const l of leaves) {
        const isUnpaid = unpaidTypeNames.has(String(l.leaveType).toLowerCase())
        if (!isUnpaid) continue
        const from = l.fromDate < monthStart ? monthStart : l.fromDate
        const to = l.toDate > monthEnd ? monthEnd : l.toDate
        unpaidDays += chargeableLeaveDays(from, to, holidaySet)
      }
    const dailyRate = basicSalary / 30
    const unpaidDeduction = unpaidDays * dailyRate
    const totalDeductions = unpaidDeduction + staff.sessi + staff.eobi

    const totalEarnings = basicSalary + totalAllowances + overtimeAmount
    const netPay = totalEarnings - totalDeductions

    const payrollNo = `PAY-${y}-${String(m).padStart(2, '0')}-${staff.id}`

    try {
      const payroll = await db.payroll.create({
        data: {
          payrollNo,
          staffId: staff.id,
          branchId: staff.branchId,
          month: m,
          year: y,
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
      created.push(payroll)
    } catch (e: any) {
      if (e?.code === 'P2002') {
        skipped.push({ staffId: staff.id, reason: 'Payroll already exists for this period' })
        continue
      }
      throw e
    }
  }

  await db.auditLog.create({
    data: { userId: session.id, action: 'CREATE', module: 'payroll', details: JSON.stringify({ month: m, year: y, created: created.length, skipped: skipped.length }) },
  })
  return NextResponse.json({ payroll: created[0] || null, created, createdCount: created.length, skipped })
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const { id, action } = await req.json()
  if (!id) return NextResponse.json({ error: 'id required' }, { status: 400 })
  if (action === 'approve') {
    if (!session.permissions.includes('payroll.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    const existing = await db.payroll.findUnique({ where: { id } })
    if (!existing) return NextResponse.json({ error: 'Payroll not found' }, { status: 404 })
    if (existing.status !== 'Draft') return NextResponse.json({ error: `Only draft payroll can be approved (current: ${existing.status})` }, { status: 400 })
    const payroll = await db.payroll.update({ where: { id }, data: { status: 'Approved' } })
    await db.auditLog.create({ data: { userId: session.id, action: 'APPROVE', module: 'payroll', details: JSON.stringify({ id }) } })
    return NextResponse.json({ payroll })
  }
  if (action === 'markPaid') {
    if (!session.permissions.includes('payroll.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    const existing = await db.payroll.findUnique({ where: { id } })
    if (!existing) return NextResponse.json({ error: 'Payroll not found' }, { status: 404 })
    if (existing.status !== 'Approved') return NextResponse.json({ error: 'Only approved payroll can be marked paid' }, { status: 400 })
    const payroll = await db.payroll.update({ where: { id }, data: { status: 'Paid' } })
    await db.auditLog.create({ data: { userId: session.id, action: 'MARK_PAID', module: 'payroll', details: JSON.stringify({ id }) } })
    return NextResponse.json({ payroll })
  }
  return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
}

// DELETE — draft payroll runs only (approved/paid runs are kept for audit)
export async function DELETE(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('payroll.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const url = new URL(req.url)
  const id = url.searchParams.get('id')
  if (!id) return NextResponse.json({ error: 'id required' }, { status: 400 })
  const existing = await db.payroll.findUnique({ where: { id } })
  if (!existing) return NextResponse.json({ error: 'Payroll not found' }, { status: 404 })
  if (existing.status !== 'Draft') return NextResponse.json({ error: 'Only draft payroll runs can be deleted' }, { status: 400 })
  await db.payroll.delete({ where: { id } })
  await db.auditLog.create({ data: { userId: session.id, action: 'DELETE', module: 'payroll', details: JSON.stringify({ id, payrollNo: existing.payrollNo }) } })
  return NextResponse.json({ success: true, message: `Payroll ${existing.payrollNo} deleted` })
}
