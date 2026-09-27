import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { reverseVoucher, deleteVoucher, postDraftVoucher } from '@/lib/accounting'

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

  if (data.action === 'post') {
    if (!session.permissions.includes('vouchers.post')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    try {
      const v = await postDraftVoucher(id, session.id)
      return NextResponse.json({ voucher: v })
    } catch (e: any) {
      return NextResponse.json({ error: e.message }, { status: 400 })
    }
  }

  // Edit (update existing Draft voucher): action === 'edit'
  if (data.action === 'edit' || data.action === undefined) {
    if (!session.permissions.includes('vouchers.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
    // Edit is handled by re-calling postVoucher with existingVoucherId — caller should POST to /api/vouchers with existingVoucherId
    return NextResponse.json({ error: 'Use POST /api/vouchers with existingVoucherId to edit' }, { status: 400 })
  }

  return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
}

export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('vouchers.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const { id } = await params
  try {
    await deleteVoucher(id, session.id)
    return NextResponse.json({ success: true })
  } catch (e: any) {
    return NextResponse.json({ error: e.message }, { status: 400 })
  }
}
