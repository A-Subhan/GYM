import { bookVoucherApi } from '@/lib/book-voucher-api'

export const dynamic = 'force-dynamic'

// Opening Trial Balance vouchers (OTV) — may be saved unbalanced
// (difference is stored and can be knocked off later via /api/knock-offs)
const api = bookVoucherApi('OTB')
export const GET = api.list
export const POST = api.create
