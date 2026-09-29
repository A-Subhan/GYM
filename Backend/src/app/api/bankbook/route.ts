import { bookVoucherApi } from '@/lib/book-voucher-api'

export const dynamic = 'force-dynamic'

// Bank book vouchers: BRV (Bank Receipt) | BPV (Bank Payment)
// Cheque details (no / amount / bank / status) live on the BankBookLine rows.
const api = bookVoucherApi('BANKBOOK')
export const GET = api.list
export const POST = api.create
