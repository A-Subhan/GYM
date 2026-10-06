import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from './auth'
import { postBookVoucher, reverseBookVoucher, bookDelegates, type BookVoucherType, type BookType } from './book-vouchers'

// =================================================================
// Shared REST handlers for the four dedicated book voucher stores:
//   CASHBOOK (/api/cashbook, CRV|CPV)
//   BANKBOOK (/api/bankbook, BRV|BPV — cheque fields live on BankBookLine)
//   JV       (/api/journal-vouchers)
//   OTB      (/api/opening-tb — allows unbalanced save)
// The voucher id IS the voucher number (e.g. CRV/BR-001/SEP26/000001).
// =================================================================

export type BookApiBookType = BookType

const DELEGATES: Record<BookApiBookType, { voucher: string; line: string }> = {
  CASHBOOK: bookDelegates('CASHBOOK'),
  BANKBOOK: bookDelegates('BANKBOOK'),
  JV: bookDelegates('JV'),
  OTB: bookDelegates('OTB'),
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

function includeFor(bookType: BookApiBookType) {
  const base = { lines: { include: { account: true } } }
  if (bookType === 'CASHBOOK') return { branch: true, bookChart: true, ...base }
  if (bookType === 'BANKBOOK') return { branch: true, bookChart: true, ...base }
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
  // Branch filter: the requested branch is intersected with the caller's allowed
  // branches (a restricted user may only narrow, never widen, the scope).
  let branchFilter: string[] | null = allowed
  if (branchParam && branchParam !== 'all') {
    branchFilter = allowed ? allowed.filter((b) => b === branchParam) : [branchParam]
  }
  return {
    where: {
      // soft-deleted vouchers never appear in any list
      isDeleted: false,
      voucherType: voucherType ? { in: voucherType } : undefined,
      ...(branchFilter ? { branchId: { in: branchFilter } } : {}),
      ...(status ? { status } : {}),
      ...dateFilter,
      ...(search ? { OR: [{ id: { contains: search } }, { description: { contains: search } }, { reference: { contains: search } }] } : {}),
    },
  }
}

export function bookVoucherApi(bookType: BookApiBookType) {
  const delegate = DELEGATES[bookType].voucher

  /**
   * Fetch the effective FinanceDefaults row for a branch (branch-specific
   * wins over company-wide). SAFE FOR PRE-MIGRATION: if the expanded
   * columns don't exist yet, the Prisma query fails and we default to
   * the historical behaviour (all flags = today's defaults).
   */
  async function resolveFinanceDefaults(branchId: string): Promise<{
    allowUnbalancedOTB: boolean
    allowBackDatedVouchers: boolean
    lockBeforeDate: Date | null
    voucherApprovalRequired: boolean
    allowEditPostedVouchers: boolean
    defaultCashPaymentMode: string | null
    defaultBankPaymentMode: string | null
    defaultCashAccountId: string | null
    defaultBankAccountId: string | null
  }> {
    const defaults = {
      allowUnbalancedOTB: true,
      allowBackDatedVouchers: true,
      lockBeforeDate: null as Date | null,
      voucherApprovalRequired: false,
      allowEditPostedVouchers: true,
      defaultCashPaymentMode: null as string | null,
      defaultBankPaymentMode: null as string | null,
      defaultCashAccountId: null as string | null,
      defaultBankAccountId: null as string | null,
    }
    try {
      const fd = (await db.financeDefaults.findFirst({
        where: { OR: [{ branchId }, { branchId: null }] },
        orderBy: [{ branchId: 'desc' }],
        select: {
          allowUnbalancedOTB: true,
          allowBackDatedVouchers: true,
          lockBeforeDate: true,
          voucherApprovalRequired: true,
          allowEditPostedVouchers: true,
          defaultCashPaymentMode: true,
          defaultBankPaymentMode: true,
          defaultCashAccountId: true,
          defaultBankAccountId: true,
        },
      })) as any | null
      if (fd) {
        return {
          allowUnbalancedOTB: fd.allowUnbalancedOTB ?? true,
          allowBackDatedVouchers: fd.allowBackDatedVouchers ?? true,
          lockBeforeDate: fd.lockBeforeDate ?? null,
          voucherApprovalRequired: fd.voucherApprovalRequired ?? false,
          allowEditPostedVouchers: fd.allowEditPostedVouchers ?? true,
          defaultCashPaymentMode: fd.defaultCashPaymentMode ?? null,
          defaultBankPaymentMode: fd.defaultBankPaymentMode ?? null,
          defaultCashAccountId: fd.defaultCashAccountId ?? null,
          defaultBankAccountId: fd.defaultBankAccountId ?? null,
        }
      }
      return defaults
    } catch {
      return defaults
    }
  }

  /**
   * Validate voucher date against FinanceDefaults:
   *  - lockBeforeDate: no voucher with date on or before this date
   *  - allowBackDatedVouchers: if OFF, voucher date cannot be earlier than today
   * Throws Error with a clear message on violation.
   */
  function validateVoucherDate(voucherDate: Date, fd: {
    allowBackDatedVouchers: boolean
    lockBeforeDate: Date | null
  }, action: 'create' | 'edit' | 'delete' | 'reverse'): void {
    // lockBeforeDate blocks ALL operations (create/edit/delete/reverse)
    if (fd.lockBeforeDate) {
      const lockDate = new Date(fd.lockBeforeDate)
      // set to start of day for comparison
      lockDate.setHours(0, 0, 0, 0)
      if (voucherDate <= lockDate) {
        throw new Error(`Voucher date ${voucherDate.toISOString().slice(0, 10)} is on or before the lock date ${lockDate.toISOString().slice(0, 10)}. Vouchers on or before the lock date cannot be created, edited, deleted, or reversed.`)
      }
    }
    // allowBackDatedVouchers only blocks create/edit (not delete/reverse,
    // which operate on an existing voucher with its own date)
    if (!fd.allowBackDatedVouchers && (action === 'create' || action === 'edit')) {
      const today = new Date()
      today.setHours(0, 0, 0, 0)
      const vDate = new Date(voucherDate)
      vDate.setHours(0, 0, 0, 0)
      if (vDate < today) {
        throw new Error(`Back-dated vouchers are not allowed. Voucher date ${vDate.toISOString().slice(0, 10)} cannot be earlier than today ${today.toISOString().slice(0, 10)}.`)
      }
    }
  }

  /**
   * For OTB only: enforce FinanceDefaults.allowUnbalancedOTB. If the
   * company-wide or branch-specific FinanceDefaults row has the flag OFF,
   * the request's `allowUnbalanced=true` is overridden to `false` so the
   * voucher must balance before it can be saved.
   * Returns the effective allowUnbalanced value.
   *
   * SAFE FOR PRE-MIGRATION: if the FinanceDefaults table doesn't have the
   * allowUnbalancedOTB column yet (migration 13 not run), the Prisma query
   * will fail. We catch the error and default to true (historical behaviour).
   */
  async function resolveAllowUnbalanced(branchId: string, requested: boolean): Promise<boolean> {
    if (bookType !== 'OTB') return requested
    if (!requested) return false
    try {
      // Try branch-specific first, then fall back to company-wide (branchId NULL).
      const fd = (await db.financeDefaults.findFirst({
        where: { OR: [{ branchId }, { branchId: null }] },
        orderBy: [{ branchId: 'desc' }], // branch-specific row wins if both exist
        select: { allowUnbalancedOTB: true },
      })) as { allowUnbalancedOTB: boolean } | null
      // Default ON when no row exists yet (preserves historical behaviour).
      return fd ? !!fd.allowUnbalancedOTB : true
    } catch {
      // Column doesn't exist yet (migration not run) — default to historical
      // behaviour (unbalanced OTB allowed).
      return true
    }
  }

  // GET list -----------------------------------------------------------
  async function list(req: NextRequest) {
    const session = await getSession()
    if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    const url = new URL(req.url)
    const allowed = getSelectedBranchIds(session, url.searchParams.get('branches'))
    const built = buildWhere(bookType, url, allowed)
    if (built.__invalid) return NextResponse.json({ error: `type must be one of ${TYPES[bookType].join('|')}` }, { status: 400 })
    const vouchers = await (db as any)[delegate].findMany({
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
    const voucher = await (db as any)[delegate].findUnique({
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
      const fd = await resolveFinanceDefaults(data.branchId)
      validateVoucherDate(new Date(data.voucherDate), fd, 'create')
      const allowUnbalanced = await resolveAllowUnbalanced(data.branchId, data.allowUnbalanced === true)
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
        allowUnbalanced,
        // When voucherApprovalRequired is ON, save as Pending; the Approve
        // action by a user with vouchers.approve will set it to Posted.
        status: fd.voucherApprovalRequired ? 'Pending' : undefined,
      })
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
    const existing = await (db as any)[delegate].findUnique({ where: { id } })
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
      const fd = await resolveFinanceDefaults(existing.branchId)
      validateVoucherDate(new Date(data.voucherDate || existing.voucherDate), fd, 'edit')
      // allowEditPostedVouchers: if OFF, posted vouchers cannot be edited
      if (!fd.allowEditPostedVouchers && existing.status === 'Posted') {
        return NextResponse.json({ error: 'Posted vouchers cannot be edited. Reverse the voucher and create a new one instead.' }, { status: 400 })
      }
      const allowUnbalanced = await resolveAllowUnbalanced(existing.branchId, data.allowUnbalanced === true)
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
        allowUnbalanced,
        existingVoucherId: id,
        // On edit, keep the existing status unless the caller overrides it
        status: data.status || (existing.status === 'Pending' ? 'Pending' : undefined),
      })
      return NextResponse.json({ voucher, difference: (voucher as any).difference ?? null })
    } catch (e: any) {
      return NextResponse.json({ error: e.message || 'Failed to update voucher' }, { status: 400 })
    }
  }

  // POST action ({ action: 'reverse' | 'delete' | 'approve', reason })
  async function action(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const session = await getSession()
    if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    const { id } = await params
    const data = await req.json()

    if (data.action === 'reverse') {
      if (!session.permissions.includes('vouchers.reverse')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
      const existing = await (db as any)[delegate].findUnique({ where: { id } })
      if (!existing) return NextResponse.json({ error: 'Voucher not found' }, { status: 404 })
      try {
        // Validate lockBeforeDate against the existing voucher's date
        const fd = await resolveFinanceDefaults(existing.branchId)
        validateVoucherDate(new Date(existing.voucherDate), fd, 'reverse')
        const reversalId = await reverseBookVoucher(id, existing.voucherType, session.id, data.reason || 'Manual reversal')
        return NextResponse.json({ success: true, reversalId })
      } catch (e: any) {
        return NextResponse.json({ error: e.message }, { status: 400 })
      }
    }

    // SOFT delete next to the Reverse option — never a physical delete.
    if (data.action === 'delete') {
      return softDelete(id, session, data.reason)
    }

    // APPROVE a Pending voucher — sets status to Posted.
    if (data.action === 'approve') {
      if (!session.permissions.includes('vouchers.approve')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
      const existing = await (db as any)[delegate].findUnique({ where: { id } })
      if (!existing) return NextResponse.json({ error: 'Voucher not found' }, { status: 404 })
      if (existing.status !== 'Pending') return NextResponse.json({ error: `Voucher is not Pending (current status: ${existing.status})` }, { status: 400 })
      try {
        await db.$transaction(async (tx) => {
          await (tx as any)[delegate].update({ where: { id }, data: { status: 'Posted' } })
          await (tx as any).auditLog.create({
            data: { userId: session.id, action: 'APPROVE', module: 'book-vouchers', details: JSON.stringify({ voucherId: id }) },
          })
        }, { timeout: 15000 })
        return NextResponse.json({ success: true, message: `Voucher ${id} approved` })
      } catch (e: any) {
        return NextResponse.json({ error: e.message || 'Failed to approve voucher' }, { status: 400 })
      }
    }

    return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
  }

  /**
   * SOFT delete: flags the voucher (isDeleted/deletedById/deletedAt) so it
   * disappears from lists, reports and ledgers; its reversal row (if any)
   * is flagged too so the pair never skews balances. Nothing is removed
   * from the database — lines stay for the audit trail.
   */
  async function softDelete(id: string, session: { id: string; permissions: string[] }, reason?: string) {
    if (!session.permissions.includes('vouchers.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    const existing = await (db as any)[delegate].findUnique({ where: { id } })
    if (!existing) return NextResponse.json({ error: 'Voucher not found' }, { status: 404 })
    if (existing.isDeleted) return NextResponse.json({ error: 'Voucher is already deleted' }, { status: 400 })
    try {
      // Validate lockBeforeDate against the existing voucher's date
      const fd = await resolveFinanceDefaults(existing.branchId)
      validateVoucherDate(new Date(existing.voucherDate), fd, 'delete')
      await db.$transaction(async (tx) => {
        await (tx as any)[delegate].update({
          where: { id },
          data: { isDeleted: true, deletedById: session.id, deletedAt: new Date() },
        })
        // flag the reversal row of this voucher (id ends with -R, reference = original id)
        const reversal = await (tx as any)[delegate].findFirst({ where: { OR: [{ id: `${id}-R` }, { reference: id, id: { endsWith: '-R' } }] } })
        if (reversal && !reversal.isDeleted) {
          await (tx as any)[delegate].update({
            where: { id: reversal.id },
            data: { isDeleted: true, deletedById: session.id, deletedAt: new Date() },
          })
        }
        await (tx as any).auditLog.create({
          data: { userId: session.id, action: 'SOFT_DELETE', module: 'book-vouchers', details: JSON.stringify({ voucherId: id, reason: reason || '' }) },
        })
      }, { timeout: 15000 })
      return NextResponse.json({ success: true, message: `Voucher ${id} deleted (soft)` })
    } catch (e: any) {
      return NextResponse.json({ error: e.message || 'Failed to delete voucher' }, { status: 400 })
    }
  }

  // DELETE — soft delete (never permanent); reason may come in the body
  async function remove(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
    const session = await getSession()
    if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
    const { id } = await params
    let reason = ''
    try { reason = (await req.json())?.reason || '' } catch { /* body optional */ }
    return softDelete(id, session, reason)
  }

  return { list, getOne, create, update, action, remove }
}

export const BOOK_VOUCHER_BOOK_TYPES = BOOK_TYPES
