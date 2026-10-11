// Compatibility layer — the generic Voucher system was replaced by four dedicated
// book tables (cashbook / bankbook / JV / opening TB). All posting logic now lives
// in book-vouchers.ts. Existing imports keep working through this re-export.

export {
  postBookVoucher,
  reverseBookVoucher,
  BILL_TYPES,
  sideForBillType,
  resolveSideForBillType,
  bookTypeFor,
  getChartBalance,
  getChartBalanceBetween,
  type BookVoucherType,
  type BookType,
  type PostBookVoucherInput,
  type BookLineInput,
} from './book-vouchers'

// Legacy compatibility aliases for routes that use the old function names
export { postBookVoucher as postVoucher } from './book-vouchers'
export { reverseBookVoucher as reverseVoucher } from './book-vouchers'

// Legacy list/find helpers — search across all four book tables
export async function listAllVouchers(opts: {
  voucherType?: string
  status?: string
  branchIds?: string[]
  from?: Date
  to?: Date
  search?: string
  take?: number
}) {
  const { db } = await import('./db')
  const filter: any = {
    ...(opts.status ? { status: opts.status } : {}),
    ...(opts.branchIds ? { branchId: { in: opts.branchIds } } : {}),
    ...((opts.from || opts.to) ? { voucherDate: { ...(opts.from ? { gte: opts.from } : {}), ...(opts.to ? { lte: opts.to } : {}) } } : {}),
    ...(opts.search ? { OR: [{ id: { contains: opts.search } }, { description: { contains: opts.search } }] } : {}),
  }
  const typeFilter = opts.voucherType ? { voucherType: opts.voucherType } : {}
  const take = opts.take || 200
  const [cash, bank, jv, otb] = await Promise.all([
    db.cashBook.findMany({ where: { ...filter, ...typeFilter, isDeleted: false }, include: { branch: true, lines: { include: { account: true } } }, orderBy: { voucherDate: 'desc' }, take }),
    db.bankBook.findMany({ where: { ...filter, ...typeFilter, isDeleted: false }, include: { branch: true, bookChart: true, lines: { include: { account: true } } }, orderBy: { voucherDate: 'desc' }, take }),
    db.journalVoucher.findMany({ where: { ...filter, ...typeFilter, isDeleted: false }, include: { branch: true, lines: { include: { account: true } } }, orderBy: { voucherDate: 'desc' }, take }),
    db.openingTbVoucher.findMany({ where: { ...filter, ...typeFilter, isDeleted: false }, include: { branch: true, lines: { include: { account: true } } }, orderBy: { voucherDate: 'desc' }, take }),
  ])
  return [...cash, ...bank, ...jv, ...otb].sort((a: any, b: any) => new Date(b.voucherDate).getTime() - new Date(a.voucherDate).getTime()).slice(0, take)
}

export async function findVoucherByNo(voucherNo: string): Promise<{ voucher: any; table: string } | null> {
  const { db } = await import('./db')
  const [cash, bank, jv, otb] = await Promise.all([
    db.cashBook.findUnique({ where: { id: voucherNo }, include: { branch: true, lines: { include: { account: true } } } }),
    db.bankBook.findUnique({ where: { id: voucherNo }, include: { branch: true, bookChart: true, lines: { include: { account: true } } } }),
    db.journalVoucher.findUnique({ where: { id: voucherNo }, include: { branch: true, lines: { include: { account: true } } } }),
    db.openingTbVoucher.findUnique({ where: { id: voucherNo }, include: { branch: true, lines: { include: { account: true } } } }),
  ])
  if (cash) return { voucher: cash, table: 'CashBook' }
  if (bank) return { voucher: bank, table: 'BankBook' }
  if (jv) return { voucher: jv, table: 'JV' }
  if (otb) return { voucher: otb, table: 'OpenTB' }
  return null
}
