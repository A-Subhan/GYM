import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const branchId = url.searchParams.get('branchId')
  const allowed = session.accessibleBranchIds === '*' ? null : session.accessibleBranchIds.split(',')
  const taxHeads = await db.taxHead.findMany({
    where: {
      ...(branchId && branchId !== 'all' ? { OR: [{ branchId }, { branchId: null }] } : {}),
      ...(allowed ? { OR: [{ branchId: { in: allowed } }, { branchId: null }] } : {}),
    },
    orderBy: { code: 'asc' },
  })
  return NextResponse.json({ taxHeads })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('tax.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.name || !data.shortName) return NextResponse.json({ error: 'Name and short name required' }, { status: 400 })
  // auto-generate code as 001, 002, ...
  const branchId = data.branchId || session.branchId
  const existing = await db.taxHead.findMany({ where: { branchId: branchId || null } })
  const existingCodes = existing.map(t => parseInt(t.code, 10)).filter(n => !isNaN(n))
  const nextCode = (existingCodes.length ? Math.max(...existingCodes) : 0) + 1
  const code = String(nextCode).padStart(3, '0')
  const taxHead = await db.taxHead.create({
    data: {
      code,
      shortName: data.shortName,
      name: data.name,
      taxType: data.taxType || 'Sales',
      rate: Number(data.rate) || 0,
      branchId: branchId || null,
      isActive: data.isActive !== false,
    },
  })
  await db.auditLog.create({
    data: { userId: session.id, action: 'CREATE', module: 'tax', details: JSON.stringify({ id: taxHead.id, code }) },
  })
  return NextResponse.json({ taxHead })
}
