import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const branchId = url.searchParams.get('branchId')
  const mappings = await db.accountMapping.findMany({
    where: { ...(branchId ? { OR: [{ branchId }, { branchId: null }] } : {}) },
    include: { account: true },
  })
  return NextResponse.json({ mappings })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('accountMappings.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.key || !data.accountId) return NextResponse.json({ error: 'key and accountId required' }, { status: 400 })
  // Validate account type matches key
  const account = await db.charts.findUnique({ where: { id: data.accountId } })
  if (!account) return NextResponse.json({ error: 'Invalid account' }, { status: 400 })

  const existing = data.branchId
    ? await db.accountMapping.findUnique({ where: { branchId_key: { branchId: data.branchId, key: data.key } } })
    : await db.accountMapping.findFirst({ where: { key: data.key, branchId: null } })

  if (existing) {
    const updated = await db.accountMapping.update({ where: { id: existing.id }, data: { accountId: data.accountId } })
    return NextResponse.json({ mapping: updated })
  }
  const mapping = await db.accountMapping.create({
    data: { key: data.key, accountId: data.accountId, branchId: data.branchId || null, description: data.description },
  })
  await db.auditLog.create({ data: { userId: session.id, action: 'CREATE', module: 'accountMappings', details: JSON.stringify({ id: mapping.id }) } })
  return NextResponse.json({ mapping })
}
