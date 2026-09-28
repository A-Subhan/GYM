import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

const ACTIONS = ['canView', 'canAdd', 'canEdit', 'canDelete', 'canPrint'] as const

// GET /api/screen-permissions?roleId=… — saved per-screen permission rows for a role
export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('roles.view') && !session.permissions.includes('users.view')) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  }
  const url = new URL(req.url)
  const roleId = url.searchParams.get('roleId')
  if (!roleId) return NextResponse.json({ error: 'roleId required' }, { status: 400 })

  const role = await db.role.findUnique({ where: { id: roleId } })
  if (!role) return NextResponse.json({ error: 'Role not found' }, { status: 404 })

  const rows = await db.screenPermission.findMany({
    where: { roleId },
    orderBy: { screenKey: 'asc' },
    select: { screenKey: true, canView: true, canAdd: true, canEdit: true, canDelete: true, canPrint: true },
  })
  return NextResponse.json({ permissions: rows })
}

// POST /api/screen-permissions — { roleId, permissions: [{ screenKey, canView, canAdd, canEdit, canDelete, canPrint }] }
// Upserts every submitted row and deletes saved keys that are no longer submitted (full-matrix save).
export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('roles.config')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  if (!data.roleId) return NextResponse.json({ error: 'roleId required' }, { status: 400 })
  const incoming: any[] = Array.isArray(data.permissions) ? data.permissions : []
  for (const p of incoming) {
    if (!p || typeof p.screenKey !== 'string' || !p.screenKey.trim()) {
      return NextResponse.json({ error: 'Each permission row needs a screenKey' }, { status: 400 })
    }
  }

  const role = await db.role.findUnique({ where: { id: data.roleId } })
  if (!role) return NextResponse.json({ error: 'Role not found' }, { status: 404 })

  const keys = incoming.map(p => p.screenKey.trim())
  const saved = await db.$transaction(async (tx) => {
    for (const p of incoming) {
      const screenKey = p.screenKey.trim()
      const flags: Record<string, boolean> = {}
      for (const a of ACTIONS) flags[a] = !!p[a]
      await tx.screenPermission.upsert({
        where: { roleId_screenKey: { roleId: data.roleId, screenKey } },
        create: { roleId: data.roleId, screenKey, ...flags },
        update: flags,
      })
    }
    // remove rows for keys that were unchecked out of the matrix entirely
    await tx.screenPermission.deleteMany({
      where: { roleId: data.roleId, ...(keys.length ? { screenKey: { notIn: keys } } : {}) },
    })
    return tx.screenPermission.findMany({ where: { roleId: data.roleId }, orderBy: { screenKey: 'asc' } })
  })

  await db.auditLog.create({
    data: { userId: session.id, action: 'UPDATE', module: 'roles', details: JSON.stringify({ roleId: data.roleId, role: role.name, screenPermissionCount: saved.length }) },
  })
  return NextResponse.json({ permissions: saved })
}
