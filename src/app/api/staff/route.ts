import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const allowed = getSelectedBranchIds(session, url.searchParams.get('branches'))
  const isTrainer = url.searchParams.get('isTrainer')
  const search = url.searchParams.get('q')

  const staff = await db.staff.findMany({
    where: {
      isDeleted: false,
      ...(allowed ? { branchId: { in: allowed } } : {}),
      ...(isTrainer === 'true' ? { isTrainer: true } : {}),
      ...(search ? { OR: [{ employeeId: { contains: search } }, { firstName: { contains: search } }] } : {}),
    },
    include: { branch: true, shift: true },
    orderBy: { createdAt: 'desc' },
    take: 200,
  })
  return NextResponse.json({ staff })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('staff.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  if (!data.firstName || !data.branchId) return NextResponse.json({ error: 'First name and branch required' }, { status: 400 })

  const count = await db.staff.count()
  const employeeId = `EMP-${String(count + 1).padStart(4, '0')}`

  const staff = await db.staff.create({
    data: {
      employeeId,
      firstName: data.firstName,
      lastName: data.lastName,
      fatherGuardian: data.fatherGuardian,
      cnic: data.cnic,
      photo: data.photo,
      address: data.address,
      emergencyContact: data.emergencyContact,
      emergencyContactNo: data.emergencyContactNo,
      phone: data.phone,
      whatsapp: data.whatsapp,
      telephone: data.telephone,
      fax: data.fax,
      email: data.email,
      joiningDate: data.joiningDate ? new Date(data.joiningDate) : new Date(),
      department: data.department,
      designation: data.designation,
      isTrainer: !!data.isTrainer,
      specialization: data.specialization,
      availability: data.availability,
      trainerSchedule: data.trainerSchedule,
      personalTraining: !!data.personalTraining,
      branchId: data.branchId,
      shiftId: data.shiftId || null,
      basicSalary: Number(data.basicSalary) || 0,
      fuelAllowance: Number(data.fuelAllowance) || 0,
      rentAllowance: Number(data.rentAllowance) || 0,
      houseAllowance: Number(data.houseAllowance) || 0,
      otherAllowance: Number(data.otherAllowance) || 0,
      sessi: Number(data.sessi) || 0,
      eobi: Number(data.eobi) || 0,
      fbrTaxNumber: data.fbrTaxNumber,
      overtimeAllowed: !!data.overtimeAllowed,
      overtimeRate: Number(data.overtimeRate) || 0,
    },
    include: { branch: true, shift: true },
  })
  await db.auditLog.create({ data: { userId: session.id, action: 'CREATE', module: 'staff', details: JSON.stringify({ id: staff.id, employeeId }) } })
  return NextResponse.json({ staff })
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('staff.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  if (!data.id) return NextResponse.json({ error: 'id required' }, { status: 400 })

  const existing = await db.staff.findUnique({ where: { id: data.id } })
  if (!existing) return NextResponse.json({ error: 'Staff not found' }, { status: 404 })

  const staff = await db.staff.update({
    where: { id: data.id },
    data: {
      firstName: data.firstName,
      lastName: data.lastName,
      fatherGuardian: data.fatherGuardian,
      cnic: data.cnic,
      photo: data.photo,
      address: data.address,
      emergencyContact: data.emergencyContact,
      emergencyContactNo: data.emergencyContactNo,
      phone: data.phone,
      whatsapp: data.whatsapp,
      telephone: data.telephone,
      fax: data.fax,
      email: data.email,
      joiningDate: data.joiningDate ? new Date(data.joiningDate) : undefined,
      department: data.department,
      designation: data.designation,
      isTrainer: data.isTrainer !== undefined ? !!data.isTrainer : undefined,
      specialization: data.specialization !== undefined ? data.specialization : undefined,
      availability: data.availability !== undefined ? data.availability : undefined,
      trainerSchedule: data.trainerSchedule !== undefined ? data.trainerSchedule : undefined,
      personalTraining: data.personalTraining !== undefined ? !!data.personalTraining : undefined,
      branchId: data.branchId,
      shiftId: data.shiftId || null,
      basicSalary: data.basicSalary !== undefined ? Number(data.basicSalary) : undefined,
      fuelAllowance: data.fuelAllowance !== undefined ? Number(data.fuelAllowance) : undefined,
      rentAllowance: data.rentAllowance !== undefined ? Number(data.rentAllowance) : undefined,
      houseAllowance: data.houseAllowance !== undefined ? Number(data.houseAllowance) : undefined,
      otherAllowance: data.otherAllowance !== undefined ? Number(data.otherAllowance) : undefined,
      sessi: data.sessi !== undefined ? Number(data.sessi) : undefined,
      eobi: data.eobi !== undefined ? Number(data.eobi) : undefined,
      fbrTaxNumber: data.fbrTaxNumber,
      overtimeAllowed: data.overtimeAllowed !== undefined ? !!data.overtimeAllowed : undefined,
      overtimeRate: data.overtimeRate !== undefined ? Number(data.overtimeRate) : undefined,
      isActive: data.isActive !== undefined ? data.isActive : undefined,
    },
    include: { branch: true, shift: true },
  })
  await db.auditLog.create({ data: { userId: session.id, action: 'UPDATE', module: 'staff', details: JSON.stringify({ id: staff.id }) } })
  return NextResponse.json({ staff })
}

export async function DELETE(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('staff.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const url = new URL(req.url)
  const id = url.searchParams.get('id')
  if (!id) return NextResponse.json({ error: 'id required' }, { status: 400 })
  // Soft delete
  await db.staff.update({ where: { id }, data: { isDeleted: true, isActive: false } })
  await db.auditLog.create({ data: { userId: session.id, action: 'DELETE', module: 'staff', details: JSON.stringify({ id }) } })
  return NextResponse.json({ success: true })
}
