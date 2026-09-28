import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const url = new URL(req.url)
  const allowed = getSelectedBranchIds(session, url.searchParams.get('branches'))

  const todayStart = new Date(new Date().setHours(0, 0, 0, 0))
  const monthStart = new Date(new Date().getFullYear(), new Date().getMonth(), 1)

  // Real stats from DB
  const [members, activeMembers, todayAttendance, unpaidFees, prospects, postedVouchers, todayRevenue, branches, staff] = await Promise.all([
    db.member.count({ where: { isDeleted: false, ...(allowed ? { branchId: { in: allowed } } : {}) } }),
    db.member.count({ where: { isDeleted: false, isActive: true, status: 'Active', ...(allowed ? { branchId: { in: allowed } } : {}) } }),
    db.attendance.count({ where: { date: { gte: todayStart }, ...(allowed ? { branchId: { in: allowed } } : {}) } }),
    db.fee.aggregate({ where: { status: { in: ['Unpaid', 'Late', 'Overdue', 'Partial'] }, ...(allowed ? { branchId: { in: allowed } } : {}) }, _sum: { balance: true } }),
    db.prospect.count({ where: { status: { not: 'Converted' } } }),
    // Posted book vouchers across all four dedicated stores
    Promise.all([
      db.cashbookVoucher.count({ where: { status: 'Posted', ...(allowed ? { branchId: { in: allowed } } : {}) } }),
      db.bankbookVoucher.count({ where: { status: 'Posted', ...(allowed ? { branchId: { in: allowed } } : {}) } }),
      db.journalVoucher.count({ where: { status: 'Posted', ...(allowed ? { branchId: { in: allowed } } : {}) } }),
      db.openTbVoucher.count({ where: { status: 'Posted', ...(allowed ? { branchId: { in: allowed } } : {}) } }),
    ]).then(([c, b, j, o]) => c + b + j + o),
    db.fee.aggregate({
      where: { paymentDate: { gte: todayStart }, ...(allowed ? { branchId: { in: allowed } } : {}) },
      _sum: { paidAmount: true },
    }),
    db.branch.count({ where: { isDeleted: false, ...(allowed ? { id: { in: allowed } } : {}) } }),
    db.staff.count({ where: { isDeleted: false, isActive: true, ...(allowed ? { branchId: { in: allowed } } : {}) } }),
  ])

  // Cash + bank movement today from the dedicated book stores (Posted only)
  const branchFilter = allowed ? { branchId: { in: allowed } } : {}
  const [cashIn, cashOut, bankIn, bankOut, monthlyFeeCollection, recentActivity] = await Promise.all([
    db.cashbookVoucher.aggregate({ where: { status: 'Posted', voucherType: 'CRV', voucherDate: { gte: todayStart }, ...branchFilter }, _sum: { totalAmount: true } }),
    db.cashbookVoucher.aggregate({ where: { status: 'Posted', voucherType: 'CPV', voucherDate: { gte: todayStart }, ...branchFilter }, _sum: { totalAmount: true } }),
    db.bankbookVoucher.aggregate({ where: { status: 'Posted', voucherType: 'BRV', voucherDate: { gte: todayStart }, ...branchFilter }, _sum: { totalAmount: true } }),
    db.bankbookVoucher.aggregate({ where: { status: 'Posted', voucherType: 'BPV', voucherDate: { gte: todayStart }, ...branchFilter }, _sum: { totalAmount: true } }),
    db.fee.aggregate({ where: { paymentDate: { gte: monthStart }, ...(allowed ? { branchId: { in: allowed } } : {}) }, _sum: { paidAmount: true } }),
    db.auditLog.findMany({ orderBy: { createdAt: 'desc' }, take: 8, include: { user: { select: { fullName: true } } } }),
  ])

  // Due/Grace alerts: fees with dueDate <= today + member's relaxation days
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  const overdueFeesRaw = await db.fee.findMany({
    where: {
      status: { in: ['Unpaid', 'Partial'] },
      ...(allowed ? { branchId: { in: allowed } } : {}),
    },
    include: { member: { include: { followUps: { orderBy: { nextFollowUpDate: 'asc' }, take: 1 } } } },
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
      drafts: 0, // book vouchers are posted directly (no draft state)
      postedVouchers,
      todayRevenue: todayRevenue._sum.paidAmount || 0,
      cashToday: (cashIn._sum.totalAmount || 0) - (cashOut._sum.totalAmount || 0),
      bankToday: (bankIn._sum.totalAmount || 0) - (bankOut._sum.totalAmount || 0),
      monthlyFeeCollection: monthlyFeeCollection._sum.paidAmount || 0,
      branches,
      staff,
    },
    recentActivity: recentActivity.map(a => ({
      id: a.id,
      action: a.action,
      module: a.module,
      user: a.user?.fullName || 'System',
      createdAt: a.createdAt,
    })),
    dueAlerts,
  })
}
