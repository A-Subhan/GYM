import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { hashPassword } from '@/lib/hash'

export async function GET() {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('roles.view')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const roles = await db.role.findMany({ include: { permissions: { include: { permission: true } } }, orderBy: { name: 'asc' } })
  const permissions = await db.permission.findMany({ orderBy: { code: 'asc' } })
  return NextResponse.json({ roles, permissions })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('roles.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const data = await req.json()
  if (!data.name) return NextResponse.json({ error: 'Role name required' }, { status: 400 })
  const existing = await db.role.findUnique({ where: { name: data.name } })
  if (existing) return NextResponse.json({ error: 'Role already exists' }, { status: 400 })
  const role = await db.role.create({ data: { name: data.name, description: data.description, isSystem: false } })
  await db.auditLog.create({ data: { userId: session.id, action: 'CREATE', module: 'roles', details: JSON.stringify({ id: role.id, name: role.name }) } })
  return NextResponse.json({ role })
}
