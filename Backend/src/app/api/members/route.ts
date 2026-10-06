import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'
import { makeBranchPeriodId, makeFeeId } from '@/lib/ids'

type FeeRow = Awaited<ReturnType<typeof db.fee.create>>

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
          { id: { contains: search } },
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
  // memberId is exposed explicitly (it IS the business id) so grids can bind
  // the Member ID column without guessing the field name.
  return NextResponse.json({ members: members.map(m => ({ ...m, memberId: m.id })) })
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
  // One-time joining fee — charged ON TOP of the membership fee on the first invoice
  const joiningFee = Math.max(0, Number(data.joiningFee) || 0)

  const joiningDate = data.joiningDate ? new Date(data.joiningDate) : new Date()
  const billingStartDate = data.billingStartDate ? new Date(data.billingStartDate) : joiningDate

  // Branch code is required for the business member ID: {branchCode}/{MMMyy}/{00001}
  // (the member id IS the business id — there is no separate memberId column).
  const branch = await db.branch.findUnique({ where: { id: data.branchId } })
  if (!branch) return NextResponse.json({ error: 'Invalid branch' }, { status: 400 })
  const memberId = await makeBranchPeriodId('MEMBER', branch.code, joiningDate)

  // Auto-generate the first period fee row (id = {branchCode}/{MMMyy}/{00001})
  let feeNo: string | null = null
  if (data.membershipPlanId) {
    feeNo = await makeFeeId(branch.code, billingStartDate)
  }

  const { member, fee } = await db.$transaction(async (tx) => {
    const created = await tx.member.create({
      data: {
        id: memberId,
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
        joiningDate,
        billingStartDate,
        feeRelaxationDays,
        joiningFee,
        status: data.status || 'Active',
        membershipPlanId: data.membershipPlanId || null,
        branchId: data.branchId,
        assignedTrainerId: data.assignedTrainerId || null,
        notes: data.notes,
        isActive: data.isActive !== false,
      },
    })

    let createdFee: FeeRow | null = null
    if (feeNo && plan) {
      // Fee charged = membership fee + joining fee (one-time), visible on the Fees & Invoices screen
      const totalFee = Math.max(0, plan.amount + joiningFee)
      // Billing period: [start, start + durationDays - 1]
      const periodEnd = new Date(billingStartDate)
      periodEnd.setDate(periodEnd.getDate() + plan.durationDays - 1)
      periodEnd.setHours(23, 59, 59, 999)
      // Due date: billing start + fee relaxation days + 10 days
      const dueDate = new Date(billingStartDate)
      dueDate.setDate(dueDate.getDate() + feeRelaxationDays + 10)
      createdFee = await tx.fee.create({
        data: {
          id: feeNo,
          memberId: created.id,
          branchId: created.branchId,
          billingPeriodStart: billingStartDate,
          billingPeriodEnd: periodEnd,
          amount: totalFee,
          discount: 0,
          paidAmount: 0,
          balance: totalFee,
          dueDate,
          status: 'Unpaid',
          reference: joiningFee > 0 ? `Membership fee ${plan.amount} + Joining fee ${joiningFee}` : undefined,
        },
      })
    }
    return { member: created, fee: createdFee }
  })

  await db.auditLog.create({
    data: { userId: session.id, action: 'CREATE', module: 'members', details: JSON.stringify({ id: member.id, memberId, feeNo }) },
  })

  const full = await db.member.findUnique({
    where: { id: member.id },
    include: { branch: true, membershipPlan: true, fees: true },
  })
  return NextResponse.json({ member: full, fee })
}
