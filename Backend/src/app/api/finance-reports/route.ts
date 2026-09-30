import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'

// Available reports
const REPORTS = [
  { key: 'trial-balance', name: 'Trial Balance', filters: ['from', 'to', 'branches', 'bookType'] },
  { key: 'ledger', name: 'Ledger', filters: ['from', 'to', 'branches', 'accountId'] },
  { key: 'general-ledger', name: 'General Ledger', filters: ['from', 'to', 'branches', 'accountId'] },
  { key: 'account-ledger', name: 'Account Ledger', filters: ['from', 'to', 'accountId'] },
  { key: 'income-statement', name: 'Income Statement', filters: ['from', 'to', 'branches'] },
  { key: 'balance-sheet', name: 'Balance Sheet', filters: ['asOf', 'branches'] },
  { key: 'cash-book', name: 'Cash Book', filters: ['from', 'to', 'branches'] },
  { key: 'bank-book', name: 'Bank Book', filters: ['from', 'to', 'branches'] },
  { key: 'voucher-register', name: 'Voucher Register', filters: ['from', 'to', 'branches', 'voucherType'] },
  { key: 'day-book', name: 'Day Book', filters: ['from', 'to', 'branches'] },
  { key: 'tax-report', name: 'Tax Report', filters: ['from', 'to', 'branches'] },
  { key: 'aging', name: 'Aging', filters: ['asOf', 'branches'] },
  { key: 'customer-aging', name: 'Customer Aging', filters: ['asOf', 'branches'] },
  { key: 'vendor-aging', name: 'Vendor Aging', filters: ['asOf', 'branches'] },
]

type PostedLine = {
  date: Date
  voucherNo: string
  type: string
  bookType: string
  branchId: string
  description: string | null
  debit: number
  credit: number
  taxAmount: number
  taxRate: number
  accountName?: string
  accountCode?: string
}

function r2(n: number): number {
  return Math.round(Number(n || 0) * 100) / 100
}

/** All Active voucher lines (with parent voucher info) for one account, from Posted vouchers only. */
async function postedLinesForAccount(accountId: string): Promise<PostedLine[]> {
  const voucherSelect = { id: true, voucherType: true, voucherDate: true, branchId: true, status: true, description: true }
  // Four separate line tables (final schema) — union them per account
  const [cashLines, bankLines, jvLines, otbLines] = await Promise.all([
    db.cashBookLine.findMany({
      where: { accountId, status: 'Active', voucher: { status: 'Posted', isDeleted: false } },
      include: { voucher: { select: voucherSelect } },
    }),
    db.bankBookLine.findMany({
      where: { accountId, status: 'Active', voucher: { status: 'Posted', isDeleted: false } },
      include: { voucher: { select: voucherSelect } },
    }),
    db.journalVoucherLine.findMany({
      where: { accountId, status: 'Active', voucher: { status: 'Posted', isDeleted: false } },
      include: { voucher: { select: voucherSelect } },
    }),
    db.openingTbLine.findMany({
      where: { accountId, status: 'Active', voucher: { status: 'Posted', isDeleted: false } },
      include: { voucher: { select: voucherSelect } },
    }),
  ])
  const out: PostedLine[] = []
  const push = (l: any, bookType: string) => {
    const v = l.voucher
    if (!v || v.status !== 'Posted') return
    out.push({
      date: v.voucherDate,
      voucherNo: v.id,
      type: v.voucherType,
      bookType,
      branchId: v.branchId,
      description: l.lineDescription || v.description,
      debit: l.debit,
      credit: l.credit,
      taxAmount: l.taxAmount ?? 0,
      taxRate: l.taxPercent ?? 0,
    })
  }
  for (const l of cashLines) push(l, 'CASHBOOK')
  for (const l of bankLines) push(l, 'BANKBOOK')
  for (const l of jvLines) push(l, 'JV')
  for (const l of otbLines) push(l, 'OTB')
  out.sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime())
  return out
}

/** Union of all Posted book vouchers (any of the 4 stores) in a range, normalized. */
async function postedVouchers(opts: { from?: Date; to?: Date; allowed?: string[] | null; voucherType?: string; branchId?: string } = {}) {
  const dateFilter = opts.from || opts.to
    ? { voucherDate: { ...(opts.from ? { gte: opts.from } : {}), ...(opts.to ? { lte: opts.to } : {}) } }
    : {}
  const branchFilter = {
    ...(opts.allowed ? { branchId: { in: opts.allowed } } : {}),
    ...(opts.branchId && opts.branchId !== 'all' ? { branchId: opts.branchId } : {}),
  }
  const select = { id: true, voucherType: true, voucherDate: true, branchId: true, description: true, reference: true, status: true, branch: true }
  const [cash, bank, jv, otb] = await Promise.all([
    db.cashBook.findMany({ where: { status: 'Posted', isDeleted: false, ...dateFilter, ...branchFilter, ...(opts.voucherType ? { voucherType: opts.voucherType } : {}) }, select: { ...select, totalAmount: true } }),
    db.bankBook.findMany({ where: { status: 'Posted', isDeleted: false, ...dateFilter, ...branchFilter, ...(opts.voucherType ? { voucherType: opts.voucherType } : {}) }, select: { ...select, totalAmount: true } }),
    db.journalVoucher.findMany({ where: { status: 'Posted', isDeleted: false, ...dateFilter, ...branchFilter, ...(opts.voucherType ? { voucherType: opts.voucherType } : {}) }, select: { ...select, totalDebit: true, totalCredit: true } }),
    db.openingTbVoucher.findMany({ where: { status: 'Posted', isDeleted: false, ...dateFilter, ...branchFilter, ...(opts.voucherType ? { voucherType: opts.voucherType } : {}) }, select: { ...select, totalDebit: true, totalCredit: true, difference: true, isBalanced: true } }),
  ])
  const rows: any[] = []
  for (const v of cash) {
    rows.push({
      voucherNo: v.id, id: v.id, voucherType: v.voucherType, voucherDate: v.voucherDate,
      branch: v.branch, description: v.description, reference: v.reference, status: v.status,
      totalDebit: (v as any).totalAmount, totalCredit: (v as any).totalAmount, totalAmount: (v as any).totalAmount,
      bookType: 'CASHBOOK', store: 'CASHBOOK',
    })
  }
  for (const v of bank) {
    rows.push({
      voucherNo: v.id, id: v.id, voucherType: v.voucherType, voucherDate: v.voucherDate,
      branch: v.branch, description: v.description, reference: v.reference, status: v.status,
      totalDebit: (v as any).totalAmount, totalCredit: (v as any).totalAmount, totalAmount: (v as any).totalAmount,
      bookType: 'BANKBOOK', store: 'BANKBOOK',
    })
  }
  for (const v of jv) {
    rows.push({
      voucherNo: v.id, id: v.id, voucherType: v.voucherType, voucherDate: v.voucherDate,
      branch: v.branch, description: v.description, reference: v.reference, status: v.status,
      totalDebit: (v as any).totalDebit, totalCredit: (v as any).totalCredit, bookType: 'JV', store: 'JV',
    })
  }
  for (const v of otb) {
    rows.push({
      voucherNo: v.id, id: v.id, voucherType: v.voucherType, voucherDate: v.voucherDate,
      branch: v.branch, description: v.description, reference: v.reference, status: v.status,
      totalDebit: (v as any).totalDebit, totalCredit: (v as any).totalCredit, difference: (v as any).difference, isBalanced: (v as any).isBalanced, bookType: 'OTB', store: 'OTB',
    })
  }
  rows.sort((a, b) => new Date(b.voucherDate).getTime() - new Date(a.voucherDate).getTime())
  return rows
}

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('finance.reports')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const url = new URL(req.url)
  const reportKey = url.searchParams.get('report')
  const from = url.searchParams.get('from') ? new Date(url.searchParams.get('from')!) : new Date(new Date().getFullYear(), 0, 1)
  const to = url.searchParams.get('to') ? new Date(url.searchParams.get('to')!) : new Date()
  const asOfParam = url.searchParams.get('asOf') ? new Date(url.searchParams.get('asOf')!) : new Date()
  const branchesParam = url.searchParams.get('branches')
  const allowed = getSelectedBranchIds(session, branchesParam)
  const accountId = url.searchParams.get('accountId')
  const voucherType = url.searchParams.get('voucherType')
  const bookType = url.searchParams.get('bookType')

  if (!reportKey) {
    return NextResponse.json({ reports: REPORTS })
  }

  // ---------- Trial Balance (all detail accounts, cumulative to `to`) ----------
  if (reportKey === 'trial-balance') {
    const charts = await db.chart.findMany({
      where: { isDetail: true, ...(allowed ? { OR: [{ branchId: { in: allowed } }, { branchId: null }] } : {}), ...(bookType && bookType !== 'all' ? { bookType } : {}) },
      include: { branch: true },
      orderBy: { id: 'asc' },
    })
    const rows: any[] = []
    let totalDebit = 0, totalCredit = 0
    for (const a of charts) {
      const lines = await postedLinesForAccount(a.id)
      const upto = lines.filter(l => new Date(l.date).getTime() <= to.getTime())
      const debit = r2(upto.reduce((s, l) => s + l.debit, 0))
      const credit = r2(upto.reduce((s, l) => s + l.credit, 0))
      const balance = r2(debit - credit)
      if (Math.abs(balance) < 0.01) continue
      const dr = balance > 0 ? balance : 0
      const cr = balance < 0 ? -balance : 0
      totalDebit += dr
      totalCredit += cr
      rows.push({ code: a.id, name: a.name, type: a.accountType, debit: dr, credit: cr, balance })
    }
    return NextResponse.json({ report: { title: 'Trial Balance', from, to, rows, totalDebit: r2(totalDebit), totalCredit: r2(totalCredit), balanced: Math.abs(totalDebit - totalCredit) < 0.01 } })
  }

  // ---------- Ledger / General Ledger / Account Ledger ----------
  if (reportKey === 'ledger' || reportKey === 'general-ledger' || reportKey === 'account-ledger') {
    const accountWhere = accountId
      ? { id: accountId }
      : { isDetail: true, ...(allowed ? { OR: [{ branchId: { in: allowed } }, { branchId: null }] } : {}) }
    const charts = await db.chart.findMany({ where: accountWhere, orderBy: { id: 'asc' } })
    const result: any[] = []
    for (const a of charts) {
      const all = await postedLinesForAccount(a.id)
      const opening = r2(all.filter(l => new Date(l.date).getTime() < from.getTime()).reduce((s, l) => s + l.debit - l.credit, 0))
      const period = all.filter(l => new Date(l.date).getTime() >= from.getTime() && new Date(l.date).getTime() <= to.getTime())
      if (!period.length) continue
      let running = opening
      const rows = period.map(l => {
        running = r2(running + l.debit - l.credit)
        return { date: l.date, voucherNo: l.voucherNo, type: l.type, description: l.description, debit: l.debit, credit: l.credit, balance: running }
      })
      result.push({ account: { code: a.id, name: a.name }, openingBalance: opening, rows, closingBalance: running })
    }
    return NextResponse.json({ report: { title: reportKey === 'account-ledger' ? 'Account Ledger' : reportKey === 'ledger' ? 'Ledger' : 'General Ledger', from, to, accounts: result } })
  }

  // ---------- Income Statement (period movement) ----------
  if (reportKey === 'income-statement') {
    const branchScope = allowed ? { OR: [{ branchId: { in: allowed } }, { branchId: null }] } : {}
    const revenueAccounts = await db.chart.findMany({ where: { accountType: 'Revenue', isDetail: true, ...branchScope }, orderBy: { id: 'asc' } })
    const expenseAccounts = await db.chart.findMany({ where: { accountType: 'Expense', isDetail: true, ...branchScope }, orderBy: { id: 'asc' } })
    const revenues: any[] = []
    const expenses: any[] = []
    let totalRevenue = 0, totalExpense = 0
    for (const a of revenueAccounts) {
      const period = (await postedLinesForAccount(a.id)).filter(l => l.date >= from && l.date <= to)
      const amount = r2(period.reduce((s, l) => s + l.credit - l.debit, 0)) // revenue is credit-normal
      if (Math.abs(amount) < 0.01) continue
      revenues.push({ code: a.id, name: a.name, amount })
      totalRevenue += amount
    }
    for (const a of expenseAccounts) {
      const period = (await postedLinesForAccount(a.id)).filter(l => l.date >= from && l.date <= to)
      const amount = r2(period.reduce((s, l) => s + l.debit - l.credit, 0)) // expense is debit-normal
      if (Math.abs(amount) < 0.01) continue
      expenses.push({ code: a.id, name: a.name, amount })
      totalExpense += amount
    }
    return NextResponse.json({ report: { title: 'Income Statement', from, to, revenues, expenses, totalRevenue: r2(totalRevenue), totalExpense: r2(totalExpense), netProfit: r2(totalRevenue - totalExpense) } })
  }

  // ---------- Balance Sheet (cumulative to asOf) ----------
  if (reportKey === 'balance-sheet') {
    const asOf = asOfParam
    const branchScope = allowed ? { OR: [{ branchId: { in: allowed } }, { branchId: null }] } : {}
    const groups: Array<{ type: string; key: 'assets' | 'liabilities' | 'equity' }> = [
      { type: 'Asset', key: 'assets' },
      { type: 'Liability', key: 'liabilities' },
      { type: 'Equity', key: 'equity' },
    ]
    const rows: any = { assets: [], liabilities: [], equity: [] }
    let totalAssets = 0, totalLiabilities = 0, totalEquity = 0
    for (const g of groups) {
      const charts = await db.chart.findMany({ where: { accountType: g.type, isDetail: true, ...branchScope }, orderBy: { id: 'asc' } })
      for (const a of charts) {
        const upto = (await postedLinesForAccount(a.id)).filter(l => new Date(l.date).getTime() <= asOf.getTime())
        const balance = r2(upto.reduce((s, l) => s + l.debit - l.credit, 0))
        const amount = g.key === 'assets' ? balance : -balance // liabilities/equity are credit-normal
        if (Math.abs(amount) < 0.01) continue
        rows[g.key].push({ code: a.id, name: a.name, amount })
        if (g.key === 'assets') totalAssets += amount
        else if (g.key === 'liabilities') totalLiabilities += amount
        else totalEquity += amount
      }
    }
    return NextResponse.json({ report: { title: 'Balance Sheet', asOf, rows, totalAssets: r2(totalAssets), totalLiabilities: r2(totalLiabilities), totalEquity: r2(totalEquity), balanced: Math.abs(totalAssets - (totalLiabilities + totalEquity)) < 0.01 } })
  }

  // ---------- Voucher Register / Day Book ----------
  if (reportKey === 'voucher-register' || reportKey === 'day-book') {
    const vouchers = await postedVouchers({ from, to, allowed, voucherType: voucherType || undefined })
    if (reportKey === 'voucher-register') {
      return NextResponse.json({ report: { title: 'Voucher Register', from, to, vouchers: vouchers.map(({ store, ...rest }: any) => rest) } })
    }
    // Day Book: group by bookType with lines
    const STORE_TABLE: Record<string, string> = {
      CASHBOOK: 'cashBook', BANKBOOK: 'bankBook', JV: 'journalVoucher', OTB: 'openingTbVoucher',
    }
    const groupsMap: Record<string, any[]> = { CASHBOOK: [], BANKBOOK: [], JV: [], OTB: [] }
    for (const v of vouchers) {
      const full: any = await (db as any)[STORE_TABLE[v.store]].findUnique({
        where: { id: v.id },
        include: { lines: { include: { account: true } } },
      })
      if (!full) continue
      groupsMap[v.store].push({
        voucherNo: v.id, voucherType: v.voucherType, voucherDate: v.voucherDate,
        branch: v.branch?.name, description: v.description, totalDebit: v.totalDebit, totalCredit: v.totalCredit,
        paymentMode: (full as any).paymentMode || null,
        lines: (full as any).lines.map((l: any) => ({ account: `${l.account.id} — ${l.account.name}`, lineDescription: l.lineDescription, debit: l.debit, credit: l.credit })),
      })
    }
    const groups = Object.entries(groupsMap).map(([bookTypeKey, list]) => ({ bookType: bookTypeKey, vouchers: list }))
    return NextResponse.json({ report: { title: 'Day Book', from, to, groups } })
  }

  // ---------- Cash Book / Bank Book ----------
  if (reportKey === 'cash-book' || reportKey === 'bank-book') {
    const bookFilter = reportKey === 'cash-book' ? 'Cash' : 'Bank'
    const charts = await db.chart.findMany({
      where: { bookType: bookFilter, isDetail: true, ...(allowed ? { OR: [{ branchId: { in: allowed } }, { branchId: null }] } : {}) },
      orderBy: { id: 'asc' },
    })
    const result: any[] = []
    for (const a of charts) {
      const all = await postedLinesForAccount(a.id)
      const opening = r2(all.filter(l => new Date(l.date).getTime() < from.getTime()).reduce((s, l) => s + l.debit - l.credit, 0))
      const period = all.filter(l => new Date(l.date).getTime() >= from.getTime() && new Date(l.date).getTime() <= to.getTime())
      if (!period.length && Math.abs(opening) < 0.01) continue
      const closing = r2(all.filter(l => new Date(l.date).getTime() <= to.getTime()).reduce((s, l) => s + l.debit - l.credit, 0))
      result.push({
        account: { code: a.id, name: a.name, bookType: a.bookType },
        opening,
        lines: period.map(l => ({ date: l.date, voucherNo: l.voucherNo, type: l.type, description: l.description, debit: l.debit, credit: l.credit })),
        closing,
      })
    }
    return NextResponse.json({ report: { title: reportKey === 'cash-book' ? 'Cash Book' : 'Bank Book', from, to, accounts: result } })
  }

  // ---------- Tax Report ----------
  if (reportKey === 'tax-report') {
    // Tax data lives inline on the book lines (taxPercent/taxAmount) — union all four line tables
    const lineQueries = [
      db.cashBookLine.findMany({ where: { taxAmount: { gt: 0 }, status: 'Active' }, include: { account: true, voucher: { include: { branch: true } } }, take: 5000 }),
      db.bankBookLine.findMany({ where: { taxAmount: { gt: 0 }, status: 'Active' }, include: { account: true, voucher: { include: { branch: true } } }, take: 5000 }),
      db.journalVoucherLine.findMany({ where: { taxAmount: { gt: 0 }, status: 'Active' }, include: { account: true, voucher: { include: { branch: true } } }, take: 5000 }),
    ]
    const allLines = (await Promise.all(lineQueries)).flat()
    const rows = allLines
      .map((l: any) => {
        const v = l.voucher
        if (!v || v.status !== 'Posted') return null
        if (v.voucherDate < from || v.voucherDate > to) return null
        if (allowed && !allowed.includes(v.branchId)) return null
        return {
          date: v.voucherDate, voucherNo: v.id, branch: v.branch?.name,
          account: l.account.name, taxableAmount: r2(l.debit + l.credit), taxAmount: l.taxAmount, taxRate: l.taxPercent,
        }
      })
      .filter(Boolean)
    return NextResponse.json({ report: { title: 'Tax Report', from, to, rows } })
  }

  // ---------- Aging (fee-based customer aging + vendor aging) ----------
  if (reportKey === 'aging' || reportKey === 'customer-aging' || reportKey === 'vendor-aging') {
    const asOf = asOfParam
    if (reportKey === 'vendor-aging') {
      const purchases = await db.purchase.findMany({
        where: { status: { in: ['Pending', 'Received'] }, ...(allowed ? { branchId: { in: allowed } } : {}) },
        include: { supplier: true },
        orderBy: { purchaseDate: 'asc' },
        take: 1000,
      })
      const bucket = (days: number) => (days <= 30 ? '0-30' : days <= 60 ? '31-60' : days <= 90 ? '61-90' : '90+')
      const rows = purchases.map(p => {
        const daysPastDue = Math.max(0, Math.floor((asOf.getTime() - new Date(p.purchaseDate).getTime()) / 86400000))
        return {
          supplier: p.supplier?.name || '—',
          purchaseNo: p.purchaseNo,
          purchaseDate: p.purchaseDate,
          amount: p.totalAmount,
          outstanding: p.totalAmount,
          daysPastDue,
          bucket: bucket(daysPastDue),
        }
      })
      const summary: Record<string, number> = { '0-30': 0, '31-60': 0, '61-90': 0, '90+': 0 }
      rows.forEach(r => { summary[r.bucket] = r2((summary[r.bucket] || 0) + r.outstanding) })
      return NextResponse.json({ report: { title: 'Vendor Aging', asOf, rows, summary } })
    }
    const fees = await db.fee.findMany({
      where: { balance: { gt: 0.01 }, status: { in: ['Unpaid', 'Partial', 'Late', 'Overdue'] }, ...(allowed ? { branchId: { in: allowed } } : {}) },
      include: { member: true },
      orderBy: { dueDate: 'asc' },
      take: 1000,
    })
    const bucket = (days: number) => (days <= 30 ? '0-30' : days <= 60 ? '31-60' : days <= 90 ? '61-90' : '90+')
    const rows = fees.map(f => {
      const daysPastDue = Math.max(0, Math.floor((asOf.getTime() - new Date(f.dueDate).getTime()) / 86400000))
      return {
        member: `${f.member.firstName} ${f.member.lastName || ''}`.trim(),
        memberId: f.member.id,
        feeNo: f.id,
        dueDate: f.dueDate,
        amount: f.amount,
        balance: f.balance,
        daysPastDue,
        bucket: bucket(daysPastDue),
      }
    })
    const summary: Record<string, number> = { '0-30': 0, '31-60': 0, '61-90': 0, '90+': 0 }
    rows.forEach(r => { summary[r.bucket] = r2((summary[r.bucket] || 0) + r.balance) })
    return NextResponse.json({ report: { title: reportKey === 'aging' ? 'Aging' : 'Customer Aging', asOf, rows, summary } })
  }

  return NextResponse.json({ error: 'Unknown report' }, { status: 400 })
}
