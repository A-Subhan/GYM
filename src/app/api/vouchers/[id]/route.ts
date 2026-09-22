import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { reverseVoucher } from '@/lib/accounting'

export async function GET(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const { id } = await params
  const voucher = await db.voucher.findUnique({
    where: { id },
    include: { branch: true, bookAccount: true, lines: { include: { account: true } }, cheques: true, fees: true, payrolls: true },
  })
  if (!voucher) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  return NextResponse.json({ voucher })
}

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const { id } = await params
  const data = await req.json()
  if (data.action === 'reverse') {
    if (!session.permissions.includes('vouchers.reverse')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    try {
      const v = await reverseVoucher(id, session.id, data.reason || 'Manual reversal')
      return NextResponse.json({ voucher: v })
    } catch (e: any) {
      return NextResponse.json({ error: e.message }, { status: 400 })
    }
  }
  return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
}
