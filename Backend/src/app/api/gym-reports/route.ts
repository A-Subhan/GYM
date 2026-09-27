import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const report = url.searchParams.get('report')
  const allowed = getSelectedBranchIds(session, url.searchParams.get('branches'))
  const from = url.searchParams.get('from')
  const to = url.searchParams.get('to')
  const branchFilter = allowed ? { branchId: { in: allowed } } : {}

  if (!report) {
    return NextResponse.json({ reports: [
      { key: 'member-list', name: 'Member List' },
      { key: 'active-memberships', name: 'Active Memberships' },
      { key: 'expired-memberships', name: 'Expired Memberships' },
      { key: 'membership-expiry', name: 'Membership Expiry' },
      { key: 'membership-freeze', name: 'Membership Freeze' },
      { key: 'member-attendance', name: 'Member Attendance' },
      { key: 'daily-attendance', name: 'Daily Attendance' },
      { key: 'trainer-assigned-members', name: 'Trainer Assigned Members' },
      { key: 'trainer-workload', name: 'Trainer Workload' },
      { key: 'pt-sessions', name: 'Personal Training Sessions' },
      { key: 'workout-assignments', name: 'Workout Plan Assignments' },
      { key: 'diet-assignments', name: 'Diet Plan Assignments' },
      { key: 'fitness-assessment', name: 'Fitness Assessment' },
      { key: 'member-progress', name: 'Member Progress' },
      { key: 'class-schedule', name: 'Class Schedule' },
      { key: 'branch-wise-members', name: 'Branch Wise Members' },
      { key: 'branch-wise-attendance', name: 'Branch Wise Attendance' },
    ]})
  }

  if (report === 'member-list') {
    const members = await db.member.findMany({
      where: { isDeleted: false, ...branchFilter },
      include: { branch: true, membershipPlan: true },
      orderBy: { createdAt: 'desc' }
    })
    return NextResponse.json({ report: { title: 'Member List', rows: members } })
  }

  if (report === 'active-memberships') {
    const members = await db.member.findMany({
      where: { isDeleted: false, status: 'Active', ...branchFilter },
      include: { branch: true, membershipPlan: true },
    })
    return NextResponse.json({ report: { title: 'Active Memberships', rows: members } })
  }

  if (report === 'trainer-assigned-members') {
    const members = await db.member.findMany({
      where: { isDeleted: false, assignedTrainerId: { not: null }, ...branchFilter },
      include: { branch: true, membershipPlan: true },
    })
    const trainers = await db.staff.findMany({ where: { isTrainer: true } })
    const trainerMap = new Map(trainers.map(t => [t.id, t]))
    const rows = members.map(m => ({
      memberId: m.memberId,
      memberName: `${m.firstName} ${m.lastName || ''}`,
      branch: m.branch?.name,
      trainer: trainerMap.get(m.assignedTrainerId || '') ? `${trainerMap.get(m.assignedTrainerId!)?.firstName} ${trainerMap.get(m.assignedTrainerId!)?.lastName || ''}` : '—',
      membership: m.membershipPlan?.name || '—',
      status: m.status,
      joiningDate: m.joiningDate,
    }))
    return NextResponse.json({ report: { title: 'Trainer Assigned Members', rows } })
  }

  if (report === 'trainer-workload') {
    const trainers = await db.staff.findMany({ where: { isTrainer: true, ...branchFilter } })
    const members = await db.member.findMany({ where: { assignedTrainerId: { not: null } } })
    const rows = trainers.map(t => ({
      trainerName: `${t.firstName} ${t.lastName || ''}`,
      employeeId: t.employeeId,
      assignedCount: members.filter(m => m.assignedTrainerId === t.id).length,
    }))
    return NextResponse.json({ report: { title: 'Trainer Workload', rows } })
  }

  if (report === 'pt-sessions') {
    const records = await db.personalTrainingSession.findMany({
      include: { member: true },
      orderBy: { createdAt: 'desc' }
    })
    return NextResponse.json({ report: { title: 'Personal Training Sessions', rows: records } })
  }

  if (report === 'class-schedule') {
    const classes = await db.gymClass.findMany({
      where: branchFilter,
      include: { branch: true, enrollments: { include: { member: true } } },
      orderBy: { dayOfWeek: 'asc' }
    })
    return NextResponse.json({ report: { title: 'Class Schedule', rows: classes } })
  }

  if (report === 'branch-wise-members') {
    const branches = await db.branch.findMany({ where: { isDeleted: false } })
    const counts = await Promise.all(branches.map(async b => {
      const count = await db.member.count({ where: { branchId: b.id, isDeleted: false } })
      return { branch: b.name, code: b.code, memberCount: count }
    }))
    return NextResponse.json({ report: { title: 'Branch Wise Members', rows: counts } })
  }

  // Default: return empty
  return NextResponse.json({ report: { title: 'Report not implemented', rows: [] } })
}
