import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

const ACCOUNT_TYPES = ['Asset', 'Liability', 'Equity', 'Revenue', 'Expense']

// GET /api/charts — list chart-of-accounts entries (id = account code)
// Optional: ?branchId&search&isActive&type&bookType&tag&detailOnly
export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const branchId = url.searchParams.get('branchId')
  const search = url.searchParams.get('search')
  const isActive = url.searchParams.get('isActive')
  const type = url.searchParams.get('type')
  const bookType = url.searchParams.get('bookType')
  const tag = url.searchParams.get('tag')
  const detailOnly = url.searchParams.get('detailOnly')

  const allowed = session.accessibleBranchIds === '*' ? null : session.accessibleBranchIds.split(',')

  const charts = await db.chart.findMany({
    where: {
      ...(allowed ? { OR: [{ branchId: { in: allowed } }, { branchId: null }] } : {}),
      ...(branchId && branchId !== 'all' ? { OR: [{ branchId }, { branchId: null }] } : {}),
      ...(type && type !== 'all' ? { accountType: type } : {}),
      ...(bookType && bookType !== 'all' ? { bookType } : {}),
      ...(tag ? { accountTag: tag } : {}),
      ...(isActive === 'true' ? { isActive: true } : {}),
      ...(isActive === 'false' ? { isActive: false } : {}),
      ...(detailOnly === 'true' ? { isDetail: true } : {}),
      ...(search ? { OR: [{ id: { contains: search } }, { name: { contains: search } }] } : {}),
    },
    include: { parent: { select: { id: true, name: true, accountType: true, isControl: true } } },
    orderBy: { id: 'asc' },
  })
  // Tree contract: the 'ROOT' sentinel means no parent. Expose parentId
  // (null for roots) and null the parent include for roots so the UI can
  // rebuild the head / sub-head hierarchy (control vs detail levels).
  const mapped = charts.map((c) => {
    const isRoot = c.parentCode === 'ROOT' || !c.parentCode
    return {
      ...c,
      parentId: isRoot ? null : c.parentCode,
      parent: isRoot ? null : c.parent,
    }
  })
  return NextResponse.json({ charts: mapped })
}

// POST /api/charts — create a chart account
// Mandatory: name, accountType. Detail accounts must sit under a control account.
// The account code (id) is auto-generated from the parent code + next sequence,
// following the coaLevelDigits setting in Defaults (default "2").
// A caller may still pass an explicit `id` for backward compatibility.
export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('finance.coa')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  // Accept an explicit code for backward compat; if absent, auto-generate.
  const explicitCode = data.id ? String(data.id).trim().toUpperCase() : ''
  if (explicitCode && /\s/.test(explicitCode)) return NextResponse.json({ error: 'Account Code cannot contain spaces' }, { status: 400 })
  if (!data.name || !String(data.name).trim()) return NextResponse.json({ error: 'Account Name is required' }, { status: 400 })
  if (!data.accountType || !ACCOUNT_TYPES.includes(data.accountType)) {
    return NextResponse.json({ error: 'Account Type must be one of Asset, Liability, Equity, Revenue, Expense' }, { status: 400 })
  }

  const isControl = data.isControl === true
  const isDetail = isControl ? false : data.isDetail !== false

  // Final schema: a single NOT NULL parentCode column ('ROOT' = tree root).
  // `parentId` is still accepted from callers and mapped onto parentCode.
  const parentCode = String(data.parentCode || data.parentId || '').trim().toUpperCase() || 'ROOT'

  if (isDetail) {
    if (parentCode === 'ROOT') return NextResponse.json({ error: 'Detail accounts must have a Parent (control) account' }, { status: 400 })
    const parent = await db.chart.findUnique({ where: { id: parentCode } })
    if (!parent) return NextResponse.json({ error: 'Parent account not found' }, { status: 400 })
    if (!parent.isControl) return NextResponse.json({ error: 'Detail accounts must be created under a control account' }, { status: 400 })
  }

  // --- Auto-generate the account code if not provided ---
  let code = explicitCode
  if (!code) {
    code = await generateAccountCode(parentCode)
  }

  const dupe = await db.chart.findUnique({ where: { id: code } })
  if (dupe) return NextResponse.json({ error: `Account code "${code}" already exists` }, { status: 400 })

  const branchId = data.branchId || session.branchId || null

  try {
    const chart = await db.chart.create({
      data: {
        id: code,
        name: String(data.name).trim(),
        parentCode,
        accountType: data.accountType,
        bookType: data.bookType || null,
        accountTag: data.accountTag || null,
        isControl,
        isDetail,
        isActive: data.isActive !== false,
        branchId: branchId || null,
        contactName: data.contactName || null,
        phone: data.phone || null,
        email: data.email || null,
        address: data.address || null,
        bankName: data.bankName || null,
        bankAccountNo: data.bankAccountNo || null,
        bankBranch: data.bankBranch || null,
        cnic: data.cnic || null,
        strn: data.strn || null,
        ntn: data.ntn || null,
        fbr: data.fbr || null,
        otherName: data.otherName || null,
        referenceNumber: data.referenceNumber || null,
        faxNumber: data.faxNumber || null,
        city: data.city || null,
        country: data.country || null,
        website: data.website || null,
        paymentTerms: data.paymentTerms || null,
        registrationNumber: data.registrationNumber || null,
        description: data.description || null,
      },
    })
    await db.auditLog.create({
      data: { userId: session.id, action: 'CREATE', module: 'coa', details: JSON.stringify({ id: chart.id, name: chart.name, autoGenerated: !explicitCode }) },
    })
    return NextResponse.json({ chart })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Failed to create account' }, { status: 400 })
  }
}

/**
 * Auto-generate a unique account code from the parent code + next sequence.
 * Reads coaLevelDigits from Defaults (default "2") to determine how many
 * digits to append.
 *
 * Root accounts (parentCode = 'ROOT'): the code is the next N-digit number
 *   among existing roots (e.g. "01", "02", ... when N=2).
 * Child accounts: the code is parentCode + next N-digit sequence among
 *   existing children of that parent (e.g. parent "01" → "0101", "0102"
 *   when N=2; or "01001", "01002" when N=3).
 *
 * Concurrency safe: uses a Prisma $transaction with SERIALIZABLE isolation
 * so two concurrent requests cannot generate the same code.
 */
async function generateAccountCode(parentCode: string): Promise<string> {
  // Read coaLevelDigits from Defaults (default "2")
  let digitsPerLevel = 2
  try {
    const defaults = await db.defaults.findFirst()
    if (defaults?.coaLevelDigits) {
      const parsed = parseInt(defaults.coaLevelDigits, 10)
      if (!isNaN(parsed) && parsed >= 1 && parsed <= 10) digitsPerLevel = parsed
    }
  } catch { /* Defaults table might not exist yet — use default */ }

  return db.$transaction(async (tx) => {
    if (parentCode === 'ROOT') {
      // Root: find the max N-digit code among existing roots
      const roots = await tx.chart.findMany({
        where: { parentCode: 'ROOT' },
        select: { id: true },
      })
      let maxSeq = 0
      for (const r of roots) {
        // Only consider codes that are exactly digitsPerLevel digits long
        if (r.id.length === digitsPerLevel && /^\d+$/.test(r.id)) {
          const n = parseInt(r.id, 10)
          if (!isNaN(n) && n > maxSeq) maxSeq = n
        }
      }
      const next = maxSeq + 1
      return String(next).padStart(digitsPerLevel, '0')
    } else {
      // Child: find the max N-digit suffix among children of this parent
      const children = await tx.chart.findMany({
        where: { parentCode },
        select: { id: true },
      })
      const prefix = parentCode
      let maxSeq = 0
      for (const c of children) {
        if (c.id.startsWith(prefix)) {
          const suffix = c.id.slice(prefix.length)
          // Only consider suffixes that are exactly digitsPerLevel digits long
          if (suffix.length === digitsPerLevel && /^\d+$/.test(suffix)) {
            const n = parseInt(suffix, 10)
            if (!isNaN(n) && n > maxSeq) maxSeq = n
          }
        }
      }
      const next = maxSeq + 1
      return prefix + String(next).padStart(digitsPerLevel, '0')
    }
  }, { isolationLevel: 'Serializable' })
}
