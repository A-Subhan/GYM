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
