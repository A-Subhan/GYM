import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const report = url.searchParams.get('report')
  const allowed = getSelectedBranchIds(session, url.searchParams.get('branches'))
  const branchFilter = allowed ? { branchId: { in: allowed } } : {}

  if (!report) {
    return NextResponse.json({ reports: [
      { key: 'staff-list', name: 'Staff List' },
      { key: 'trainer-list', name: 'Trainer List' },
      { key: 'payroll-register', name: 'Payroll Register' },
      { key: 'salary-report', name: 'Salary Report' },
      { key: 'overtime-report', name: 'Overtime Report' },
      { key: 'trainer-incentive', name: 'Trainer Incentive Report' },
      { key: 'leave-report', name: 'Leave Report' },
      { key: 'branch-wise-staff', name: 'Branch Wise Staff' },
    ]})
  }

  if (report === 'staff-list') {
    const staff = await db.staff.findMany({
      where: { isDeleted: false, ...branchFilter },
      include: { branch: true, shift: true },
      orderBy: { createdAt: 'desc' }
    })
    return NextResponse.json({ report: { title: 'Staff List', rows: staff } })
  }

  if (report === 'trainer-list') {
    const trainers = await db.staff.findMany({
      where: { isTrainer: true, isDeleted: false, ...branchFilter },
      include: { branch: true },
      orderBy: { firstName: 'asc' }
    })
    return NextResponse.json({ report: { title: 'Trainer List', rows: trainers } })
  }

  if (report === 'payroll-register') {
    const records = await db.payroll.findMany({
      where: branchFilter,
      include: { staff: true, branch: true },
      orderBy: { createdAt: 'desc' }
    })
    return NextResponse.json({ report: { title: 'Payroll Register', rows: records } })
  }

  if (report === 'overtime-report') {
    const records = await db.overtime.findMany({
      where: { status: 'Approved', ...branchFilter },
      include: { staff: true },
      orderBy: { date: 'desc' }
    })
    return NextResponse.json({ report: { title: 'Overtime Report', rows: records } })
  }

  if (report === 'leave-report') {
    const records = await db.leave.findMany({
      include: { staff: true },
      orderBy: { createdAt: 'desc' }
    })
    return NextResponse.json({ report: { title: 'Leave Report', rows: records } })
  }

  if (report === 'branch-wise-staff') {
    const branches = await db.branch.findMany({ where: { isDeleted: false } })
    const counts = await Promise.all(branches.map(async b => {
      const total = await db.staff.count({ where: { branchId: b.id, isDeleted: false } })
      const trainers = await db.staff.count({ where: { branchId: b.id, isTrainer: true, isDeleted: false } })
      return { branch: b.name, totalStaff: total, trainers }
    }))
    return NextResponse.json({ report: { title: 'Branch Wise Staff', rows: counts } })
  }

  return NextResponse.json({ report: { title: 'Report not implemented', rows: [] } })
}
