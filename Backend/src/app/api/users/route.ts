import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { hashPassword } from '@/lib/hash'

export async function GET() {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('users.view')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const users = await db.user.findMany({
    where: { isDeleted: false },
    include: { role: true, branch: true },
    orderBy: { username: 'asc' },
  })
  return NextResponse.json({ users: users.map(u => ({ ...u, passwordHash: undefined })) })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('users.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  if (!data.username || !data.fullName || !data.password) {
    return NextResponse.json({ error: 'Username, full name, and password required' }, { status: 400 })
  }

  const existing = await db.user.findUnique({ where: { username: data.username } })
  if (existing) return NextResponse.json({ error: 'Username already exists' }, { status: 400 })

  const role = await db.role.findUnique({ where: { id: data.roleId } })
  if (!role) return NextResponse.json({ error: 'Invalid role' }, { status: 400 })

  const user = await db.user.create({
    data: {
      username: data.username,
      email: data.email || null,
      fullName: data.fullName,
      passwordHash: hashPassword(String(data.password)),
      roleId: data.roleId,
      branchId: data.branchId || null,
      accessibleBranchIds: data.accessibleBranchIds || (data.branchId || '*'),
      phone: data.phone,
      isActive: data.isActive !== false,
    },
  })
  await db.auditLog.create({
    data: { userId: session.id, action: 'CREATE', module: 'users', details: JSON.stringify({ id: user.id, username: user.username }) },
  })
  return NextResponse.json({ user: { ...user, passwordHash: undefined } })
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('users.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  if (!data.id) return NextResponse.json({ error: 'User id required' }, { status: 400 })

  const user = await db.user.findFirst({ where: { id: data.id, isDeleted: false } })
  if (!user) return NextResponse.json({ error: 'User not found' }, { status: 404 })

  if (data.username !== undefined && String(data.username).trim() !== user.username) {
    const dupe = await db.user.findUnique({ where: { username: String(data.username).trim() } })
    if (dupe) return NextResponse.json({ error: 'Username already exists' }, { status: 400 })
  }
  if (data.roleId !== undefined && data.roleId) {
    const role = await db.role.findUnique({ where: { id: data.roleId } })
    if (!role) return NextResponse.json({ error: 'Invalid role' }, { status: 400 })
  }

  const updated = await db.user.update({
    where: { id: user.id },
    data: {
      ...(data.username !== undefined ? { username: String(data.username).trim() } : {}),
      ...(data.fullName !== undefined ? { fullName: data.fullName } : {}),
      ...(data.email !== undefined ? { email: data.email || null } : {}),
      ...(data.phone !== undefined ? { phone: data.phone } : {}),
      // password optional on edit — leave blank to keep the current one
      ...(data.password ? { passwordHash: hashPassword(String(data.password)) } : {}),
      ...(data.roleId !== undefined ? { roleId: data.roleId } : {}),
      ...(data.branchId !== undefined ? { branchId: data.branchId || null } : {}),
      ...(data.accessibleBranchIds !== undefined ? { accessibleBranchIds: data.accessibleBranchIds || '*' } : {}),
      ...(data.isActive !== undefined ? { isActive: !!data.isActive } : {}),
    },
  })
  await db.auditLog.create({
    data: { userId: session.id, action: 'UPDATE', module: 'users', details: JSON.stringify({ id: user.id, username: updated.username }) },
  })
  return NextResponse.json({ user: { ...updated, passwordHash: undefined } })
}

export async function DELETE(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('users.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const url = new URL(req.url)
  const id = url.searchParams.get('id')
  if (!id) return NextResponse.json({ error: 'User id required' }, { status: 400 })
  if (id === session.id) return NextResponse.json({ error: 'You cannot delete your own account' }, { status: 400 })

  const user = await db.user.findFirst({ where: { id, isDeleted: false } })
  if (!user) return NextResponse.json({ error: 'User not found' }, { status: 404 })

  await db.user.update({ where: { id }, data: { isDeleted: true, isActive: false } })
  await db.auditLog.create({
    data: { userId: session.id, action: 'DELETE', module: 'users', details: JSON.stringify({ id, username: user.username }) },
  })
  return NextResponse.json({ success: true, message: `User ${user.username} deleted` })
}
