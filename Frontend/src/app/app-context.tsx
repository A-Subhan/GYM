'use client'

import { createContext, useContext } from 'react'

export type SessionUser = {
  id: string
  username: string
  fullName: string
  email: string | null
  roleId: string
  roleName: string | null
  branchId: string | null
  isSuperAdmin: boolean
  permissions: string[]
}

export type Branch = { id: string; code: string; name: string; city?: string | null }

export type AppCtx = {
  session: SessionUser | null
  branches: Branch[]
  selectedBranchIds: string[]
  setSelectedBranchIds: (ids: string[]) => void
  has: (perm: string) => boolean
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
