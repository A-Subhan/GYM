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
  const accounts = await db.charts.findMany({
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
  // Required fields per spec: Name, Parent Account, Account Type, Account Tag, Book Type, Control/Detail
  if (!data.name || !data.name.trim()) return NextResponse.json({ error: 'Account Name is required' }, { status: 400 })
  if (!data.accountType) return NextResponse.json({ error: 'Account Type is required' }, { status: 400 })
  if (!data.accountTag) return NextResponse.json({ error: 'Account Tag is required' }, { status: 400 })
  if (!data.bookType) return NextResponse.json({ error: 'Book Type is required' }, { status: 400 })
  if (data.isControl === undefined && data.isDetail === undefined) return NextResponse.json({ error: 'Control / Detail is required' }, { status: 400 })
  if (!data.parentId && data.parentId !== null) return NextResponse.json({ error: 'Parent Account is required (select a root or parent account)' }, { status: 400 })

  // auto-generate code based on parent
  const branchId = data.branchId || session.branchId
  let code = data.code
  if (!code && data.parentId) {
    const parent = await db.charts.findUnique({ where: { id: data.parentId } })
    if (!parent) return NextResponse.json({ error: 'Invalid parent' }, { status: 400 })
    // count siblings, append 3-digit (configurable via COA Level Detailing)
    const financeDefaults = await db.financeDefaults.findFirst()
    const levelDigits = financeDefaults?.coaLevelDetailing ?? 2
    const siblingCount = await db.charts.count({ where: { parentId: data.parentId } })
    code = `${parent.code}${String(siblingCount + 1).padStart(levelDigits, '0')}`
    if (code.length > 12) return NextResponse.json({ error: 'Account code exceeds 12 digits (max hierarchy depth reached)' }, { status: 400 })
  } else if (!code) {
    // root level — pick next available 2-digit prefix
    const rootHeads = await db.charts.findMany({ where: { parentId: null, branchId } })
    code = String(rootHeads.length + 1).padStart(2, '0')
  }

  // check depth <= 7
  let depth = 1
  let p = data.parentId ? await db.charts.findUnique({ where: { id: data.parentId } }) : null
  while (p) {
    depth++
    p = p.parentId ? await db.charts.findUnique({ where: { id: p.parentId } }) : null
  }
  if (depth > 7) return NextResponse.json({ error: 'Maximum hierarchy depth (7) exceeded' }, { status: 400 })

  // Validate Payment Terms only applies to Customer/Supplier accountTag
  if (data.paymentTerms && !['Customer', 'Supplier'].includes(data.accountTag)) {
    return NextResponse.json({ error: 'Payment Terms can only be set for Customer or Supplier accounts' }, { status: 400 })
  }

  // Determine Control/Detail
  const isControl = !!data.isControl
  const isDetail = data.isControl ? false : (data.isDetail === undefined ? true : !!data.isDetail)

  // After this account is created, lock COA Level Detailing (per spec)
  const existingDefaults = await db.financeDefaults.findFirst()
  if (existingDefaults && !existingDefaults.coaLevelLocked) {
    await db.financeDefaults.update({ where: { id: existingDefaults.id }, data: { coaLevelLocked: true } })
  }

  const account = await db.charts.create({
    data: {
      code,
      name: data.name,
      parentId: data.parentId || null,
      accountType: data.accountType,
      bookType: data.bookType,
      accountTag: data.accountTag,
      isControl,
      isDetail,
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
      strn: data.strn,
      fbr: data.fbr,
      description: data.description,
      otherName: data.otherName,
      referenceNumber: data.referenceNumber,
      faxNumber: data.faxNumber,
      city: data.city,
      country: data.country,
      website: data.website,
      paymentTerms: ['Customer', 'Supplier'].includes(data.accountTag) ? data.paymentTerms : null,
      registrationNumber: data.registrationNumber,
    },
  })
  await db.auditLog.create({
    data: { userId: session.id, action: 'CREATE', module: 'coa', details: JSON.stringify({ id: account.id, code }) },
  })
  return NextResponse.json({ account })
}
