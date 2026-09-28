import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'
import { makeKnockOffBillId } from '@/lib/ids'

// Knock-off entries — bill-wise standing of Customer/Supplier accounts.
// Each entry gets an auto Bill ID: OTB-{branchCode}/{0000001}.
// Final schema: standalone rows (accountId + branchId); the Customer/Supplier
// accountTag rule is enforced here at application level, `description` is
// max 20 characters, and `dcFlag` must be Debit or Credit.
export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const allowed = getSelectedBranchIds(session, url.searchParams.get('branches'))
  const accountId = url.searchParams.get('accountId')
  const dcFlag = url.searchParams.get('dcFlag')

  const knockOffs = await db.knockOff.findMany({
    where: {
      ...(allowed ? { branchId: { in: allowed } } : {}),
      ...(accountId ? { accountId } : {}),
      ...(dcFlag ? { dcFlag } : {}),
    },
    include: {
      account: { select: { id: true, name: true, accountType: true, accountTag: true } },
      branch: { select: { id: true, name: true, code: true } },
    },
    orderBy: { createdAt: 'desc' },
    take: 500,
  })
  return NextResponse.json({ knockOffs })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('vouchers.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  const { accountId, branchId, description, amount, dcFlag } = data
  if (!accountId || !branchId || description === undefined || amount === undefined || amount === null || !dcFlag) {
    return NextResponse.json({ error: 'accountId, branchId, description, amount, dcFlag are required' }, { status: 400 })
  }
  if (!['Debit', 'Credit'].includes(dcFlag)) {
    return NextResponse.json({ error: 'dcFlag must be Debit or Credit' }, { status: 400 })
  }
  if (String(description).trim().length > 20) {
    return NextResponse.json({ error: 'Description must be 20 characters or less' }, { status: 400 })
  }
  const amt = Number(amount)
  if (!(amt > 0)) return NextResponse.json({ error: 'Amount must be greater than zero' }, { status: 400 })

  const branch = await db.branch.findUnique({ where: { id: branchId } })
  if (!branch) return NextResponse.json({ error: 'Invalid branch' }, { status: 400 })

  const account = await db.chart.findUnique({ where: { id: accountId } })
  if (!account) return NextResponse.json({ error: 'Account not found' }, { status: 400 })
  if (account.isControl) return NextResponse.json({ error: 'Knock-off account must be a detail account' }, { status: 400 })
  // Customer/Supplier rule (application-enforced per final schema contract)
  if (account.accountTag !== 'Customer' && account.accountTag !== 'Supplier') {
    return NextResponse.json({ error: 'Knock-off account must be tagged Customer or Supplier' }, { status: 400 })
  }

  const billId = await makeKnockOffBillId(branch.code)

  const knockOff = await db.knockOff.create({
    data: {
      billId,
      billNumber: data.billNumber || null,
      referenceNumber: data.referenceNumber || null,
      billType: data.billType || null,
      amount: amt,
      dcFlag,
      referenceDate: data.referenceDate ? new Date(data.referenceDate) : null,
      dueDate: data.dueDate ? new Date(data.dueDate) : null,
      description: String(description).trim().slice(0, 20),
      accountId,
      branchId,
      createdById: data.createdById || session.id,
    },
    include: {
      account: { select: { id: true, name: true, accountType: true, accountTag: true } },
      branch: { select: { id: true, name: true, code: true } },
    },
  })
  await db.auditLog.create({
    data: { userId: session.id, action: 'CREATE', module: 'knock-offs', details: JSON.stringify({ id: knockOff.id, billId, amount: amt, dcFlag }) },
  })

  return NextResponse.json({ knockOff })
}
