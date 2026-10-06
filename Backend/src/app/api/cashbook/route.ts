import { bookVoucherApi } from '@/lib/book-voucher-api'

export const dynamic = 'force-dynamic'

// Cash book vouchers: CRV (Cash Receipt) | CPV (Cash Payment)
const api = bookVoucherApi('CASHBOOK')
export const GET = api.list
export const POST = api.create
