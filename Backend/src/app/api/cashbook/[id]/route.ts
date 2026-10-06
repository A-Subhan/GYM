import { bookVoucherApi } from '@/lib/book-voucher-api'

export const dynamic = 'force-dynamic'

// Single cash book voucher: GET / PATCH (edit) / POST (reverse) / DELETE (rejected)
const api = bookVoucherApi('CASHBOOK')
export const GET = api.getOne
export const PATCH = api.update
export const POST = api.action
export const DELETE = api.remove
