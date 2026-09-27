import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const reportKey = url.searchParams.get('reportKey')
  const formats = await db.userReportFormat.findMany({
    where: { userId: session.id, ...(reportKey ? { reportKey } : {}) },
    orderBy: { isDefault: 'desc' },
  })
  return NextResponse.json({ formats })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const { reportKey, name, columns, isDefault } = await req.json()
  if (!reportKey || !name) return NextResponse.json({ error: 'reportKey and name required' }, { status: 400 })
  const format = await db.userReportFormat.create({
    data: {
      userId: session.id,
      reportKey,
      name,
      columns: JSON.stringify(columns || []),
      isDefault: !!isDefault,
    },
  })
  return NextResponse.json({ format })
}

export async function DELETE(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const id = url.searchParams.get('id')
  if (!id) return NextResponse.json({ error: 'id required' }, { status: 400 })
  const format = await db.userReportFormat.findUnique({ where: { id } })
  if (!format) return NextResponse.json({ error: 'Not found' }, { status: 404 })
  if (format.userId !== session.id && !session.isSuperAdmin) return NextResponse.json({ error: 'Cannot delete other users formats' }, { status: 403 })
  await db.userReportFormat.delete({ where: { id } })
  return NextResponse.json({ success: true })
}
