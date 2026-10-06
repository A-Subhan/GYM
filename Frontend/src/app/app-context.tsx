'use client'

import { createContext, useContext } from 'react'

export type ScreenPermRow = {
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
  /** "Admin" | "User" — Admin gets full rights automatically */
  userType: string
  roleId: string | null
  roleName: string | null
  branchId: string | null
  isSuperAdmin: boolean
  permissions: string[]
  screenPermissions?: ScreenPermRow[]
}

export type Branch = { id: string; code: string; name: string; city?: string | null }

export type ScreenAction = 'view' | 'add' | 'edit' | 'delete' | 'print'

/** Session-level screen permission check: gates only when a saved row exists for that screen key. */
export function canScreen(session: SessionUser | null, screenKey: string, action: ScreenAction = 'view'): boolean {
  if (!session) return false
  const row = session.screenPermissions?.find(p => p.screenKey === screenKey)
  if (!row) return true // no saved entry for this screen — not gated by the matrix
  return !!row[action === 'view' ? 'canView' : action === 'add' ? 'canAdd' : action === 'edit' ? 'canEdit' : action === 'delete' ? 'canDelete' : 'canPrint']
}

export type AppCtx = {
  session: SessionUser | null
  branches: Branch[]
  selectedBranchIds: string[]
  setSelectedBranchIds: (ids: string[]) => void
  has: (perm: string) => boolean
  can: (screenKey: string, action?: ScreenAction) => boolean
  screenPerms: Record<string, ScreenPermRow>
  companyName: string | null
  setCompanyName: (name: string | null) => void
  companyLogo: string | null
  setCompanyLogo: (logo: string | null) => void
  refreshSession: () => Promise<void>
  logout: () => Promise<void>
  login: (username: string, password: string) => Promise<boolean>
}

export const AppContext = createContext<AppCtx>(null as any)

export function useApp(): AppCtx {
  const c = useContext(AppContext)
  if (!c) throw new Error('useApp must be used within AppContext provider')
  return c
}
