import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const branchesParam = url.searchParams.get('branches')
  const status = url.searchParams.get('status')
  const search = url.searchParams.get('q')
  const allowed = getSelectedBranchIds(session, branchesParam)

  const members = await db.member.findMany({
    where: {
      isDeleted: false,
      ...(allowed ? { branchId: { in: allowed } } : {}),
      ...(status ? { status } : {}),
      ...(search ? {
        OR: [
          { memberId: { contains: search } },
          { firstName: { contains: search } },
          { lastName: { contains: search } },
          { phone: { contains: search } },
          { cnic: { contains: search } },
        ]
      } : {}),
    },
    include: { branch: true, membershipPlan: true },
    orderBy: { createdAt: 'desc' },
    take: 200,
  })
  return NextResponse.json({ members })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('members.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  // Required fields per spec: First Name, Last Name, Contact Number, Membership, Trainer
  const missing: string[] = []
  if (!data.firstName || !String(data.firstName).trim()) missing.push('First Name')
  if (!data.lastName || !String(data.lastName).trim()) missing.push('Last Name')
  if (!data.phone || !String(data.phone).trim()) missing.push('Contact Number')
  if (!data.membershipPlanId) missing.push('Membership')
  if (!data.assignedTrainerId) missing.push('Trainer')
  if (!data.branchId) missing.push('Branch')
  if (missing.length > 0) {
    return NextResponse.json({ error: `Missing required fields: ${missing.join(', ')}` }, { status: 400 })
  }

  // Validate membership plan exists
  const plan = await db.membershipPlan.findUnique({ where: { id: data.membershipPlanId } })
  if (!plan) return NextResponse.json({ error: 'Invalid membership plan' }, { status: 400 })

  // Validate trainer exists and is actually a trainer
  const trainer = await db.staff.findUnique({ where: { id: data.assignedTrainerId } })
  if (!trainer) return NextResponse.json({ error: 'Invalid trainer' }, { status: 400 })
  if (!trainer.isTrainer) return NextResponse.json({ error: 'Assigned staff is not a trainer' }, { status: 400 })

  // Fee Relaxation Days: 0..27
  const feeRelaxationDays = Math.max(0, Math.min(27, Number(data.feeRelaxationDays) || 0))

  // Auto-generate member ID
  const count = await db.member.count()
  const memberId = `M-${String(count + 1).padStart(5, '0')}`

  const member = await db.member.create({
    data: {
      memberId,
      firstName: data.firstName,
      lastName: data.lastName,
      gender: data.gender,
      dob: data.dob ? new Date(data.dob) : null,
      phone: data.phone,
      whatsapp: data.whatsapp,
      email: data.email,
      address: data.address,
      emergencyContact: data.emergencyContact,
      emergencyContactNo: data.emergencyContactNo,
      photo: data.photo,
      cnic: data.cnic,
      joiningDate: data.joiningDate ? new Date(data.joiningDate) : new Date(),
      billingStartDate: data.billingStartDate ? new Date(data.billingStartDate) : (data.joiningDate ? new Date(data.joiningDate) : new Date()),
      feeRelaxationDays,
      status: data.status || 'Active',
      membershipPlanId: data.membershipPlanId || null,
      branchId: data.branchId,
      assignedTrainerId: data.assignedTrainerId || null,
      notes: data.notes,
      isActive: data.isActive !== false,
    },
    include: { branch: true, membershipPlan: true },
  })

  await db.auditLog.create({
    data: { userId: session.id, action: 'CREATE', module: 'members', details: JSON.stringify({ id: member.id, memberId }) },
  })
  return NextResponse.json({ member })
}
