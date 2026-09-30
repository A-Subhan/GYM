import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'

// Gym Reports — rebuilt on the surviving models only (GymClass / ClassEnrollment /
// FitnessAssessment / MemberDocument features were removed; those reports are gone).

const UNPAID_STATUSES = ['Unpaid', 'Partial', 'Late', 'Overdue']

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const report = url.searchParams.get('report')
  const allowed = getSelectedBranchIds(session, url.searchParams.get('branches'))
  const branchFilter = allowed ? { branchId: { in: allowed } } : {}
  const memberBase = { isDeleted: false, ...branchFilter }

  const now = new Date()
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1)
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate())

  if (!report) {
    return NextResponse.json({ reports: [
      { key: 'summary', name: 'Gym Summary' },
      { key: 'member-list', name: 'Member List' },
      { key: 'active-memberships', name: 'Active Memberships' },
      { key: 'expired-memberships', name: 'Expired Memberships' },
      { key: 'membership-expiry', name: 'Membership Expiry (next 30 days)' },
      { key: 'new-members', name: 'New Members This Month' },
      { key: 'membership-freeze', name: 'Membership Freeze' },
      { key: 'member-attendance', name: 'Member Attendance' },
      { key: 'daily-attendance', name: 'Daily Attendance (this month)' },
      { key: 'branch-wise-attendance', name: 'Branch Wise Attendance (this month)' },
      { key: 'trainer-assigned-members', name: 'Trainer Assigned Members' },
      { key: 'trainer-workload', name: 'Trainer Workload' },
      { key: 'pt-sessions', name: 'Personal Training Sessions' },
      { key: 'workout-assignments', name: 'Workout Plan Assignments' },
      { key: 'diet-assignments', name: 'Diet Plan Assignments' },
      { key: 'member-progress', name: 'Member Progress' },
      { key: 'revenue', name: 'Revenue (Fee Collections)' },
      { key: 'pending-fees', name: 'Pending Fees' },
      { key: 'branch-wise-members', name: 'Branch Wise Members' },
      { key: 'equipment', name: 'Equipment' },
    ]})
  }

  if (report === 'summary') {
    const [activeMembers, attendanceThisMonth, revenueThisMonth, pendingFees, newMembersThisMonth, ptSessions, equipmentCount] = await Promise.all([
      db.member.count({ where: { ...memberBase, status: 'Active', isActive: true } }),
      db.attendance.count({ where: { date: { gte: monthStart }, ...branchFilter } }),
      db.fee.aggregate({ where: { paymentDate: { gte: monthStart }, ...branchFilter }, _sum: { paidAmount: true } }),
      db.fee.aggregate({ where: { status: { in: UNPAID_STATUSES }, ...branchFilter }, _sum: { balance: true }, _count: true }),
      db.member.count({ where: { ...memberBase, joiningDate: { gte: monthStart } } }),
      db.personalTrainingSession.aggregate({
        where: { member: { isDeleted: false }, ...(allowed ? { branchId: { in: allowed } } : {}) },
        _count: true,
        _sum: { sessionsPurchased: true, sessionsUsed: true, sessionsRemaining: true },
      }),
      db.equipment.count({ where: branchFilter }),
    ])
    return NextResponse.json({ report: { title: 'Gym Summary', rows: [{
      activeMembers,
      attendanceThisMonth,
      revenueThisMonth: revenueThisMonth._sum.paidAmount || 0,
      pendingFeesBalance: pendingFees._sum.balance || 0,
      pendingFeesCount: pendingFees._count,
      newMembersThisMonth,
      ptSessionsCount: ptSessions._count,
      ptSessionsPurchased: ptSessions._sum.sessionsPurchased || 0,
      ptSessionsUsed: ptSessions._sum.sessionsUsed || 0,
      ptSessionsRemaining: ptSessions._sum.sessionsRemaining || 0,
      equipmentCount,
    }] } })
  }

  if (report === 'member-list') {
    const members = await db.member.findMany({
      where: memberBase,
      include: { branch: true, membershipPlan: true },
      orderBy: { createdAt: 'desc' }
    })
    const rows = members.map(m => ({
      memberId: m.id,
      name: `${m.firstName} ${m.lastName || ''}`,
      gender: m.gender || '—',
      phone: m.phone || '—',
      plan: m.membershipPlan?.name || '—',
      branch: m.branch?.name || '—',
      joiningDate: m.joiningDate,
      status: m.status,
    }))
    return NextResponse.json({ report: { title: 'Member List', rows } })
  }

  if (report === 'active-memberships') {
    const members = await db.member.findMany({
      where: { ...memberBase, status: 'Active', isActive: true },
      include: { branch: true, membershipPlan: true },
    })
    const rows = members.map(m => ({
      memberId: m.id,
      name: `${m.firstName} ${m.lastName || ''}`,
      plan: m.membershipPlan?.name || '—',
      branch: m.branch?.name || '—',
      joiningDate: m.joiningDate,
      billingStart: m.billingStartDate,
    }))
    return NextResponse.json({ report: { title: 'Active Memberships', rows } })
  }

  if (report === 'expired-memberships') {
    const members = await db.member.findMany({
      where: { ...memberBase, status: { in: ['Inactive', 'Cancelled', 'Suspended'] } },
      include: { branch: true, membershipPlan: true },
    })
    const rows = members.map(m => ({
      memberId: m.id,
      name: `${m.firstName} ${m.lastName || ''}`,
      plan: m.membershipPlan?.name || '—',
      branch: m.branch?.name || '—',
      joiningDate: m.joiningDate,
      status: m.status,
    }))
    return NextResponse.json({ report: { title: 'Expired Memberships', rows } })
  }

  if (report === 'membership-expiry') {
    const in30 = new Date(todayStart)
    in30.setDate(in30.getDate() + 30)
    const fees = await db.fee.findMany({
      where: { billingPeriodEnd: { gte: todayStart, lte: in30 }, ...branchFilter, member: { isDeleted: false } },
      include: { member: { include: { branch: true, membershipPlan: true } } },
      orderBy: { billingPeriodEnd: 'asc' },
      take: 300,
    })
    const rows = fees.map(f => ({
      feeNo: f.id,
      memberId: f.member.id,
      memberName: `${f.member.firstName} ${f.member.lastName || ''}`,
      plan: f.member.membershipPlan?.name || '—',
      branch: f.member.branch?.name || '—',
      periodEnd: f.billingPeriodEnd,
      balance: f.balance,
      status: f.status,
    }))
    return NextResponse.json({ report: { title: 'Membership Expiry (next 30 days)', rows } })
  }

  if (report === 'new-members') {
    const members = await db.member.findMany({
      where: { ...memberBase, joiningDate: { gte: monthStart } },
      include: { branch: true, membershipPlan: true },
      orderBy: { joiningDate: 'desc' },
    })
    const rows = members.map(m => ({
      memberId: m.id,
      name: `${m.firstName} ${m.lastName || ''}`,
      plan: m.membershipPlan?.name || '—',
      branch: m.branch?.name || '—',
      joiningDate: m.joiningDate,
      status: m.status,
    }))
    return NextResponse.json({ report: { title: 'New Members This Month', rows } })
  }

  if (report === 'membership-freeze') {
    const freezes = await db.membershipFreeze.findMany({
      where: branchFilter,
      include: { member: true, branch: true },
      orderBy: { createdAt: 'desc' },
      take: 300,
    })
    const rows = freezes.map(f => ({
      memberId: f.member.id,
      memberName: `${f.member.firstName} ${f.member.lastName || ''}`,
      branch: f.branch?.name || '—',
      freezeFrom: f.freezeFrom,
      freezeTo: f.freezeTo,
      days: f.days,
      reason: f.reason || '—',
      status: f.status,
    }))
    return NextResponse.json({ report: { title: 'Membership Freeze', rows } })
  }

  if (report === 'member-attendance') {
    const records = await db.attendance.findMany({
      where: { date: { gte: monthStart }, ...branchFilter },
      include: { member: true, branch: true },
      orderBy: { date: 'desc' },
      take: 500,
    })
    const rows = records.map(r => ({
      memberId: r.member.id,
      memberName: `${r.member.firstName} ${r.member.lastName || ''}`,
      branch: r.branch?.name || '—',
      date: r.date,
      checkIn: r.checkIn,
      checkOut: r.checkOut,
    }))
    return NextResponse.json({ report: { title: 'Member Attendance (this month)', rows } })
  }

  if (report === 'daily-attendance') {
    const records = await db.attendance.findMany({
      where: { date: { gte: monthStart }, ...branchFilter },
      select: { date: true },
    })
    const byDate = new Map<string, number>()
    for (const r of records) {
      const key = new Date(r.date).toISOString().slice(0, 10)
      byDate.set(key, (byDate.get(key) || 0) + 1)
    }
    const rows = Array.from(byDate.entries())
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([date, count]) => ({ date, checkIns: count }))
    return NextResponse.json({ report: { title: 'Daily Attendance (this month)', rows } })
  }

  if (report === 'branch-wise-attendance') {
    const branches = await db.branch.findMany({ where: { isDeleted: false, ...(allowed ? { id: { in: allowed } } : {}) } })
    const rows = await Promise.all(branches.map(async b => {
      const count = await db.attendance.count({ where: { branchId: b.id, date: { gte: monthStart } } })
      return { branch: b.name, code: b.code, checkInsThisMonth: count }
    }))
    return NextResponse.json({ report: { title: 'Branch Wise Attendance (this month)', rows } })
  }

  if (report === 'trainer-assigned-members') {
    const members = await db.member.findMany({
      where: { ...memberBase, assignedTrainerId: { not: null } },
      include: { branch: true, membershipPlan: true },
    })
    const trainers = await db.staff.findMany({ where: { isTrainer: true } })
    const trainerMap = new Map(trainers.map(t => [t.id, t]))
    const rows = members.map(m => {
      const t = trainerMap.get(m.assignedTrainerId || '')
      return {
        memberId: m.id,
        memberName: `${m.firstName} ${m.lastName || ''}`,
        branch: m.branch?.name || '—',
        trainer: t ? `${t.firstName} ${t.lastName || ''}` : '—',
        membership: m.membershipPlan?.name || '—',
        status: m.status,
        joiningDate: m.joiningDate,
      }
    })
    return NextResponse.json({ report: { title: 'Trainer Assigned Members', rows } })
  }

  if (report === 'trainer-workload') {
    const trainers = await db.staff.findMany({ where: { isTrainer: true, isDeleted: false } })
    const members = await db.member.findMany({ where: { isDeleted: false, assignedTrainerId: { not: null } } })
    const rows = trainers.map(t => ({
      trainerName: `${t.firstName} ${t.lastName || ''}`,
      employeeId: t.id,
      assignedCount: members.filter(m => m.assignedTrainerId === t.id).length,
    }))
    return NextResponse.json({ report: { title: 'Trainer Workload', rows } })
  }

  if (report === 'pt-sessions') {
    const records = await db.personalTrainingSession.findMany({
      where: { member: { isDeleted: false }, ...(allowed ? { branchId: { in: allowed } } : {}) },
      include: { member: true },
      orderBy: { createdAt: 'desc' },
      take: 300,
    })
    const trainers = await db.staff.findMany({ where: { isTrainer: true } })
    const trainerMap = new Map(trainers.map(t => [t.id, t]))
    const rows = records.map(r => {
      const t = trainerMap.get(r.trainerId)
      return {
        memberName: `${r.member.firstName} ${r.member.lastName || ''}`,
        memberId: r.member.id,
        trainer: t ? `${t.firstName} ${t.lastName || ''}` : '—',
        sessionsPurchased: r.sessionsPurchased,
        sessionsUsed: r.sessionsUsed,
        sessionsRemaining: r.sessionsRemaining,
        sessionDate: r.sessionDate,
        sessionStatus: r.sessionStatus,
        status: r.status,
      }
    })
    return NextResponse.json({ report: { title: 'Personal Training Sessions', rows } })
  }

  if (report === 'workout-assignments') {
    const records = await db.workoutAssignment.findMany({
      where: { member: { isDeleted: false } },
      include: { member: true, plan: true },
      orderBy: { createdAt: 'desc' },
      take: 300,
    })
    const rows = records.map(r => ({
      memberId: r.member.id,
      memberName: `${r.member.firstName} ${r.member.lastName || ''}`,
      plan: r.plan?.name || '—',
      startDate: r.startDate,
      endDate: r.endDate,
      notes: r.notes || '—',
    }))
    return NextResponse.json({ report: { title: 'Workout Plan Assignments', rows } })
  }

  if (report === 'diet-assignments') {
    const records = await db.dietAssignment.findMany({
      where: { member: { isDeleted: false } },
      include: { member: true, plan: true },
      orderBy: { createdAt: 'desc' },
      take: 300,
    })
    const rows = records.map(r => ({
      memberId: r.member.id,
      memberName: `${r.member.firstName} ${r.member.lastName || ''}`,
      plan: r.plan?.name || '—',
      startDate: r.startDate,
      endDate: r.endDate,
      notes: r.notes || '—',
    }))
    return NextResponse.json({ report: { title: 'Diet Plan Assignments', rows } })
  }

  if (report === 'member-progress') {
    const records = await db.progressEntry.findMany({
      where: { member: { isDeleted: false } },
      include: { member: true },
      orderBy: { date: 'desc' },
      take: 300,
    })
    const rows = records.map(r => ({
      memberId: r.member.id,
      memberName: `${r.member.firstName} ${r.member.lastName || ''}`,
      date: r.date,
      weight: r.weight,
      chest: r.chest,
      waist: r.waist,
      hips: r.hips,
      biceps: r.biceps,
      notes: r.notes || '—',
    }))
    return NextResponse.json({ report: { title: 'Member Progress', rows } })
  }

  if (report === 'revenue') {
    const fees = await db.fee.findMany({
      where: { paidAmount: { gt: 0 }, ...branchFilter, member: { isDeleted: false } },
      include: { member: true, branch: true },
      orderBy: { paymentDate: 'desc' },
      take: 500,
    })
    const rows = fees.map(f => ({
      feeNo: f.id,
      memberId: f.member.id,
      memberName: `${f.member.firstName} ${f.member.lastName || ''}`,
      branch: f.branch?.name || '—',
      amount: f.amount,
      discount: f.discount,
      paidAmount: f.paidAmount,
      balance: f.balance,
      status: f.status,
      paymentMethod: f.paymentMethod || '—',
      paymentDate: f.paymentDate,
    }))
    return NextResponse.json({ report: { title: 'Revenue (Fee Collections)', rows } })
  }

  if (report === 'pending-fees') {
    const fees = await db.fee.findMany({
      where: { status: { in: UNPAID_STATUSES }, ...branchFilter, member: { isDeleted: false } },
      include: { member: true, branch: true },
      orderBy: { dueDate: 'asc' },
      take: 500,
    })
    const rows = fees.map(f => ({
      feeNo: f.id,
      memberId: f.member.id,
      memberName: `${f.member.firstName} ${f.member.lastName || ''}`,
      branch: f.branch?.name || '—',
      amount: f.amount,
      paidAmount: f.paidAmount,
      balance: f.balance,
      dueDate: f.dueDate,
      status: f.status,
    }))
    return NextResponse.json({ report: { title: 'Pending Fees', rows } })
  }

  if (report === 'branch-wise-members') {
    const branches = await db.branch.findMany({ where: { isDeleted: false, ...(allowed ? { id: { in: allowed } } : {}) } })
    const counts = await Promise.all(branches.map(async b => {
      const count = await db.member.count({ where: { branchId: b.id, isDeleted: false } })
      return { branch: b.name, code: b.code, memberCount: count }
    }))
    return NextResponse.json({ report: { title: 'Branch Wise Members', rows: counts } })
  }

  if (report === 'equipment') {
    const equipment = await db.equipment.findMany({
      where: branchFilter,
      include: { branch: true },
      orderBy: { createdAt: 'desc' },
      take: 500,
    })
    const rows = equipment.map(e => ({
      code: e.code,
      name: e.name,
      category: e.category,
      branch: e.branch?.name || '—',
      quantity: e.quantity,
      purchasePrice: e.purchasePrice,
      condition: e.condition,
      status: e.status,
    }))
    return NextResponse.json({ report: { title: 'Equipment', rows } })
  }

  // Default: return empty
  return NextResponse.json({ report: { title: 'Report not implemented', rows: [] } })
}
