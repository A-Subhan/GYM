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
    include: { role: true, branch: true, userPermissions: { include: { permission: true } } },
    orderBy: { username: 'asc' },
  })
  return NextResponse.json({ users: users.map(u => ({
    ...u,
    passwordHash: undefined,
    userPermissions: u.userPermissions.map(p => p.permission.code),
  })) })
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
      email: data.email,
      fullName: data.fullName,
      passwordHash: hashPassword(String(data.password)),
      roleId: data.roleId,
      branchId: data.branchId || null,
      accessibleBranchIds: data.accessibleBranchIds || (data.branchId || '*'),
      phone: data.phone,
      photo: data.photo,
      isActive: data.isActive !== false,
    },
  })
  await db.auditLog.create({
    data: { userId: session.id, action: 'CREATE', module: 'users', details: JSON.stringify({ id: user.id, username: user.username }) },
  })
  return NextResponse.json({ user: { ...user, passwordHash: undefined } })
}

// PATCH — update user (including per-user permissions)
export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('users.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  if (!data.id) return NextResponse.json({ error: 'id required' }, { status: 400 })

  const existing = await db.user.findUnique({ where: { id: data.id } })
  if (!existing) return NextResponse.json({ error: 'User not found' }, { status: 404 })

  // Update basic fields
  if (data.fullName || data.email || data.phone || data.photo || data.roleId || data.branchId || data.accessibleBranchIds || data.isActive !== undefined) {
    await db.user.update({
      where: { id: data.id },
      data: {
        fullName: data.fullName,
        email: data.email,
        phone: data.phone,
        photo: data.photo,
        roleId: data.roleId,
        branchId: data.branchId || null,
        accessibleBranchIds: data.accessibleBranchIds,
        isActive: data.isActive,
      },
    })
  }

  // Update password if provided
  if (data.password) {
    await db.user.update({ where: { id: data.id }, data: { passwordHash: hashPassword(String(data.password)) } })
  }

  // Update per-user permissions if provided
  if (Array.isArray(data.permissionCodes)) {
    // Get permission IDs from codes
    const perms = await db.permission.findMany({ where: { code: { in: data.permissionCodes } } })
    const permIds = perms.map(p => p.id)

    // Delete existing user permissions
    await db.userPermission.deleteMany({ where: { userId: data.id } })
    // Insert new user permissions
    for (const pid of permIds) {
      await db.userPermission.create({ data: { userId: data.id, permissionId: pid } })
    }
    await db.auditLog.create({
      data: { userId: session.id, action: 'UPDATE', module: 'users', details: JSON.stringify({ id: data.id, action: 'permissions', count: permIds.length }) },
    })
  }

  const updated = await db.user.findUnique({
    where: { id: data.id },
    include: { role: true, branch: true, userPermissions: { include: { permission: true } } },
  })
  return NextResponse.json({ user: { ...updated, passwordHash: undefined, userPermissions: updated?.userPermissions.map(p => p.permission.code) } })
}
