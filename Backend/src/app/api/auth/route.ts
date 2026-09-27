import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { comparePassword } from '@/lib/hash'
import { signToken, setSessionCookie, clearSessionCookie } from '@/lib/jwt'
import { getSession } from '@/lib/auth'

export async function POST(req: NextRequest) {
  try {
    const { username, password } = await req.json()
    if (!username || !password) {
      return NextResponse.json({ error: 'Username and password are required' }, { status: 400 })
    }
    // case-insensitive username lookup (SQLite doesn't support mode: 'insensitive')
    const allUsers = await db.user.findMany({ include: { role: true } })
    const user = allUsers.find(u => u.username.toLowerCase() === String(username).trim().toLowerCase() && !u.isDeleted)
    if (!user) return NextResponse.json({ error: 'Invalid username or password' }, { status: 401 })
    if (!user.isActive || user.isDeleted) return NextResponse.json({ error: 'Account is inactive. Contact administrator.' }, { status: 403 })

    const ok = comparePassword(String(password), user.passwordHash)
    if (!ok) {
      await db.user.update({ where: { id: user.id }, data: { failedLoginCount: { increment: 1 } } })
      await db.auditLog.create({
        data: {
          userId: user.id, action: 'LOGIN_FAILED', module: 'auth',
          details: JSON.stringify({ username }),
          ipAddress: req.headers.get('x-forwarded-for') || undefined,
        },
      })
      return NextResponse.json({ error: 'Invalid username or password' }, { status: 401 })
    }

    await db.user.update({ where: { id: user.id }, data: { lastLoginAt: new Date(), failedLoginCount: 0 } })
    await db.auditLog.create({
      data: {
        userId: user.id, action: 'LOGIN', module: 'auth',
        details: JSON.stringify({ username }),
        ipAddress: req.headers.get('x-forwarded-for') || undefined,
      },
    })

    const token = await signToken({
      userId: user.id, username: user.username, roleId: user.roleId,
      branchId: user.branchId, accessibleBranchIds: user.accessibleBranchIds,
    })
    await setSessionCookie(token)

    return NextResponse.json({
      message: 'Login successful',
      user: {
        id: user.id, username: user.username, fullName: user.fullName,
        roleId: user.roleId, roleName: user.role?.name, branchId: user.branchId,
      },
    })
  } catch (e) {
    console.error('[login] error', e)
    return NextResponse.json({ error: 'Login failed. Please try again.' }, { status: 500 })
  }
}

export async function GET() {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Not authenticated' }, { status: 401 })
  return NextResponse.json({ user: session })
}

export async function DELETE() {
  await clearSessionCookie()
  return NextResponse.json({ message: 'Logged out' })
}
