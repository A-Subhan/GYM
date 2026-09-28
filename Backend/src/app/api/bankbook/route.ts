import { bookVoucherApi } from '@/lib/book-voucher-api'

export const dynamic = 'force-dynamic'

// Bank book vouchers: BRV (Bank Receipt) | BPV (Bank Payment)
// Cheque payments also create Cheque rows (one per line with a cheque no).
const api = bookVoucherApi('BANKBOOK')
export const GET = api.list
export const POST = api.create
