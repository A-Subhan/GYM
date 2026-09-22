import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'
import { getAccountBalanceBetween } from '@/lib/accounting'

// Available reports
const REPORTS = [
  { key: 'trial-balance', name: 'Trial Balance', filters: ['from', 'to', 'branches', 'bookType'] },
  { key: 'general-ledger', name: 'General Ledger', filters: ['from', 'to', 'branches', 'accountId'] },
  { key: 'account-ledger', name: 'Account Ledger', filters: ['from', 'to', 'accountId'] },
  { key: 'income-statement', name: 'Income Statement', filters: ['from', 'to', 'branches'] },
  { key: 'balance-sheet', name: 'Balance Sheet', filters: ['asOf', 'branches'] },
  { key: 'cash-book', name: 'Cash Book', filters: ['from', 'to', 'branches'] },
  { key: 'bank-book', name: 'Bank Book', filters: ['from', 'to', 'branches'] },
  { key: 'voucher-register', name: 'Voucher Register', filters: ['from', 'to', 'branches', 'voucherType'] },
  { key: 'tax-report', name: 'Tax Report', filters: ['from', 'to', 'branches'] },
]

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('finance.reports')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const url = new URL(req.url)
  const reportKey = url.searchParams.get('report')
  const from = url.searchParams.get('from') ? new Date(url.searchParams.get('from')!) : new Date(new Date().getFullYear(), 0, 1)
  const to = url.searchParams.get('to') ? new Date(url.searchParams.get('to')!) : new Date()
  const branchesParam = url.searchParams.get('branches')
  const allowed = getSelectedBranchIds(session, branchesParam)
  const accountId = url.searchParams.get('accountId')
  const voucherType = url.searchParams.get('voucherType')
  const bookType = url.searchParams.get('bookType')

  if (!reportKey) {
    return NextResponse.json({ reports: REPORTS })
  }

  // Generate report
  if (reportKey === 'trial-balance') {
    const accounts = await db.account.findMany({
      where: { isDetail: true, ...(allowed ? { branchId: { in: allowed } } : {}), ...(bookType ? { bookType } : {}) },
      include: { branch: true },
    })
    const rows: any[] = []
    let totalDebit = 0, totalCredit = 0
    for (const a of accounts) {
      const bal = await getAccountBalanceBetween(a.id, from, to)
      if (Math.abs(bal.balance) < 0.01) continue
      const debit = bal.balance > 0 ? bal.balance : 0
      const credit = bal.balance < 0 ? -bal.balance : 0
      totalDebit += debit
      totalCredit += credit
      rows.push({ code: a.code, name: a.name, type: a.accountType, debit, credit, balance: bal.balance })
    }
    return NextResponse.json({ report: { title: 'Trial Balance', from, to, rows, totalDebit, totalCredit, balanced: Math.abs(totalDebit - totalCredit) < 0.01 } })
  }

  if (reportKey === 'general-ledger' || reportKey === 'account-ledger') {
    const accountWhere = accountId ? { id: accountId } : { isDetail: true, ...(allowed ? { branchId: { in: allowed } } : {}) }
    const accounts = await db.account.findMany({ where: accountWhere, include: { branch: true } })
    const result: any[] = []
    for (const a of accounts) {
      const lines = await db.voucherLine.findMany({
        where: { accountId: a.id, voucher: { status: 'Posted', voucherDate: { gte: from, lte: to } } },
        include: { voucher: true },
        orderBy: { voucher: { voucherDate: 'asc' } },
      })
      if (!lines.length) continue
      const opening = await getAccountBalanceBetween(a.id, new Date(0), from)
      let running = opening.balance
      const rows = lines.map(l => {
        running += (l.debit - l.credit)
        return { date: l.voucher.voucherDate, voucherNo: l.voucher.voucherNo, type: l.voucher.voucherType, description: l.lineDescription || l.voucher.description, debit: l.debit, credit: l.credit, balance: running }
      })
      result.push({ account: { code: a.code, name: a.name }, openingBalance: opening.balance, rows, closingBalance: running })
    }
    return NextResponse.json({ report: { title: reportKey === 'account-ledger' ? 'Account Ledger' : 'General Ledger', from, to, accounts: result } })
  }

  if (reportKey === 'income-statement') {
    const revenueAccounts = await db.account.findMany({ where: { accountType: 'Revenue', isDetail: true, ...(allowed ? { branchId: { in: allowed } } : {}) } })
    const expenseAccounts = await db.account.findMany({ where: { accountType: 'Expense', isDetail: true, ...(allowed ? { branchId: { in: allowed } } : {}) } })
    const revenues: any[] = []
    const expenses: any[] = []
    let totalRevenue = 0, totalExpense = 0
    for (const a of revenueAccounts) {
      const bal = await getAccountBalanceBetween(a.id, from, to)
      // Revenue is credit-normal → balance should be negative normally (credits)
      const amount = -bal.balance
      if (Math.abs(amount) < 0.01) continue
      revenues.push({ code: a.code, name: a.name, amount })
      totalRevenue += amount
    }
    for (const a of expenseAccounts) {
      const bal = await getAccountBalanceBetween(a.id, from, to)
      const amount = bal.balance
      if (Math.abs(amount) < 0.01) continue
      expenses.push({ code: a.code, name: a.name, amount })
      totalExpense += amount
    }
    return NextResponse.json({ report: { title: 'Income Statement', from, to, revenues, expenses, totalRevenue, totalExpense, netProfit: totalRevenue - totalExpense } })
  }

  if (reportKey === 'balance-sheet') {
    const asOf = url.searchParams.get('asOf') ? new Date(url.searchParams.get('asOf')!) : new Date()
    const assetAccounts = await db.account.findMany({ where: { accountType: 'Asset', isDetail: true, ...(allowed ? { branchId: { in: allowed } } : {}) } })
    const liabilityAccounts = await db.account.findMany({ where: { accountType: 'Liability', isDetail: true, ...(allowed ? { branchId: { in: allowed } } : {}) } })
    const equityAccounts = await db.account.findMany({ where: { accountType: 'Equity', isDetail: true, ...(allowed ? { branchId: { in: allowed } } : {}) } })
    const rows: any = { assets: [], liabilities: [], equity: [] }
    let totalAssets = 0, totalLiabilities = 0, totalEquity = 0
    for (const a of assetAccounts) {
      const bal = await getAccountBalanceBetween(a.id, new Date(0), asOf)
      const amount = bal.balance
      if (Math.abs(amount) < 0.01) continue
      rows.assets.push({ code: a.code, name: a.name, amount })
      totalAssets += amount
    }
    for (const a of liabilityAccounts) {
      const bal = await getAccountBalanceBetween(a.id, new Date(0), asOf)
      const amount = -bal.balance
      if (Math.abs(amount) < 0.01) continue
      rows.liabilities.push({ code: a.code, name: a.name, amount })
      totalLiabilities += amount
    }
    for (const a of equityAccounts) {
      const bal = await getAccountBalanceBetween(a.id, new Date(0), asOf)
      const amount = -bal.balance
      if (Math.abs(amount) < 0.01) continue
      rows.equity.push({ code: a.code, name: a.name, amount })
      totalEquity += amount
    }
    return NextResponse.json({ report: { title: 'Balance Sheet', asOf, rows, totalAssets, totalLiabilities, totalEquity, balanced: Math.abs(totalAssets - (totalLiabilities + totalEquity)) < 0.01 } })
  }

  if (reportKey === 'voucher-register') {
    const vouchers = await db.voucher.findMany({
      where: { status: 'Posted', voucherDate: { gte: from, lte: to }, ...(allowed ? { branchId: { in: allowed } } : {}), ...(voucherType ? { voucherType } : {}) },
      include: { branch: true, lines: true },
      orderBy: { voucherDate: 'desc' },
    })
    return NextResponse.json({ report: { title: 'Voucher Register', from, to, vouchers } })
  }

  if (reportKey === 'cash-book' || reportKey === 'bank-book') {
    const bookTypeFilter = reportKey === 'cash-book' ? 'Cash' : 'Bank'
    const accounts = await db.account.findMany({ where: { bookType: bookTypeFilter, isDetail: true, ...(allowed ? { branchId: { in: allowed } } : {}) } })
    const result: any[] = []
    for (const a of accounts) {
      const bal = await getAccountBalanceBetween(a.id, from, to)
      const lines = await db.voucherLine.findMany({
        where: { accountId: a.id, voucher: { status: 'Posted', voucherDate: { gte: from, lte: to } } },
        include: { voucher: true },
        orderBy: { voucher: { voucherDate: 'asc' } },
      })
      if (!lines.length && Math.abs(bal.balance) < 0.01) continue
      result.push({ account: a, opening: bal.opening, lines: lines.map(l => ({ date: l.voucher.voucherDate, voucherNo: l.voucher.voucherNo, description: l.lineDescription || l.voucher.description, debit: l.debit, credit: l.credit })), closing: bal.balance })
    }
    return NextResponse.json({ report: { title: reportKey === 'cash-book' ? 'Cash Book' : 'Bank Book', from, to, accounts: result } })
  }

  if (reportKey === 'tax-report') {
    const lines = await db.voucherLine.findMany({
      where: { taxAmount: { gt: 0 }, voucher: { status: 'Posted', voucherDate: { gte: from, lte: to }, ...(allowed ? { branchId: { in: allowed } } : {}) } },
      include: { voucher: { include: { branch: true } }, account: true },
    })
    return NextResponse.json({ report: { title: 'Tax Report', from, to, lines: lines.map(l => ({ date: l.voucher.voucherDate, voucherNo: l.voucher.voucherNo, branch: l.voucher.branch.name, account: l.account.name, taxableAmount: l.debit + l.credit, taxAmount: l.taxAmount, taxRate: l.taxRate })) } })
  }

  return NextResponse.json({ error: 'Unknown report' }, { status: 400 })
}
