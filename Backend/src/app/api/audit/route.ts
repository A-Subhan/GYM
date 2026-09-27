import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('audit.view')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const url = new URL(req.url)
  const module = url.searchParams.get('module')
  const action = url.searchParams.get('action')
  const from = url.searchParams.get('from')
  const to = url.searchParams.get('to')
  const userId = url.searchParams.get('userId')
  const logs = await db.auditLog.findMany({
    where: {
      ...(module ? { module } : {}),
      ...(action ? { action } : {}),
      ...(userId ? { userId } : {}),
      ...(from || to ? { createdAt: { ...(from ? { gte: new Date(from) } : {}), ...(to ? { lte: new Date(to) } : {}) } } : {}),
    },
    include: { user: { select: { username: true, fullName: true } } },
    orderBy: { createdAt: 'desc' },
    take: 200,
  })
  return NextResponse.json({ logs })
}
