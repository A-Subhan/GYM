import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

// Update role permissions
export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('roles.config')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const { id } = await params
  const data = await req.json()

  if (data.action === 'permissions') {
    const role = await db.role.findUnique({ where: { id }, include: { permissions: true } })
    if (!role) return NextResponse.json({ error: 'Role not found' }, { status: 404 })
    if (role.isSystem && !session.isSuperAdmin) return NextResponse.json({ error: 'Cannot modify system role' }, { status: 403 })

    await db.rolePermission.deleteMany({ where: { roleId: id } })
    const perms = await db.permission.findMany({ where: { code: { in: data.permissionCodes || [] } } })
    for (const p of perms) {
      await db.rolePermission.create({ data: { roleId: id, permissionId: p.id } })
    }
    await db.auditLog.create({
      data: { userId: session.id, action: 'UPDATE', module: 'roles', details: JSON.stringify({ id, permissionCount: perms.length }) },
    })
    return NextResponse.json({ success: true })
  }

  return NextResponse.json({ error: 'Unknown action' }, { status: 400 })
}

export async function DELETE(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('roles.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const { id } = await params
  const role = await db.role.findUnique({ where: { id } })
  if (!role) return NextResponse.json({ error: 'Role not found' }, { status: 404 })
  if (role.isSystem) return NextResponse.json({ error: 'Cannot delete system role' }, { status: 400 })
  const userCount = await db.user.count({ where: { roleId: id } })
  if (userCount > 0) return NextResponse.json({ error: `Role has ${userCount} users. Reassign before deleting.` }, { status: 400 })
  await db.role.delete({ where: { id } })
  await db.auditLog.create({ data: { userId: session.id, action: 'DELETE', module: 'roles', details: JSON.stringify({ id }) } })
  return NextResponse.json({ success: true })
}
