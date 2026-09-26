import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'
import { postVoucher, listAllVouchers } from '@/lib/accounting'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const voucherType = url.searchParams.get('voucherType')
  const status = url.searchParams.get('status')
  const branchesParam = url.searchParams.get('branches')
  const from = url.searchParams.get('from')
  const to = url.searchParams.get('to')
  const search = url.searchParams.get('q')
  const allowed = getSelectedBranchIds(session, branchesParam)

  const vouchers = await listAllVouchers({
    ...(voucherType ? { voucherType } : {}),
    ...(status ? { status } : {}),
    ...(allowed ? { branchIds: allowed } : {}),
    ...(from || to ? { from: from ? new Date(from) : undefined, to: to ? new Date(to) : undefined } : {}),
    ...(search ? { search } : {}),
    take: 200,
  })
  return NextResponse.json({ vouchers })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('vouchers.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  const { voucherType, voucherDate, branchId, bookAccountId, description, reference, lines, status } = data

  if (!voucherType || !voucherDate || !branchId || !lines?.length) {
    return NextResponse.json({ error: 'Missing required fields' }, { status: 400 })
  }

  // Validate branch exists
  const branch = await db.branch.findUnique({ where: { id: branchId } })
  if (!branch) return NextResponse.json({ error: 'Invalid branch' }, { status: 400 })

  try {
    const voucher = await postVoucher({
      voucherType,
      voucherDate: new Date(voucherDate),
      branchId,
      bookAccountId: bookAccountId || null,
      description,
      reference,
      lines: lines.map((l: any) => ({
        accountId: l.accountId,
        amount: Number(l.amount) || 0,
        debit: Number(l.debit) || 0,
        credit: Number(l.credit) || 0,
        lineDescription: l.lineDescription,
        taxAccountId: l.taxAccountId || null,
        taxRate: Number(l.taxRate) || 0,
        taxAmount: Number(l.taxAmount) || 0,
        chequeNo: l.chequeNo,
        chequeAmount: l.chequeAmount ? Number(l.chequeAmount) : undefined,
        chequeBankName: l.chequeBankName,
        chequeStatus: l.chequeStatus,
        status: l.status || 'Active',
      })),
      postedById: session.id,
      status: status || 'Posted',
    })
    return NextResponse.json({ voucher })
  } catch (e: any) {
    return NextResponse.json({ error: e.message || 'Failed to post voucher' }, { status: 400 })
  }
}
