import { bookVoucherApi } from '@/lib/book-voucher-api'

export const dynamic = 'force-dynamic'

// Journal vouchers (JV) — manual Debit/Credit lines, must balance
const api = bookVoucherApi('JV')
export const GET = api.list
export const POST = api.create
