import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from './auth'
import { postBookVoucher, reverseBookVoucher, type BookVoucherType } from './book-vouchers'

// =================================================================
// Shared REST handlers for the four dedicated book voucher stores:
//   CASHBOOK (/api/cashbook, CRV|CPV)
//   BANKBOOK (/api/bankbook, BRV|BPV — also creates Cheque rows)
//   JV       (/api/journal-vouchers)
//   OTB      (/api/opening-tb — allows unbalanced save)
// The voucher id IS the voucher number (e.g. CRV/BR-001/Sep25/000001).
// =================================================================

export type BookApiBookType = 'CASHBOOK' | 'BANKBOOK' | 'JV' | 'OTB'

const TABLE: Record<BookApiBookType, 'cashbookVoucher' | 'bankbookVoucher' | 'journalVoucher' | 'openTbVoucher'> = {
  CASHBOOK: 'cashbookVoucher',
  BANKBOOK: 'bankbookVoucher',
  JV: 'journalVoucher',
  OTB: 'openTbVoucher',
}

const TYPES: Record<BookApiBookType, BookVoucherType[]> = {
  CASHBOOK: ['CRV', 'CPV'],
  BANKBOOK: ['BRV', 'BPV'],
  JV: ['JV'],
  OTB: ['OTV'],
}

function usesBookAccount(voucherType: BookVoucherType): boolean {
  return voucherType === 'CRV' || voucherType === 'CPV' || voucherType === 'BRV' || voucherType === 'BPV'
}

/** COA rule: control accounts cannot carry voucher lines — only detail accounts may be posted to. */
async function assertNoControlLines(lines: any[]) {
  const ids = Array.from(new Set((lines || []).map((l: any) => l.accountId).filter(Boolean)))
  for (const id of ids) {
    const chart = await db.chart.findUnique({ where: { id }, select: { id: true, name: true, isControl: true, isDetail: true } })
    if (!chart) throw new Error(`Account "${id}" not found`)
    if (chart.isControl) throw new Error(`Account "${chart.id} — ${chart.name}" is a control account and cannot have voucher lines`)
  }
}

const BOOK_TYPES: BookApiBookType[] = ['CASHBOOK', 'BANKBOOK', 'JV', 'OTB']

function normalizeLine(l: any) {
  return {
    accountId: l.accountId,
    amount: Number(l.amount) || 0,
    debit: Number(l.debit) || 0,
    credit: Number(l.credit) || 0,
    lineDescription: l.lineDescription || undefined,
    title: l.title || undefined,
    reference: l.reference || undefined,
    billType: l.billType || undefined,
    taxRate: Number(l.taxRate) || 0,
    taxAmount: Number(l.taxAmount) || 0,
    chequeNo: l.chequeNo || undefined,
    chequeBankName: l.chequeBankName || undefined,
  }
}

async function createChequesForVoucher(voucherId: string, voucherDate: Date, lines: any[], chequeDate?: string | null) {
  const rows = (lines || []).filter((l: any) => l.chequeNo)
  for (const l of rows) {
    await db.cheque.create({
      data: {
        voucherId,
        chequeNo: l.chequeNo,
        chequeDate: chequeDate ? new Date(chequeDate) : voucherDate,
        bankName: l.chequeBankName || null,
        amount: Number(l.amount) || 0,
        status: 'Hold',
      },
    })
  }
}

function includeFor(bookType: BookApiBookType) {
  const base = { lines: { include: { account: true } } }
  if (bookType === 'CASHBOOK') return { branch: true, bookChart: true, ...base }
  if (bookType === 'BANKBOOK') return { branch: true, bookChart: true, cheques: true, ...base }
  if (bookType === 'OTB') return { branch: true, knockOffs: { include: { account: true } }, ...base }
  return { branch: true, ...base }
}

function buildWhere(bookType: BookApiBookType, url: URL, allowed: string[] | null) {
  const typeParam = url.searchParams.get('type')
  let voucherType: string[] | undefined = TYPES[bookType]
  if (typeParam) {
    if (!TYPES[bookType].includes(typeParam as BookVoucherType)) return { __invalid: typeParam } as any
    voucherType = [typeParam]
  }
  const branchParam = url.searchParams.get('branches') || url.searchParams.get('branchId')
  const status = url.searchParams.get('status')
  const from = url.searchParams.get('from')
  const to = url.searchParams.get('to')
  const search = url.searchParams.get('search') || url.searchParams.get('q')
  const dateFilter = from || to
    ? { voucherDate: { ...(from ? { gte: new Date(from) } : {}), ...(to ? { lte: new Date(to) } : {}) } }
    : {}
  return {
    where: {
      voucherType: voucherType ? { in: voucherType } : undefined,
      ...(allowed ? { branchId: { in: allowed } } : {}),
      ...(branchParam && branchParam !== 'all' ? { branchId: branchParam } : {}),
      ...(status ? { status } : {}),
      ...dateFilter,
      ...(search ? { OR: [{ id: { contains: search } }, { description: { contains: search } }, { reference: { contains: search } }] } : {}),
    },
  }
}

export function bookVoucherApi(bookType: BookApiBookType) {
  // GET list -----------------------------------------------------------
  async function list(req: NextRequest) {
    const session = await getSession()
    if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    const url = new URL(req.url)
    const allowed = getSelectedBranchIds(session, url.searchParams.get('branches'))
    const built = buildWhere(bookType, url, allowed)
    if (built.__invalid) return NextResponse.json({ error: `type must be one of ${TYPES[bookType].join('|')}` }, { status: 400 })
    const vouchers = await (db as any)[TABLE[bookType]].findMany({
      where: built.where,
      include: includeFor(bookType),
      orderBy: { voucherDate: 'desc' },
      take: 300,
    })
    return NextResponse.json({ vouchers })
  }

  // GET one ------------------------------------------------------------
  async function getOne(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const session = await getSession()
    if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    const { id } = await params
    const voucher = await (db as any)[TABLE[bookType]].findUnique({
      where: { id },
      include: includeFor(bookType),
    })
    if (!voucher) return NextResponse.json({ error: 'Voucher not found' }, { status: 404 })
    return NextResponse.json({ voucher })
  }

  // POST create --------------------------------------------------------
  async function create(req: NextRequest) {
    const session = await getSession()
    if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    if (!session.permissions.includes('vouchers.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

    const data = await req.json()
    const voucherType = data.voucherType as BookVoucherType
    if (!TYPES[bookType].includes(voucherType)) {
      return NextResponse.json({ error: `voucherType must be one of ${TYPES[bookType].join('|')}` }, { status: 400 })
    }
    if (!data.voucherDate || !data.branchId) {
      return NextResponse.json({ error: 'voucherDate and branchId are required' }, { status: 400 })
    }
    if (usesBookAccount(voucherType) && !data.bookChartId) {
      return NextResponse.json({ error: 'Book Account is required' }, { status: 400 })
    }
    const branch = await db.branch.findUnique({ where: { id: data.branchId } })
    if (!branch) return NextResponse.json({ error: 'Invalid branch' }, { status: 400 })

    try {
      await assertNoControlLines(data.lines)
      const voucher = await postBookVoucher({
        voucherType,
        voucherDate: new Date(data.voucherDate),
        branchId: data.branchId,
        branchCode: branch.code,
        bookChartId: data.bookChartId || null,
        description: data.description,
        reference: data.reference,
        paymentMode: data.paymentMode,
        lines: (data.lines || []).map(normalizeLine),
        postedById: data.postedById || session.id,
        allowUnbalanced: data.allowUnbalanced === true,
      })
      if (bookType === 'BANKBOOK' && data.paymentMode === 'Cheque') {
        await createChequesForVoucher(voucher.id, new Date(data.voucherDate), data.lines || [], data.chequeDate)
      }
      return NextResponse.json({ voucher, difference: (voucher as any).difference ?? null })
    } catch (e: any) {
      return NextResponse.json({ error: e.message || 'Failed to post voucher' }, { status: 400 })
    }
  }

  // PATCH edit (re-post with existingVoucherId) -------------------------
  async function update(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const session = await getSession()
    if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    if (!session.permissions.includes('vouchers.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

    const { id } = await params
    const data = await req.json()
    const existing = await (db as any)[TABLE[bookType]].findUnique({ where: { id } })
    if (!existing) return NextResponse.json({ error: 'Voucher not found' }, { status: 404 })
    if (existing.status === 'Reversed') return NextResponse.json({ error: 'Reversed vouchers cannot be edited' }, { status: 400 })

    const voucherType = (data.voucherType || existing.voucherType) as BookVoucherType
    if (!TYPES[bookType].includes(voucherType)) {
      return NextResponse.json({ error: `voucherType must be one of ${TYPES[bookType].join('|')}` }, { status: 400 })
    }
    const branch = await db.branch.findUnique({ where: { id: existing.branchId } })
    if (!branch) return NextResponse.json({ error: 'Invalid branch on voucher' }, { status: 400 })

    try {
      await assertNoControlLines(data.lines)
      const voucher = await postBookVoucher({
        voucherType,
        voucherDate: new Date(data.voucherDate || existing.voucherDate),
        branchId: existing.branchId,
        branchCode: branch.code,
        bookChartId: data.bookChartId || existing.bookChartId || null,
        description: data.description,
        reference: data.reference,
        paymentMode: data.paymentMode ?? existing.paymentMode,
        lines: (data.lines || []).map(normalizeLine),
        postedById: session.id,
        allowUnbalanced: data.allowUnbalanced === true,
        existingVoucherId: id,
      })
      if (bookType === 'BANKBOOK') {
        // refresh cheque rows to match the edited lines
        await db.cheque.deleteMany({ where: { voucherId: id } })
        if ((data.paymentMode ?? existing.paymentMode) === 'Cheque') {
          await createChequesForVoucher(id, new Date(data.voucherDate || existing.voucherDate), data.lines || [], data.chequeDate)
        }
      }
      return NextResponse.json({ voucher, difference: (voucher as any).difference ?? null })
    } catch (e: any) {
      return NextResponse.json({ error: e.message || 'Failed to update voucher' }, { status: 400 })
    }
  }

  // POST action ({ action: 'reverse', reason }) -------------------------
  async function action(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const session = await getSession()
    if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    const { id } = await params
    const data = await req.json()

    if (data.action === 'reverse') {
      if (!session.permissions.includes('vouchers.reverse')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
      const existing = await (db as any)[TABLE[bookType]].findUnique({ where: { id } })
      if (!existing) return NextResponse.json({ error: 'Voucher not found' }, { status: 404 })
      try {
        const reversalId = await reverseBookVoucher(id, existing.voucherType, session.id, data.reason || 'Manual reversal')
        return NextResponse.json({ success: true, reversalId })
      } catch (e: any) {
        return NextResponse.json({ error: e.message }, { status: 400 })
      }
    }
    return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
  }

  // DELETE — always rejected -------------------------------------------
  async function remove(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const session = await getSession()
    if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    return NextResponse.json({ error: 'Posted vouchers cannot be deleted; use reversal' }, { status: 400 })
  }

  return { list, getOne, create, update, action, remove }
}

export const BOOK_VOUCHER_BOOK_TYPES = BOOK_TYPES
