import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

/** Walk up from `startId` to the root; returns true if `targetId` is reached (i.e. target is start itself or an ancestor of start). */
function reachesTarget(all: { id: string; parentId: string | null }[], startId: string, targetId: string): boolean {
  let current: string | null = startId
  const seen = new Set<string>()
  while (current && !seen.has(current)) {
    if (current === targetId) return true
    seen.add(current)
    const node = all.find(b => b.id === current)
    current = node?.parentId ?? null
  }
  return false
}

export async function GET(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const { id } = await params
  const branch = await db.branch.findFirst({ where: { id, isDeleted: false }, include: { parent: true, children: true } })
  if (!branch) return NextResponse.json({ error: 'Branch not found' }, { status: 404 })
  return NextResponse.json({ branch })
}

export async function PATCH(req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('branches.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const { id } = await params
  const data = await req.json()

  const branch = await db.branch.findFirst({ where: { id, isDeleted: false } })
  if (!branch) return NextResponse.json({ error: 'Branch not found' }, { status: 404 })

  // code is immutable once created
  if (data.code !== undefined && String(data.code).trim() !== branch.code) {
    return NextResponse.json({ error: 'Branch code cannot be changed' }, { status: 400 })
  }

  // parent guard: must exist, must not be the branch itself or one of its descendants
  let parentId: string | null | undefined = undefined
  if (data.parentId !== undefined) {
    if (data.parentId === null || data.parentId === '') {
      parentId = null
    } else {
      const all = await db.branch.findMany({ where: { isDeleted: false }, select: { id: true, parentId: true } })
      // cycle guard: the new parent must not be the branch itself or one of its descendants —
      // walking UP from the proposed parent must never reach this branch
      if (reachesTarget(all, data.parentId, id)) {
        return NextResponse.json({ error: 'A branch cannot be moved under itself or one of its sub-branches' }, { status: 400 })
      }
      const parent = await db.branch.findFirst({ where: { id: data.parentId, isDeleted: false } })
      if (!parent) return NextResponse.json({ error: 'Parent branch not found' }, { status: 400 })
      parentId = parent.id
    }
  }

  const updated = await db.branch.update({
    where: { id },
    data: {
      ...(data.name !== undefined ? { name: String(data.name).trim() } : {}),
      ...(parentId !== undefined ? { parentId } : {}),
      ...(data.nodeType !== undefined ? { nodeType: data.nodeType === 'Control' ? 'Control' : 'Detail' } : {}),
      // Control-level nodes cannot hold branch detail data — clear it on switch
      ...(data.nodeType === 'Control'
        ? { address: null, city: null, phone: null, email: null, strn: null, ntn: null, trn: null, fbr: null, logo: null }
        : {}),
      ...(data.address !== undefined ? { address: data.address } : {}),
      ...(data.city !== undefined ? { city: data.city } : {}),
      ...(data.phone !== undefined ? { phone: data.phone } : {}),
      ...(data.email !== undefined ? { email: data.email } : {}),
      ...(data.strn !== undefined ? { strn: data.strn } : {}),
      ...(data.ntn !== undefined ? { ntn: data.ntn } : {}),
      ...(data.trn !== undefined ? { trn: data.trn } : {}),
      ...(data.fbr !== undefined ? { fbr: data.fbr } : {}),
      ...(data.logo !== undefined ? { logo: data.logo } : {}),
      ...(data.isActive !== undefined ? { isActive: !!data.isActive } : {}),
    },
  })
  await db.auditLog.create({
    data: { userId: session.id, action: 'UPDATE', module: 'branches', details: JSON.stringify({ id, code: updated.code }) },
  })
  return NextResponse.json({ branch: updated })
}

export async function DELETE(_req: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('branches.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })
  const { id } = await params

  const branch = await db.branch.findFirst({ where: { id, isDeleted: false } })
  if (!branch) return NextResponse.json({ error: 'Branch not found' }, { status: 404 })

  const children = await db.branch.count({ where: { parentId: id, isDeleted: false } })
  if (children > 0) return NextResponse.json({ error: `Cannot delete: ${children} sub-branch(es) attached. Delete or move them first.` }, { status: 400 })

  const users = await db.user.count({ where: { branchId: id } })
  if (users > 0) return NextResponse.json({ error: `Cannot delete: ${users} user(s) attached to this branch.` }, { status: 400 })

  const members = await db.member.count({ where: { branchId: id } })
  if (members > 0) return NextResponse.json({ error: `Cannot delete: ${members} member(s) attached to this branch.` }, { status: 400 })

  const staff = await db.staff.count({ where: { branchId: id } })
  if (staff > 0) return NextResponse.json({ error: `Cannot delete: ${staff} staff member(s) attached to this branch.` }, { status: 400 })

  await db.branch.update({ where: { id }, data: { isDeleted: true, isActive: false } })
  await db.auditLog.create({
    data: { userId: session.id, action: 'DELETE', module: 'branches', details: JSON.stringify({ id, code: branch.code }) },
  })
  return NextResponse.json({ success: true, message: `Branch ${branch.code} deleted` })
}
