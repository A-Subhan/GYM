import { db } from './db'
import { getSessionToken, verifyToken, type TokenPayload } from './jwt'
import { PERMISSION_CODES } from './permissions'

export type SessionUser = {
  id: string
  username: string
  fullName: string
  email: string | null
  phone: string | null
  photo: string | null
  roleId: string
  roleName: string | null
  branchId: string | null
  accessibleBranchIds: string
  isSuperAdmin: boolean
  permissions: string[]
  lastLoginAt: Date | null
}

export async function getSession(): Promise<SessionUser | null> {
  const token = await getSessionToken()
  if (!token) return null
  const payload = await verifyToken(token)
  if (!payload) return null

  const user = await db.user.findUnique({
    where: { id: payload.userId },
    include: {
      role: { include: { permissions: { include: { permission: true } } } },
      userPermissions: { include: { permission: true } },
    },
  })
  if (!user || !user.isActive || user.isDeleted) return null

  const rolePerms = user.role?.permissions?.map(p => p.permission.code) ?? []
  const userPerms = user.userPermissions?.map(p => p.permission.code) ?? []
  // Merge role permissions + user override permissions (union)
  const perms = Array.from(new Set([...rolePerms, ...userPerms]))
  const isSuperAdmin = user.role?.name === 'Super Admin' || user.role?.name === 'Owner'

  return {
    id: user.id,
    username: user.username,
    fullName: user.fullName,
    email: user.email,
    phone: user.phone,
    photo: user.photo,
    roleId: user.roleId,
    roleName: user.role?.name ?? null,
    branchId: user.branchId,
    accessibleBranchIds: user.accessibleBranchIds,
    isSuperAdmin,
    permissions: isSuperAdmin ? PERMISSION_CODES : perms,
    lastLoginAt: user.lastLoginAt,
  }
}

export function hasPermission(session: SessionUser | null, code: string): boolean {
  if (!session) return false
  return session.permissions.includes(code)
}

export function canAccessBranch(session: SessionUser, branchId: string | null): boolean {
  if (!branchId) return true
  if (session.isSuperAdmin || session.accessibleBranchIds === '*') return true
  return session.accessibleBranchIds.split(',').includes(branchId)
}

/** Returns the list of branch IDs the user can see, or null to indicate "all". */
export function getAllowedBranchIds(session: SessionUser): string[] | null {
  if (session.isSuperAdmin || session.accessibleBranchIds === '*') return null
  const ids = session.accessibleBranchIds.split(',').filter(Boolean)
  // Always include the user's own branch
  if (session.branchId && !ids.includes(session.branchId)) ids.push(session.branchId)
  return ids
}

/** Parse the `branches` query param and intersect with allowed. Empty = all allowed. */
export function getSelectedBranchIds(session: SessionUser, branchesParam: string | null): string[] | null {
  const allowed = getAllowedBranchIds(session)
  if (!branchesParam) return allowed
  const requested = branchesParam.split(',').filter(Boolean)
  if (!allowed) return requested
  return requested.filter(b => allowed.includes(b))
}

export type { TokenPayload }
