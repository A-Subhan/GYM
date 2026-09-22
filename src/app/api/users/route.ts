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
      email: data.email,
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
