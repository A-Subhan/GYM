import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession, getSelectedBranchIds } from '@/lib/auth'

export async function GET() {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const allowed = session.accessibleBranchIds === '*' ? null : session.accessibleBranchIds.split(',')
  const branches = await db.branch.findMany({
    where: {
      isDeleted: false,
      ...(allowed ? { id: { in: allowed } } : {}),
    },
    orderBy: { code: 'asc' },
    include: { parent: true, children: true },
  })
  return NextResponse.json({ branches })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('branches.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  if (!data.name) return NextResponse.json({ error: 'Branch name required' }, { status: 400 })

  // auto-generate code
  const count = await db.branch.count()
  const code = `BR-${String(count + 1).padStart(3, '0')}`
  const branch = await db.branch.create({
    data: {
      code,
      name: data.name,
      address: data.address,
      city: data.city,
      phone: data.phone,
      email: data.email,
      strn: data.strn,
      ntn: data.ntn,
      fbr: data.fbr,
      logo: data.logo,
      level: data.level || 'Detail', // Company | Control | Detail
      parentId: data.parentId || null,
    },
    include: { parent: true, children: true },
  })
  await db.auditLog.create({
    data: { userId: session.id, action: 'CREATE', module: 'branches', details: JSON.stringify({ id: branch.id, code }) },
  })
  return NextResponse.json({ branch })
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('branches.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  if (!data.id) return NextResponse.json({ error: 'id required' }, { status: 400 })

  const existing = await db.branch.findUnique({ where: { id: data.id } })
  if (!existing) return NextResponse.json({ error: 'Branch not found' }, { status: 404 })

  // Prevent setting parent to self or descendant
  if (data.parentId && data.parentId === data.id) {
    return NextResponse.json({ error: 'Branch cannot be its own parent' }, { status: 400 })
  }

  const branch = await db.branch.update({
    where: { id: data.id },
    data: {
      name: data.name,
      address: data.address,
      city: data.city,
      phone: data.phone,
      email: data.email,
      strn: data.strn,
      ntn: data.ntn,
      fbr: data.fbr,
      logo: data.logo,
      level: data.level,
      parentId: data.parentId || null,
      isActive: data.isActive,
    },
    include: { parent: true, children: true },
  })
  await db.auditLog.create({
    data: { userId: session.id, action: 'UPDATE', module: 'branches', details: JSON.stringify({ id: branch.id }) },
  })
  return NextResponse.json({ branch })
}

export async function DELETE(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('branches.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const url = new URL(req.url)
  const id = url.searchParams.get('id')
  if (!id) return NextResponse.json({ error: 'id required' }, { status: 400 })

  // Soft delete — set isDeleted = true
  await db.branch.update({ where: { id }, data: { isDeleted: true, isActive: false } })
  await db.auditLog.create({
    data: { userId: session.id, action: 'DELETE', module: 'branches', details: JSON.stringify({ id }) },
  })
  return NextResponse.json({ success: true })
}
