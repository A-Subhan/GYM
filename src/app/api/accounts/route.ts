import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const url = new URL(req.url)
  const branchId = url.searchParams.get('branchId')
  const accountType = url.searchParams.get('accountType')
  const bookType = url.searchParams.get('bookType')
  const tag = url.searchParams.get('tag')

  const allowed = session.accessibleBranchIds === '*' ? null : session.accessibleBranchIds.split(',')
  const accounts = await db.account.findMany({
    where: {
      ...(allowed ? { branchId: { in: allowed } } : {}),
      ...(branchId && branchId !== 'all' ? { branchId } : {}),
      ...(accountType ? { accountType } : {}),
      ...(bookType ? { bookType } : {}),
      ...(tag ? { accountTag: tag } : {}),
    },
    orderBy: { code: 'asc' },
    include: { parent: true, branch: true },
  })
  return NextResponse.json({ accounts })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('finance.coa')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  if (!data.name || !data.accountType) return NextResponse.json({ error: 'Name and account type required' }, { status: 400 })

  // auto-generate code based on parent
  const branchId = data.branchId || session.branchId
  let code = data.code
  if (!code && data.parentId) {
    const parent = await db.account.findUnique({ where: { id: data.parentId } })
    if (!parent) return NextResponse.json({ error: 'Invalid parent' }, { status: 400 })
    // count siblings, append 3-digit
    const siblingCount = await db.account.count({ where: { parentId: data.parentId } })
    code = `${parent.code}${String(siblingCount + 1).padStart(3, '0')}`
    if (code.length > 12) return NextResponse.json({ error: 'Account code exceeds 12 digits (max hierarchy depth reached)' }, { status: 400 })
  } else if (!code) {
    // root level — pick next available 2-digit prefix
    const rootHeads = await db.account.findMany({ where: { parentId: null, branchId } })
    code = String(rootHeads.length + 1).padStart(2, '0')
  }

  // check depth <= 7
  let depth = 1
  let p = data.parentId ? await db.account.findUnique({ where: { id: data.parentId } }) : null
  while (p) {
    depth++
    p = p.parentId ? await db.account.findUnique({ where: { id: p.parentId } }) : null
  }
  if (depth > 7) return NextResponse.json({ error: 'Maximum hierarchy depth (7) exceeded' }, { status: 400 })

  const account = await db.account.create({
    data: {
      code,
      name: data.name,
      parentId: data.parentId || null,
      accountType: data.accountType,
      bookType: data.bookType,
      accountTag: data.accountTag,
      isControl: !!data.isControl,
      isDetail: data.isControl ? false : true,
      isActive: data.isActive !== false,
      branchId,
      contactName: data.contactName,
      phone: data.phone,
      email: data.email,
      address: data.address,
      bankName: data.bankName,
      bankAccountNo: data.bankAccountNo,
      bankBranch: data.bankBranch,
      cnic: data.cnic,
      ntn: data.ntn,
      description: data.description,
      openingBalance: data.openingBalance || 0,
      openingBalanceType: data.openingBalanceType || 'Dr',
    },
  })
  await db.auditLog.create({
    data: { userId: session.id, action: 'CREATE', module: 'coa', details: JSON.stringify({ id: account.id, code }) },
  })
  return NextResponse.json({ account })
}
