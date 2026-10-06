import { db } from './db'
import { getSessionToken, verifyToken, type TokenPayload } from './jwt'
import { PERMISSION_CODES } from './permissions'

export type SessionScreenPermission = {
  screenKey: string
  canView: boolean
  canAdd: boolean
  canEdit: boolean
  canDelete: boolean
  canPrint: boolean
}

export type SessionUser = {
  id: string
  username: string
  fullName: string
  email: string | null
  phone: string | null
  photo: string | null
  /** "Admin" | "User" — Admin gets full rights automatically, User is gated per screen */
  userType: string
  roleId: string | null
  roleName: string | null
  branchId: string | null
  accessibleBranchIds: string
  isSuperAdmin: boolean
  permissions: string[]
  /** per-screen permission matrix (empty for Admin — never gated) */
  screenPermissions: SessionScreenPermission[]
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
      role: { include: { permissions: { include: { permission: true } }, screenPermissions: true } },
      userPermissions: true,
    },
  })
  if (!user || !user.isActive || user.isDeleted) return null

  // --- User Type model -------------------------------------------------
  // Admin: automatically full rights on the entire software.
  // User: rights assigned per user, per screen (UserPermission). The legacy
  // role grants (if any) are still honoured so pre-existing accounts and
  // data keep working after the upgrade.
  const isAdmin = (user.userType || 'User') === 'Admin'
  const legacyRoleAdmin = user.role?.name === 'Super Admin' || user.role?.name === 'Owner'
  const isSuperAdmin = isAdmin || legacyRoleAdmin

  const rolePermCodes = user.role?.permissions?.map(p => p.permission.code) ?? []
  const permissions = isSuperAdmin ? PERMISSION_CODES : rolePermCodes

  // Per-user screen permissions (dbo.UserPermission); role-level screen rows
  // act as the base layer that user rows override.
  const roleScreens = isSuperAdmin
    ? []
    : (user.role?.screenPermissions ?? []).map(r => ({
        screenKey: r.screenKey,
        canView: r.canView,
        canAdd: r.canAdd,
        canEdit: r.canEdit,
        canDelete: r.canDelete,
        canPrint: r.canPrint,
      }))
  const screenPermissions = isSuperAdmin
    ? []
    : (() => {
        const byKey = new Map(roleScreens.map(r => [r.screenKey, { ...r }]))
        for (const up of user.userPermissions ?? []) {
          byKey.set(up.screenKey, {
            screenKey: up.screenKey,
            canView: up.canView,
            canAdd: up.canAdd,
            canEdit: up.canEdit,
            canDelete: up.canDelete,
            canPrint: up.canPrint,
          })
        }
        return Array.from(byKey.values())
      })()

  return {
    id: user.id,
    username: user.username,
    fullName: user.fullName,
    email: user.email,
    phone: user.phone,
    photo: user.photo,
    userType: isAdmin ? 'Admin' : 'User',
    roleId: user.roleId,
    roleName: user.role?.name ?? null,
    branchId: user.branchId,
    accessibleBranchIds: user.accessibleBranchIds,
    isSuperAdmin,
    permissions,
    screenPermissions,
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
