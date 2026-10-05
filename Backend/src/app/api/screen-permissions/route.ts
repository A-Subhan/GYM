import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { makeScreenPermissionId, makeUserPermissionId } from '@/lib/ids'

const ACTIONS = ['canView', 'canAdd', 'canEdit', 'canDelete', 'canPrint'] as const

// GET /api/screen-permissions?userId=…   -> per-USER screen permission rows (User Type = User)
// GET /api/screen-permissions?roleId=…   -> legacy per-ROLE rows (kept for backward compatibility)
export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('roles.view') && !session.permissions.includes('users.view')) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  }
  const url = new URL(req.url)
  const userId = url.searchParams.get('userId')
  const roleId = url.searchParams.get('roleId')
  if (!userId && !roleId) return NextResponse.json({ error: 'userId or roleId required' }, { status: 400 })

  if (userId) {
    const user = await db.user.findFirst({ where: { id: userId, isDeleted: false } })
    if (!user) return NextResponse.json({ error: 'User not found' }, { status: 404 })
    const rows = await db.userPermission.findMany({
      where: { userId },
      orderBy: { screenKey: 'asc' },
      select: { screenKey: true, canView: true, canAdd: true, canEdit: true, canDelete: true, canPrint: true },
    })
    return NextResponse.json({ permissions: rows, scope: 'user' })
  }

  const role = await db.role.findUnique({ where: { id: roleId! } })
  if (!role) return NextResponse.json({ error: 'Role not found' }, { status: 404 })

  const rows = await db.screenPermission.findMany({
    where: { roleId: roleId! },
    orderBy: { screenKey: 'asc' },
    select: { screenKey: true, canView: true, canAdd: true, canEdit: true, canDelete: true, canPrint: true },
  })
  return NextResponse.json({ permissions: rows, scope: 'role' })
}

// POST /api/screen-permissions — full-matrix save, either per user or (legacy) per role:
//   { userId, permissions: [{ screenKey, canView, canAdd, canEdit, canDelete, canPrint }] }
//   { roleId, permissions: [...] }
// Upserts every submitted row and deletes saved keys that are no longer submitted.
export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('roles.config') && !session.permissions.includes('users.edit')) {
    return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  }

  const data = await req.json()
  if (!data.userId && !data.roleId) return NextResponse.json({ error: 'userId or roleId required' }, { status: 400 })
  const incoming: any[] = Array.isArray(data.permissions) ? data.permissions : []
  for (const p of incoming) {
    if (!p || typeof p.screenKey !== 'string' || !p.screenKey.trim()) {
      return NextResponse.json({ error: 'Each permission row needs a screenKey' }, { status: 400 })
    }
  }

  const keys = incoming.map((p: any) => p.screenKey.trim())
  const flagsFor = (p: any) => {
    const flags: Record<string, boolean> = {}
    for (const a of ACTIONS) flags[a] = !!p[a]
    return flags
  }

  // --- per-USER save ( dbo.UserPermission ) ----------------------------
  if (data.userId) {
    const user = await db.user.findFirst({ where: { id: data.userId, isDeleted: false } })
    if (!user) return NextResponse.json({ error: 'User not found' }, { status: 404 })

    const saved = await db.$transaction(async (tx) => {
      // Pre-fetch existing rows for this user so we can branch on create vs update
      // (the @default(cuid()) is gone — the create path needs an explicit UPM- id).
      const existing = await tx.userPermission.findMany({
        where: { userId: data.userId },
        select: { id: true, screenKey: true },
      })
      const existingByKey = new Map(existing.map(r => [r.screenKey, r.id]))
      for (const p of incoming) {
        const screenKey = p.screenKey.trim()
        const existingId = existingByKey.get(screenKey)
        if (existingId) {
          await tx.userPermission.update({ where: { id: existingId }, data: flagsFor(p) })
        } else {
          // Reserve on the global db (reserve() opens its own $transaction)
          // so the IdSequence bump survives even if the outer tx rolls back.
          const id = await makeUserPermissionId()
          await tx.userPermission.create({ data: { id, userId: data.userId, screenKey, ...flagsFor(p) } })
        }
      }
      await tx.userPermission.deleteMany({
        where: { userId: data.userId, ...(keys.length ? { screenKey: { notIn: keys } } : {}) },
      })
      return tx.userPermission.findMany({ where: { userId: data.userId }, orderBy: { screenKey: 'asc' } })
    })

    await db.auditLog.create({
      data: { userId: session.id, action: 'UPDATE', module: 'users', details: JSON.stringify({ userId: data.userId, username: user.username, userPermissionCount: saved.length }) },
    })
    return NextResponse.json({ permissions: saved, scope: 'user' })
  }

  // --- legacy per-ROLE save ( dbo.ScreenPermission ) --------------------
  const role = await db.role.findUnique({ where: { id: data.roleId } })
  if (!role) return NextResponse.json({ error: 'Role not found' }, { status: 404 })

  const saved = await db.$transaction(async (tx) => {
    // Pre-fetch existing rows for this role so we can branch on create vs update
    // (the @default(cuid()) is gone — the create path needs an explicit SCP- id).
    const existing = await tx.screenPermission.findMany({
      where: { roleId: data.roleId },
      select: { id: true, screenKey: true },
    })
    const existingByKey = new Map(existing.map(r => [r.screenKey, r.id]))
    for (const p of incoming) {
      const screenKey = p.screenKey.trim()
      const existingId = existingByKey.get(screenKey)
      if (existingId) {
        await tx.screenPermission.update({ where: { id: existingId }, data: flagsFor(p) })
      } else {
        const id = await makeScreenPermissionId()
        await tx.screenPermission.create({ data: { id, roleId: data.roleId, screenKey, ...flagsFor(p) } })
      }
    }
    await tx.screenPermission.deleteMany({
      where: { roleId: data.roleId, ...(keys.length ? { screenKey: { notIn: keys } } : {}) },
    })
    return tx.screenPermission.findMany({ where: { roleId: data.roleId }, orderBy: { screenKey: 'asc' } })
  })

  await db.auditLog.create({
    data: { userId: session.id, action: 'UPDATE', module: 'roles', details: JSON.stringify({ roleId: data.roleId, role: role.name, screenPermissionCount: saved.length }) },
  })
  return NextResponse.json({ permissions: saved, scope: 'role' })
}
