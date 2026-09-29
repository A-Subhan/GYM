import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { makeBranchPeriodId } from '@/lib/ids'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const branchId = url.searchParams.get('branchId')
  const plans = await db.membershipPlan.findMany({
    where: { ...(branchId && branchId !== 'all' ? { branchId } : {}) },
    include: { branch: { select: { id: true, name: true, code: true } } },
    orderBy: { name: 'asc' },
  })
  return NextResponse.json({ plans })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('memberships.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.name || !String(data.name).trim()) return NextResponse.json({ error: 'Name is required' }, { status: 400 })
  if (!data.branchId) return NextResponse.json({ error: 'Branch is required' }, { status: 400 })
  const durationDays = Number(data.durationDays)
  if (!durationDays || durationDays < 1) return NextResponse.json({ error: 'Duration must be at least 1 day' }, { status: 400 })
  const amount = Number(data.amount)
  if (isNaN(amount) || amount < 0) return NextResponse.json({ error: 'Amount must be a non-negative number' }, { status: 400 })

  // Plans are branch-scoped (branchId NOT NULL in the final schema) and the
  // plan id IS the business id: {branchCode}/{MMMyy}/{00001}.
  const branch = await db.branch.findUnique({ where: { id: data.branchId } })
  if (!branch) return NextResponse.json({ error: 'Invalid branch' }, { status: 400 })

  try {
    const id = await makeBranchPeriodId('PLAN', branch.code, new Date())
    const plan = await db.membershipPlan.create({
      data: {
        id,
        name: String(data.name).trim(),
        durationDays,
        amount,
        description: data.description,
        branchId: data.branchId,
        isActive: data.isActive !== false,
      },
    })
    return NextResponse.json({ plan })
  } catch (e: any) {
    if (e?.code === 'P2002') {
      return NextResponse.json({ error: 'A plan with this id already exists — please try again' }, { status: 400 })
    }
    throw e
  }
}
