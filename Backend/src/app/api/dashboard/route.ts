import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const url = new URL(req.url)
  const allowed = getSelectedBranchIds(session, url.searchParams.get('branches'))

  // Real stats from DB
  const [members, activeMembers, todayAttendance, unpaidFees, prospects, drafts, postedVouchers, todayRevenue, branches, staff] = await Promise.all([
    db.member.count({ where: { isDeleted: false, ...(allowed ? { branchId: { in: allowed } } : {}) } }),
    db.member.count({ where: { isDeleted: false, isActive: true, status: 'Active', ...(allowed ? { branchId: { in: allowed } } : {}) } }),
    db.attendance.count({ where: { date: { gte: new Date(new Date().setHours(0, 0, 0, 0)) }, ...(allowed ? { branchId: { in: allowed } } : {}) } }),
    db.fee.aggregate({ where: { status: { in: ['Unpaid', 'Late', 'Overdue', 'Partial'] }, ...(allowed ? { branchId: { in: allowed } } : {}) }, _sum: { balance: true } }),
    db.prospect.count({ where: { status: { not: 'Converted' } } }),
    db.voucher.count({ where: { status: 'Draft', ...(allowed ? { branchId: { in: allowed } } : {}) } }),
    db.voucher.count({ where: { status: 'Posted', ...(allowed ? { branchId: { in: allowed } } : {}) } }),
    db.fee.aggregate({
      where: { paymentDate: { gte: new Date(new Date().setHours(0, 0, 0, 0)) }, ...(allowed ? { branchId: { in: allowed } } : {}) },
      _sum: { paidAmount: true },
    }),
    db.branch.count({ where: { isDeleted: false, ...(allowed ? { id: { in: allowed } } : {}) } }),
    db.staff.count({ where: { isDeleted: false, isActive: true, ...(allowed ? { branchId: { in: allowed } } : {}) } }),
  ])

  // Due/Grace alerts: fees with dueDate <= today + member's relaxation days
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  const overdueFeesRaw = await db.fee.findMany({
    where: {
      status: { in: ['Unpaid', 'Partial'] },
      ...(allowed ? { branchId: { in: allowed } } : {}),
    },
    include: { member: true },
    take: 100,
  })
  const dueAlerts = overdueFeesRaw.map(f => {
    const dueDate = new Date(f.dueDate)
    const graceEnd = new Date(dueDate.getTime() + (f.member.feeRelaxationDays || 0) * 24 * 60 * 60 * 1000)
    const daysPastDue = Math.floor((today.getTime() - dueDate.getTime()) / (24 * 60 * 60 * 1000))
    const graceLeft = Math.floor((graceEnd.getTime() - today.getTime()) / (24 * 60 * 60 * 1000))
    let alertStatus = 'Not Due'
    if (daysPastDue < 0) alertStatus = 'Upcoming'
    else if (daysPastDue === 0) alertStatus = 'Due Today'
    else if (graceLeft >= 0) alertStatus = `Grace Day ${daysPastDue}`
    else alertStatus = 'Overdue'
    return {
      feeId: f.id,
      feeNo: f.feeNo,
      memberName: `${f.member.firstName} ${f.member.lastName || ''}`,
      phone: f.member.phone,
      dueDate: f.dueDate,
      amount: f.amount,
      balance: f.balance,
      graceDays: f.member.feeRelaxationDays,
      alertStatus,
      nextFollowUp: f.member.followUps?.[0]?.nextFollowUpDate,
    }
  }).filter(a => a.alertStatus !== 'Not Due' && a.alertStatus !== 'Upcoming').slice(0, 20)

  return NextResponse.json({
    stats: {
      members,
      activeMembers,
      todayAttendance,
      unpaidFeesBalance: unpaidFees._sum.balance || 0,
      prospects,
      drafts,
      postedVouchers,
      todayRevenue: todayRevenue._sum.paidAmount || 0,
      branches,
      staff,
    },
    dueAlerts,
  })
}
