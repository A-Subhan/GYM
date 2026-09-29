import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'

// Payload → Prisma data mapper shared by create/update
function staffFields(data: any) {
  return {
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
    branchId: data.branchId,
    shiftId: data.shiftId !== undefined ? (data.shiftId || null) : undefined,
    basicSalary: data.basicSalary !== undefined ? Number(data.basicSalary) || 0 : undefined,
    fuelAllowance: data.fuelAllowance !== undefined ? Number(data.fuelAllowance) || 0 : undefined,
    rentAllowance: data.rentAllowance !== undefined ? Number(data.rentAllowance) || 0 : undefined,
    houseAllowance: data.houseAllowance !== undefined ? Number(data.houseAllowance) || 0 : undefined,
    otherAllowance: data.otherAllowance !== undefined ? Number(data.otherAllowance) || 0 : undefined,
    sessi: data.sessi !== undefined ? Number(data.sessi) || 0 : undefined,
    eobi: data.eobi !== undefined ? Number(data.eobi) || 0 : undefined,
    fbrTaxNumber: data.fbrTaxNumber,
    overtimeAllowed: data.overtimeAllowed !== undefined ? !!data.overtimeAllowed : undefined,
    overtimeRate: data.overtimeRate !== undefined ? Number(data.overtimeRate) || 0 : undefined,
  }
}

function validateCommon(data: any, requireAll: boolean): string | null {
  if (requireAll || data.firstName !== undefined) {
    if (!data.firstName || !String(data.firstName).trim()) return 'First name is required'
  }
  if (requireAll || data.branchId !== undefined) {
    if (!data.branchId) return 'Branch is required'
  }
  if (requireAll || data.joiningDate !== undefined) {
    if (!data.joiningDate) return 'Joining date is required'
  }
  if (data.joiningDate && isNaN(new Date(data.joiningDate).getTime())) return 'Invalid joining date'
  return null
}

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
  const invalid = validateCommon(data, true)
  if (invalid) return NextResponse.json({ error: invalid }, { status: 400 })

  try {
    // Employee ID: client-supplied wins, otherwise atomic sequence EMP-00001, EMP-00002, …
    if (data.shiftId === undefined) data.shiftId = null
    const staff = await db.$transaction(async (tx) => {
      let employeeId = typeof data.employeeId === 'string' ? data.employeeId.trim() : ''
      if (!employeeId) {
        const seqRow = await tx.idSequence.upsert({
          where: { key: 'EMPLOYEE' },
          update: { next: { increment: 1 } },
          create: { key: 'EMPLOYEE', next: 2 },
        })
        employeeId = `EMP-${String(seqRow.next - 1).padStart(5, '0')}`
      }
      return tx.staff.create({ data: { employeeId, ...staffFields(data) }, include: { branch: true, shift: true } })
    })
    await db.auditLog.create({ data: { userId: session.id, action: 'CREATE', module: 'staff', details: JSON.stringify({ id: staff.id, employeeId: staff.employeeId }) } })
    return NextResponse.json({ staff })
  } catch (e: any) {
    if (e?.code === 'P2002') return NextResponse.json({ error: 'An employee with this Employee ID already exists' }, { status: 400 })
    throw e
  }
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('staff.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  if (!data.id) return NextResponse.json({ error: 'id required' }, { status: 400 })

  const existing = await db.staff.findUnique({ where: { id: data.id } })
  if (!existing || existing.isDeleted) return NextResponse.json({ error: 'Staff not found' }, { status: 404 })

  const invalid = validateCommon(data, false)
  if (invalid) return NextResponse.json({ error: invalid }, { status: 400 })

  try {
    // employeeId is the immutable business id — never changed on update
    const staff = await db.staff.update({
      where: { id: data.id },
      data: staffFields(data),
      include: { branch: true, shift: true },
    })
    await db.auditLog.create({ data: { userId: session.id, action: 'UPDATE', module: 'staff', details: JSON.stringify({ id: staff.id, employeeId: staff.employeeId }) } })
    return NextResponse.json({ staff })
  } catch (e: any) {
    if (e?.code === 'P2002') return NextResponse.json({ error: 'Update violates a unique constraint' }, { status: 400 })
    throw e
  }
}

export async function DELETE(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('staff.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const url = new URL(req.url)
  const id = url.searchParams.get('id')
  if (!id) return NextResponse.json({ error: 'id required' }, { status: 400 })

  const existing = await db.staff.findUnique({ where: { id } })
  if (!existing || existing.isDeleted) return NextResponse.json({ error: 'Staff not found' }, { status: 404 })

  // Soft delete — keep payroll/leave/attendance history intact
  await db.staff.update({ where: { id }, data: { isDeleted: true, isActive: false } })
  await db.auditLog.create({ data: { userId: session.id, action: 'DELETE', module: 'staff', details: JSON.stringify({ id, employeeId: existing.employeeId, softDelete: true }) } })
  return NextResponse.json({ success: true, message: `Employee ${existing.employeeId} deleted` })
}
