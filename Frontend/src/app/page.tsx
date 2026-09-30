'use client'

import { useEffect, useState, useCallback, useMemo, type ReactNode } from 'react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription,
} from '@/components/ui/dialog'
import {
  Sheet, SheetContent, SheetTrigger,
} from '@/components/ui/sheet'
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select'
import { Badge } from '@/components/ui/badge'
import { Textarea } from '@/components/ui/textarea'
import { Switch } from '@/components/ui/switch'
import { toast } from 'sonner'
import {
  LayoutDashboard, Wallet, Users, ClipboardList, Dumbbell, Apple,
  UserCog, Calendar, Receipt, Stethoscope, FileText, Settings, LogOut,
  Menu, ChevronDown, ChevronRight, Search, Plus, Edit, Trash2, Eye, X, Save,
  BarChart3, BookOpen, UsersRound, CalendarCheck, DonutIcon, Coins,
  Briefcase, Truck, ShieldCheck, Building2, IdCard, ScrollText,
  ListTree, Tag, FileBarChart, CheckCircle2, AlertCircle, Banknote,
  Layers, Crown, Cookie, BanknoteIcon, Send, Activity, Hand,
  AlertTriangle, Check, Filter, Download, Printer,
  Sun, Moon, SunMoon, ShieldAlert,
} from 'lucide-react'
import { format as fmtDate } from 'date-fns'
import { useTheme } from 'next-themes'
import {
  CoaModule as CoaModuleImpl,
  BookVoucherScreen as BookVoucherScreenImpl,
  OpeningTrialBalanceModule as OpeningTrialBalanceModuleImpl,
  TaxHeadsModule as TaxHeadsModuleImpl,
  ChequesModule as ChequesModuleImpl,
  FinanceReportsModule as FinanceReportsModuleImpl,
  AccountMappingsModule as AccountMappingsModuleImpl,
  FinanceDefaultsModule as FinanceDefaultsModuleImpl,
  MembersModule as MembersModuleImpl,
  MembershipsModule as MembershipsModuleImpl,
  AttendanceModule as AttendanceModuleImpl,
  FeesModule as FeesModuleImpl,
  ProspectsModule as ProspectsModuleImpl,
  FreezesModule as FreezesModuleImpl,
  FollowUpsModule as FollowUpsModuleImpl,
  MemberStatusModule as MemberStatusModuleImpl,
  ExercisesModule as ExercisesModuleImpl,
  WorkoutsModule as WorkoutsModuleImpl,
  DietModule as DietModuleImpl,
  ProgressModule as ProgressModuleImpl,
  EquipmentModule as EquipmentModuleImpl,
  InventoryModule as InventoryModuleImpl,
  StaffModule as StaffModuleImpl,
  ShiftsModule as ShiftsModuleImpl,
  CalendarModule as CalendarModuleImpl,
  LeavesModule as LeavesModuleImpl,
  OvertimeModule as OvertimeModuleImpl,
  PayrollModule as PayrollModuleImpl,
  CompanyModule as CompanyModuleImpl,
  UsersModule as UsersModuleImpl,
  AdminDefaultsModule as AdminDefaultsModuleImpl,
  AuditModule as AuditModuleImpl,
  PTSessionsModule as PTSessionsModuleImpl,
  MasterFilesScreen,
  WorkoutAssignmentScreen,
  FitnessGoalsScreen,
  TrainerAvailabilityScreen,
  TrainerScheduleScreen,
} from './module-pages'
import { BranchesModule as BranchesModuleImpl } from './modules'
import { AppContext, type AppCtx, type SessionUser, type Branch, useApp, canScreen, type ScreenPermRow } from './app-context'
import {
  Toolbar, DataTable, StatusBadge, Modal, FormRow, EmptyState, SearchInput, ConfirmModal,
} from './modules'

// =================================================================
// Auth context — types and useApp hook imported from ./app-context
// =================================================================

// =================================================================
// Module router — all module components live in this file (avoids
// multi-route restriction of the sandbox)
// =================================================================
type ModuleKey =
  | 'dashboard' | 'login'
  // Finance → Vouchers
  | 'finance-voucher-bpv' | 'finance-voucher-brv' | 'finance-voucher-cpv'
  | 'finance-voucher-crv' | 'finance-voucher-jv' | 'finance-voucher-otb'
  | 'finance-voucher-cheques'
  // Finance → Reports
  | 'finance-reports-aging' | 'finance-reports-main'
  // Finance → Master Files
  | 'finance-coa' | 'finance-tax' | 'finance-master-files'
  // Gym → Main
  | 'gym-members' | 'gym-memberships' | 'gym-attendance' | 'gym-fees'
  | 'gym-status' | 'gym-freezes' | 'gym-prospects'
  | 'gym-workout-assignment' | 'gym-diet-assignment' | 'gym-progress'
  | 'gym-followups'
  // Gym → Reports
  | 'gym-reports'
  // Gym → Master Files
  | 'gym-exercises' | 'gym-workouts' | 'gym-diet'
  | 'gym-equipment' | 'gym-inventory' | 'gym-master-files'
  // Payroll → Main
  | 'payroll-staff' | 'payroll-staff-attendance' | 'payroll-leaves'
  | 'payroll-overtime' | 'payroll-payroll'
  // Payroll → Reports
  | 'payroll-reports'
  // Payroll → Master Files
  | 'payroll-shifts' | 'payroll-calendar' | 'payroll-master-files'
  // Admin → Defaults
  | 'admin-company' | 'admin-finance-defaults' | 'admin-account-mappings'
  | 'admin-coa-config' | 'admin-accounting-defaults'
  // Admin → Reports
  | 'admin-audit'
  // Admin → Master Files
  | 'admin-branches' | 'admin-users' | 'admin-roles' | 'admin-permissions'
  // Gym → Operations (new)
  | 'gym-fitness-goals' | 'gym-body-progress'
  | 'gym-pt-sessions' | 'gym-trainer-availability' | 'gym-trainer-schedule'
  // Gym → Reports (new)
  // Inventory → Transactions
  | 'inv-purchases' | 'inv-stock-movements' | 'inv-equipment' | 'inv-equipment-maintenance'
  // Inventory → Reports
  | 'inv-reports'
  // Inventory → Master
  | 'inv-items' | 'inv-suppliers' | 'inv-master-files'
  // HR Reports
  | 'hr-reports'

type NavScreen = { key: ModuleKey; label: string; perm: string }
type NavSection = { label: string; perm?: string; screens: NavScreen[] }
type NavModule = { label: string; icon: any; perm?: string; sections: NavSection[] } | { key: ModuleKey; label: string; icon: any; perm: string }

const NAV: NavModule[] = [
  { key: 'dashboard', label: 'Dashboard', icon: LayoutDashboard, perm: 'dashboard.view' },
  {
    label: 'Gym Management', icon: Dumbbell, sections: [
      {
        label: 'Operations', perm: 'members.view', screens: [
          { key: 'gym-members', label: 'Members', perm: 'members.view' },
          { key: 'gym-memberships', label: 'Membership Plans', perm: 'memberships.view' },
          { key: 'gym-attendance', label: 'Attendance', perm: 'attendance.view' },
          { key: 'gym-fees', label: 'Fees & Invoices', perm: 'fees.view' },
          { key: 'gym-status', label: 'Member Status', perm: 'members.status' },
          { key: 'gym-freezes', label: 'Membership Freeze', perm: 'freeze.view' },
          { key: 'gym-prospects', label: 'Prospects / Inquiries', perm: 'prospects.view' },
          { key: 'gym-followups', label: 'Member Follow Up', perm: 'followups.view' },
          { key: 'gym-workout-assignment', label: 'Workout Assignment', perm: 'workouts.assign' },
          { key: 'gym-diet-assignment', label: 'Diet Assignment', perm: 'diet.assign' },
          { key: 'gym-progress', label: 'Body Progress', perm: 'progress.view' },
          { key: 'gym-fitness-goals', label: 'Fitness Goals', perm: 'progress.view' },
          { key: 'gym-pt-sessions', label: 'Personal Training', perm: 'progress.view' },
          { key: 'gym-trainer-availability', label: 'Trainer Availability', perm: 'staff.view' },
          { key: 'gym-trainer-schedule', label: 'Trainer Schedule', perm: 'staff.view' },
        ],
      },
      {
        label: 'Reports', perm: 'reports.view', screens: [
          { key: 'gym-reports', label: 'Gym Reports', perm: 'reports.view' },
        ],
      },
      {
        label: 'Master', perm: 'workouts.view', screens: [
          { key: 'gym-exercises', label: 'Exercises', perm: 'workouts.view' },
          { key: 'gym-workouts', label: 'Workout Plans', perm: 'workouts.view' },
          { key: 'gym-diet', label: 'Diet Plans', perm: 'diet.view' },
          { key: 'gym-master-files', label: 'Gym Master Files', perm: 'masters.view' },
        ],
      },
    ],
  },
  {
    label: 'Finance', icon: Wallet, sections: [
      {
        label: 'Vouchers', perm: 'vouchers.view', screens: [
          { key: 'finance-voucher-bpv', label: 'Bank Payment Voucher', perm: 'vouchers.view' },
          { key: 'finance-voucher-brv', label: 'Bank Receipt Voucher', perm: 'vouchers.view' },
          { key: 'finance-voucher-cpv', label: 'Cash Payment Voucher', perm: 'vouchers.view' },
          { key: 'finance-voucher-crv', label: 'Cash Receipt Voucher', perm: 'vouchers.view' },
          { key: 'finance-voucher-jv', label: 'Journal Voucher', perm: 'vouchers.view' },
          { key: 'finance-voucher-otb', label: 'Opening Trial Balance', perm: 'vouchers.view' },
          { key: 'finance-voucher-cheques', label: 'Cheques', perm: 'cheques.view' },
        ],
      },
      {
        label: 'Reports', perm: 'finance.reports', screens: [
          { key: 'finance-reports-aging', label: 'Aging Reports', perm: 'finance.reports' },
          { key: 'finance-reports-main', label: 'Finance Reports', perm: 'finance.reports' },
        ],
      },
      {
        label: 'Master', perm: 'finance.coa', screens: [
          { key: 'finance-coa', label: 'Chart of Accounts', perm: 'finance.coa' },
          { key: 'finance-tax', label: 'Tax Heads', perm: 'tax.view' },
          { key: 'finance-master-files', label: 'Master Files', perm: 'masters.view' },
        ],
      },
    ],
  },
  {
    label: 'HR and Payroll', icon: UserCog, sections: [
      {
        label: 'Transactions', perm: 'staff.view', screens: [
          { key: 'payroll-staff', label: 'Staff', perm: 'staff.view' },
          { key: 'payroll-leaves', label: 'Leave', perm: 'leaves.view' },
          { key: 'payroll-overtime', label: 'Overtime', perm: 'overtime.view' },
          { key: 'payroll-payroll', label: 'Payroll', perm: 'payroll.view' },
          { key: 'payroll-shifts', label: 'Shifts', perm: 'shifts.view' },
          { key: 'payroll-calendar', label: 'Calendar', perm: 'calendar.view' },
        ],
      },
      {
        label: 'Reports', perm: 'reports.view', screens: [
          { key: 'hr-reports', label: 'HR Reports', perm: 'reports.view' },
        ],
      },
      {
        label: 'Master', perm: 'masters.view', screens: [
          { key: 'payroll-master-files', label: 'Payroll Master File', perm: 'masters.view' },
        ],
      },
    ],
  },
  {
    label: 'Inventory', icon: Truck, sections: [
      {
        label: 'Transactions', perm: 'inventory.view', screens: [
          { key: 'inv-purchases', label: 'Purchases', perm: 'inventory.add' },
          { key: 'inv-stock-movements', label: 'Stock Movements', perm: 'inventory.add' },
          { key: 'inv-equipment', label: 'Equipment', perm: 'equipment.view' },
        ],
      },
      {
        label: 'Reports', perm: 'reports.view', screens: [
          { key: 'inv-reports', label: 'Inventory Reports', perm: 'reports.view' },
        ],
      },
      {
        label: 'Master', perm: 'inventory.view', screens: [
          { key: 'inv-items', label: 'Items', perm: 'inventory.view' },
          { key: 'inv-suppliers', label: 'Suppliers', perm: 'inventory.view' },
        ],
      },
    ],
  },
  {
    label: 'Admin & Security', icon: Settings, sections: [
      {
        label: 'Management', perm: 'company.view', screens: [
          { key: 'admin-company', label: 'Company Information', perm: 'company.view' },
          { key: 'admin-finance-defaults', label: 'Finance Defaults', perm: 'finance.settings' },
          { key: 'admin-account-mappings', label: 'Account Mapping', perm: 'accountMappings.view' },
          { key: 'admin-accounting-defaults', label: 'Defaults', perm: 'company.view' },
        ],
      },
      {
        label: 'Reports', perm: 'audit.view', screens: [
          { key: 'admin-audit', label: 'Administrative Reports', perm: 'audit.view' },
        ],
      },
      {
        label: 'Master', perm: 'branches.view', screens: [
          { key: 'admin-branches', label: 'Branches', perm: 'branches.view' },
          { key: 'admin-users', label: 'Users & Permissions', perm: 'users.view' },
        ],
      },
    ],
  },
]

// =================================================================
// Hooks
// =================================================================
function useFetch<T>(url: string | null) {
  const [data, setData] = useState<T | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const reload = useCallback(async () => {
    if (!url) return
    setLoading(true)
    setError(null)
    try {
      const res = await fetch(url)
      if (res.status === 401) { setData(null); setError('Unauthorized'); return }
      const json = await res.json()
      if (!res.ok) setError(json.error || 'Failed')
      else setData(json)
    } catch (e: any) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }, [url])
  useEffect(() => { reload() }, [reload])
  return { data, loading, error, reload, setData }
}

async function apiPost(url: string, body: any) {
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  const json = await res.json()
  if (!res.ok) throw new Error(json.error || 'Failed')
  return json
}

async function apiPatch(url: string, body: any) {
  const res = await fetch(url, {
    method: 'PATCH',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  const json = await res.json()
  if (!res.ok) throw new Error(json.error || 'Failed')
  return json
}

async function apiDelete(url: string) {
  const res = await fetch(url, { method: 'DELETE' })
  const json = await res.json()
  if (!res.ok) throw new Error(json.error || 'Failed')
  return json
}

// =================================================================
// Common UI helpers
// =================================================================
function fmtMoney(n: number | null | undefined) {
  if (n === null || n === undefined) return '—'
  return Number(n).toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 2 })
}

function fmtDateStr(d: string | Date | null | undefined) {
  if (!d) return '—'
  try { return fmtDate(new Date(d), 'dd MMM yyyy') } catch { return '—' }
}

function fmtDateTime(d: string | Date | null | undefined) {
  if (!d) return '—'
  try { return fmtDate(new Date(d), 'dd MMM yyyy HH:mm') } catch { return '—' }
}

// =================================================================
// App Shell
// =================================================================
export default function Home() {
  const [session, setSession] = useState<SessionUser | null>(null)
  const [loadingSession, setLoadingSession] = useState(true)
  const [branches, setBranches] = useState<Branch[]>([])
  const [selectedBranchIds, setSelectedBranchIds] = useState<string[]>([])
  const [activeModule, setActiveModule] = useState<ModuleKey>('dashboard')
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const [companyName, setCompanyName] = useState<string | null>(null)

  const refreshSession = useCallback(async () => {
    setLoadingSession(true)
    try {
      const res = await fetch('/api/auth')
      if (res.ok) {
        const json = await res.json()
        setSession(json.user)
      } else {
        setSession(null)
      }
    } catch {
      setSession(null)
    } finally {
      setLoadingSession(false)
    }
  }, [])

  const loadBranches = useCallback(async () => {
    const res = await fetch('/api/branches')
    if (res.ok) {
      const json = await res.json()
      setBranches(json.branches || [])
    }
  }, [])

  // Company name for the app shell brand (set once on the Defaults page, shown globally)
  useEffect(() => {
    if (!session) { setCompanyName(null); return }
    let cancelled = false
    fetch('/api/company')
      .then(r => (r.ok ? r.json() : null))
      .then(json => { if (!cancelled && json?.company?.name) setCompanyName(json.company.name) })
      .catch(() => {})
    return () => { cancelled = true }
  }, [session])

  useEffect(() => { refreshSession() }, [refreshSession])

  // Hash routing — every sidebar link is a real anchor (#/<screen-key>), so
  // right-click shows "Open in new tab / window" and a URL can be opened directly.
  useEffect(() => {
    const valid = new Set<string>(['dashboard'])
    for (const mod of NAV) {
      if ('key' in mod) valid.add(mod.key)
      else for (const s of mod.sections) for (const sc of s.screens) valid.add(sc.key)
    }
    const applyHash = () => {
      const key = window.location.hash.replace(/^#\/?/, '')
      if (key && valid.has(key)) setActiveModule(key as ModuleKey)
    }
    applyHash()
    window.addEventListener('hashchange', applyHash)
    return () => window.removeEventListener('hashchange', applyHash)
  }, [])

  // Central navigation: update the hash (real URL) + switch the screen
  const navigateTo = useCallback((key: ModuleKey) => {
    if (('#/' + key) !== window.location.hash) window.location.hash = '/' + key
    setActiveModule(key)
  }, [])

  useEffect(() => {
    if (session) {
      loadBranches()
    } else {
      setActiveModule('login')
    }
  }, [session, loadBranches])

  // Cross-screen navigation mechanism — modules can dispatch:
  //   window.dispatchEvent(new CustomEvent('contoura:navigate', { detail: { key: 'gym-attendance' } }))
  useEffect(() => {
    const handler = (e: Event) => {
      const key = (e as CustomEvent).detail?.key
      if (typeof key === 'string') setActiveModule(key as ModuleKey)
    }
    window.addEventListener('contoura:navigate', handler)
    return () => window.removeEventListener('contoura:navigate', handler)
  }, [])

  const login = useCallback(async (username: string, password: string) => {
    try {
      const res = await fetch('/api/auth', {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ username, password }),
      })
      const json = await res.json()
      if (!res.ok) throw new Error(json.error || 'Login failed')
      await refreshSession()
      return true
    } catch (e: any) {
      toast.error(e.message)
      return false
    }
  }, [refreshSession])

  const logout = useCallback(async () => {
    await fetch('/api/auth', { method: 'DELETE' })
    setSession(null)
    setBranches([])
    setSelectedBranchIds([])
  }, [])

  const has = useCallback((perm: string) => {
    if (!session) return false
    return session.permissions.includes(perm)
  }, [session])

  // Session-level screen-permission matrix (gates NAV + screen rendering; see canScreen)
  const screenPerms = useMemo(() => {
    const map: Record<string, ScreenPermRow> = {}
    for (const row of session?.screenPermissions || []) map[row.screenKey] = row
    return map
  }, [session])
  const can = useCallback((screenKey: string, action: 'view' | 'add' | 'edit' | 'delete' | 'print' = 'view') =>
    canScreen(session, screenKey, action), [session])

  if (loadingSession) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-background">
        <div className="text-muted-foreground">Loading…</div>
      </div>
    )
  }

  if (!session) {
    return <LoginScreen login={login} />
  }

  // Filter nav by permissions (3-level: Module → Section → Screen) + session screen matrix
  const visibleNav = NAV.map((mod: NavModule) => {
    if ('key' in mod) {
      // Single-screen module (Dashboard)
      return has(mod.perm) && can(mod.key, 'view') ? mod : null
    }
    // Module with sections
    const visibleSections = mod.sections
      .map(section => {
        const visibleScreens = section.screens.filter(s => has(s.perm) && can(s.key, 'view'))
        return visibleScreens.length ? { ...section, screens: visibleScreens } : null
      })
      .filter(Boolean) as NavSection[]
    return visibleSections.length ? { ...mod, sections: visibleSections } : null
  }).filter(Boolean) as NavModule[]

  const brand = companyName || 'Contoura Gym'

  return (
    <AppContext.Provider value={{
      session, branches, selectedBranchIds, setSelectedBranchIds,
      has, can, screenPerms, companyName, setCompanyName, refreshSession, logout, login,
    }}>
      <div className="min-h-screen bg-muted/30">
        {/* Topbar */}
        <header className="sticky top-0 z-30 h-14 bg-background border-b flex items-center px-3 sm:px-6 gap-2">
          <Sheet open={sidebarOpen} onOpenChange={setSidebarOpen}>
            <SheetTrigger asChild>
              <Button variant="ghost" size="icon" className="lg:hidden">
                <Menu className="h-5 w-5" />
              </Button>
            </SheetTrigger>
            <SheetContent side="left" className="w-72 p-0">
              <SidebarContent
                nav={visibleNav}
                active={activeModule}
                onNavigate={(k) => { navigateTo(k as ModuleKey); setSidebarOpen(false) }}
                session={session}
                brand={brand}
                onLogout={logout}
              />
            </SheetContent>
          </Sheet>

          <div className="font-semibold text-lg flex items-center gap-2 min-w-0">
            <div className="h-7 w-7 rounded bg-primary/15 text-primary flex items-center justify-center text-sm font-bold shrink-0">C</div>
            <span className="hidden sm:inline truncate max-w-[220px] lg:max-w-[320px]" title={brand}>{brand}</span>
            <span className="sm:hidden text-base truncate max-w-[120px]">{companyName || 'Contoura'}</span>
          </div>

          <div className="flex-1" />

          <BranchSelector
            branches={branches}
            selected={selectedBranchIds}
            onChange={setSelectedBranchIds}
          />

          <ThemeToggle />

          <div className="hidden md:flex items-center gap-2 px-3 py-1.5 rounded border bg-muted/40">
            <div className="h-7 w-7 rounded-full bg-primary/15 text-primary flex items-center justify-center text-xs font-bold">
              {session.fullName.charAt(0).toUpperCase()}
            </div>
            <div className="text-xs leading-tight">
              <div className="font-medium">{session.fullName}</div>
              <div className="text-muted-foreground">{session.userType === 'Admin' ? 'Admin' : 'User'}</div>
            </div>
          </div>

          <Button variant="ghost" size="icon" onClick={logout} title="Logout">
            <LogOut className="h-4 w-4" />
          </Button>
        </header>

        <div className="flex">
          {/* Desktop Sidebar */}
          <aside className="hidden lg:block w-60 border-r bg-background min-h-[calc(100vh-3.5rem)] sticky top-14">
            <SidebarContent
              nav={visibleNav}
              active={activeModule}
              onNavigate={navigateTo}
              session={session}
              brand={brand}
              onLogout={logout}
            />
          </aside>

          {/* Main content */}
          <main className="flex-1 min-h-[calc(100vh-3.5rem)] p-4 sm:p-6">
            <ModuleRouter active={activeModule} setActive={setActiveModule} />
          </main>
        </div>
      </div>
    </AppContext.Provider>
  )
}

// =================================================================
// Theme Toggle
// =================================================================
function ThemeToggle() {
  const { theme, setTheme } = useTheme()
  const [mounted, setMounted] = useState(false)
  useEffect(() => setMounted(true), [])
  if (!mounted) return <Button variant="ghost" size="icon" className="h-9 w-9"><SunMoon className="h-4 w-4" /></Button>
  const isDark = theme === 'dark'
  return (
    <Button
      variant="ghost" size="icon" className="h-9 w-9"
      onClick={() => setTheme(isDark ? 'light' : 'dark')}
      title={isDark ? 'Switch to light theme' : 'Switch to dark theme'}
    >
      {isDark ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}
    </Button>
  )
}

// =================================================================
// Sidebar — nested Module → Section → Screen
// =================================================================
function SidebarContent({ nav, active, onNavigate, session, brand, onLogout }: any) {
  return (
    <div className="h-full flex flex-col">
      <div className="h-14 border-b flex items-center px-4 gap-2">
        <div className="h-7 w-7 rounded bg-primary/15 text-primary flex items-center justify-center text-sm font-bold">C</div>
        <div className="font-semibold truncate">{brand || 'Contoura Gym'}</div>
      </div>
      <nav className="flex-1 overflow-y-auto py-2 px-2 space-y-0.5 text-sm">
        {nav.map((mod: NavModule) => {
          if ('key' in mod) {
            const Icon = mod.icon
            // Real anchor link — the browser's right-click menu offers
            // "Open in new tab / window", and the URL can be opened directly.
            return (
              <a
                key={mod.key}
                href={`#/${mod.key}`}
                onClick={() => onNavigate(mod.key)}
                className={`w-full flex items-center gap-2 px-3 py-2 rounded hover:bg-muted ${active === mod.key ? 'bg-primary/10 text-primary font-medium' : 'text-foreground/80'}`}
              >
                <Icon className="h-4 w-4" />
                <span>{mod.label}</span>
              </a>
            )
          }
          return <NavModuleAccordion key={mod.label} mod={mod} active={active} onNavigate={onNavigate} />
        })}
      </nav>
      <div className="border-t p-3 text-xs text-muted-foreground">
        <div className="font-medium text-foreground">{session?.fullName}</div>
        <div>{session?.userType === 'Admin' ? 'Admin' : 'User'} · {session?.username}</div>
        <button onClick={onLogout} className="mt-2 flex items-center gap-1 text-red-600 hover:underline">
          <LogOut className="h-3 w-3" /> Logout
        </button>
      </div>
    </div>
  )
}

function NavModuleAccordion({ mod, active, onNavigate }: { mod: NavModule, active: ModuleKey, onNavigate: (k: ModuleKey) => void }) {
  const [open, setOpen] = useState(false)
  // Auto-expand if a screen under this module is active
  const sections = 'sections' in mod ? mod.sections : []
  const isActiveMod = sections.some(s => s.screens.some(sc => sc.key === active))
  useEffect(() => { if (isActiveMod) setOpen(true) }, [isActiveMod])
  if (!('sections' in mod) || !mod.sections) return null
  const Icon = mod.icon
  return (
    <div>
      <button
        onClick={() => setOpen(o => !o)}
        className={`w-full flex items-center gap-2 px-3 py-2 rounded hover:bg-muted text-foreground/80 ${isActiveMod ? 'text-foreground' : ''}`}
      >
        <Icon className="h-4 w-4" />
        <span className="flex-1 text-left font-medium">{mod.label}</span>
        <ChevronDown className={`h-4 w-4 transition-transform ${open ? 'rotate-180' : ''}`} />
      </button>
      {open && (
        <div className="ml-2 mt-0.5 space-y-0.5 border-l pl-2">
          {mod.sections.map((section: NavSection) => (
            <NavSectionAccordion key={section.label} section={section} active={active} onNavigate={onNavigate} />
          ))}
        </div>
      )}
    </div>
  )
}

function NavSectionAccordion({ section, active, onNavigate }: { section: NavSection, active: ModuleKey, onNavigate: (k: ModuleKey) => void }) {
  const [open, setOpen] = useState(false)
  const isActiveSection = section.screens.some(sc => sc.key === active)
  useEffect(() => { if (isActiveSection) setOpen(true) }, [isActiveSection])
  return (
    <div>
      <button
        onClick={() => setOpen(o => !o)}
        className={`w-full flex items-center gap-1.5 px-2 py-1.5 rounded hover:bg-muted text-xs ${isActiveSection ? 'text-foreground font-medium' : 'text-muted-foreground'}`}
      >
        <ChevronRight className={`h-3 w-3 transition-transform ${open ? 'rotate-90' : ''}`} />
        <span className="flex-1 text-left">{section.label}</span>
      </button>
      {open && (
        <div className="ml-3 mt-0.5 space-y-0.5">
          {section.screens.map((sc: NavScreen) => (
            <a
              key={sc.key}
              href={`#/${sc.key}`}
              onClick={() => onNavigate(sc.key)}
              className={`w-full text-left px-3 py-1.5 rounded hover:bg-muted text-xs block ${active === sc.key ? 'bg-primary/10 text-primary font-medium' : 'text-foreground/70'}`}
            >
              {sc.label}
            </a>
          ))}
        </div>
      )}
    </div>
  )
}

// =================================================================
// Branch Selector
// =================================================================
function BranchSelector({ branches, selected, onChange }: any) {
  const [open, setOpen] = useState(false)
  const all = selected.length === 0
  return (
    <div className="relative">
      <Button variant="outline" size="sm" onClick={() => setOpen(o => !o)} className="gap-1.5 max-w-[180px]">
        <Building2 className="h-3.5 w-3.5" />
        <span className="truncate">{all ? 'All branches' : `${selected.length} selected`}</span>
        <ChevronDown className="h-3 w-3" />
      </Button>
      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
          <div className="absolute right-0 mt-1 w-64 bg-background border rounded shadow-lg z-50 max-h-80 overflow-y-auto">
            <div className="p-2 border-b flex items-center justify-between">
              <span className="text-sm font-medium">Filter branches</span>
              <button onClick={() => onChange([])} className="text-xs text-primary hover:underline">All</button>
            </div>
            {branches.map((b: Branch) => (
              <label key={b.id} className="flex items-center gap-2 px-3 py-1.5 hover:bg-muted cursor-pointer text-sm">
                <input
                  type="checkbox"
                  checked={selected.includes(b.id)}
                  onChange={(e) => {
                    if (e.target.checked) onChange([...selected, b.id])
                    else onChange(selected.filter((x: string) => x !== b.id))
                  }}
                />
                <div className="flex-1">
                  <div className="font-medium">{b.name}</div>
                  <div className="text-xs text-muted-foreground">{b.code}{b.city ? ` · ${b.city}` : ''}</div>
                </div>
              </label>
            ))}
          </div>
        </>
      )}
    </div>
  )
}

// =================================================================
// Login
// =================================================================
function LoginScreen({ login }: { login: (u: string, p: string) => Promise<boolean> }) {
  const [username, setUsername] = useState('admin')
  const [password, setPassword] = useState('admin123')
  const [loading, setLoading] = useState(false)

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    setLoading(true)
    await login(username, password)
    setLoading(false)
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-muted/30 px-4">
      <Card className="w-full max-w-md">
        <CardHeader className="space-y-1">
          <div className="flex items-center gap-2">
            <div className="h-9 w-9 rounded bg-primary/15 text-primary flex items-center justify-center font-bold">C</div>
            <div>
              <CardTitle className="text-xl">Contoura Gym</CardTitle>
              <div className="text-xs text-muted-foreground">Management System</div>
            </div>
          </div>
        </CardHeader>
        <CardContent>
          <form onSubmit={submit} className="space-y-4">
            <div className="space-y-1.5">
              <Label htmlFor="u">Username</Label>
              <Input id="u" value={username} onChange={e => setUsername(e.target.value)} autoComplete="username" />
            </div>
            <div className="space-y-1.5">
              <Label htmlFor="p">Password</Label>
              <Input id="p" type="password" value={password} onChange={e => setPassword(e.target.value)} autoComplete="current-password" />
            </div>
            <Button type="submit" className="w-full" disabled={loading}>
              {loading ? 'Signing in…' : 'Sign In'}
            </Button>
            <div className="text-xs text-muted-foreground text-center pt-2 border-t">
              Default admin: <code className="font-mono">admin</code> / <code className="font-mono">admin123</code>
            </div>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}

// =================================================================
// Module Router
// =================================================================
function AccessDeniedPanel({ screenKey }: { screenKey: string }) {
  return (
    <div className="flex items-center justify-center min-h-[60vh]">
      <Card className="max-w-md w-full">
        <CardContent className="p-8 text-center">
          <ShieldAlert className="h-10 w-10 mx-auto text-destructive" />
          <div className="text-xl font-semibold mt-3">Access denied</div>
          <div className="text-sm text-muted-foreground mt-2">
            Your role does not have <b>View</b> permission for this screen
            {screenKey ? <span className="font-mono text-xs"> ({screenKey})</span> : null}.
            Contact an administrator to request access in Users &amp; Permissions.
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

// Compat redirect for consolidated/legacy admin keys (e.g. Roles, Permissions → Users & Permissions)
function RedirectToModule({ target, setActive }: { target: ModuleKey, setActive: (m: ModuleKey) => void }) {
  useEffect(() => { setActive(target) }, [target, setActive])
  return <div className="text-sm text-muted-foreground">Redirecting…</div>
}

function ModuleRouter({ active, setActive }: { active: ModuleKey, setActive: (m: ModuleKey) => void }) {
  const { can } = useApp()
  // Session-level screen gating: a saved permission row without View blocks rendering
  if (active !== 'login' && !can(active, 'view')) return <AccessDeniedPanel screenKey={active} />
  switch (active) {
    case 'dashboard': return <DashboardModule />
    // Finance → Vouchers
    case 'finance-voucher-bpv': return <VoucherScreenModule voucherType="BPV" title="Bank Payment Voucher" />
    case 'finance-voucher-brv': return <VoucherScreenModule voucherType="BRV" title="Bank Receipt Voucher" />
    case 'finance-voucher-cpv': return <VoucherScreenModule voucherType="CPV" title="Cash Payment Voucher" />
    case 'finance-voucher-crv': return <VoucherScreenModule voucherType="CRV" title="Cash Receipt Voucher" />
    case 'finance-voucher-jv': return <VoucherScreenModule voucherType="JV" title="Journal Voucher" />
    case 'finance-voucher-otb': return <OpeningTrialBalanceModule />
    case 'finance-voucher-cheques': return <ChequesModule />
    // Finance → Reports
    case 'finance-reports-aging': return <AgingReportsModule />
    case 'finance-reports-main': return <FinanceReportsModule />
    // Finance → Master Files
    case 'finance-coa': return <CoaModule />
    case 'finance-tax': return <TaxHeadsModule />
    case 'finance-master-files': return <FinanceMasterFilesModule />
    // Gym → Main
    case 'gym-members': return <MembersModule />
    case 'gym-memberships': return <MembershipsModule />
    case 'gym-attendance': return <AttendanceModule />
    case 'gym-fees': return <FeesModule />
    case 'gym-status': return <MemberStatusModule />
    case 'gym-freezes': return <FreezesModule />
    case 'gym-prospects': return <ProspectsModule />
    case 'gym-followups': return <FollowUpsModule />
    case 'gym-workout-assignment': return <WorkoutAssignmentModule />
    case 'gym-diet-assignment': return <DietAssignmentModule />
    case 'gym-progress': return <ProgressModule />
    // Gym → Reports
    case 'gym-reports': return <GymReportsModule />
    // Gym → Master Files
    case 'gym-exercises': return <ExercisesModule />
    case 'gym-workouts': return <WorkoutsModule />
    case 'gym-diet': return <DietModule />
    case 'gym-equipment': return <EquipmentModule />
    case 'gym-inventory': return <InventoryModule />
    case 'gym-master-files': return <GymMasterFilesModule />
    // Payroll → Main
    case 'payroll-staff': return <StaffModule />
    case 'payroll-staff-attendance': return <StaffAttendanceStub />
    case 'payroll-leaves': return <LeavesModule />
    case 'payroll-overtime': return <OvertimeModule />
    case 'payroll-payroll': return <PayrollModule />
    // Payroll → Reports
    case 'payroll-reports': return <PayrollReportsModule />
    // Payroll → Master Files
    case 'payroll-shifts': return <ShiftsModule />
    case 'payroll-calendar': return <CalendarModule />
    case 'payroll-master-files': return <PayrollMasterFilesModule />
    // Admin → Defaults
    case 'admin-company': return <CompanyModule />
    case 'admin-finance-defaults': return <FinanceDefaultsModule />
    case 'admin-account-mappings': return <AccountMappingsModule />
    case 'admin-coa-config': return <CoaConfigStub />
    case 'admin-accounting-defaults': return <AccountingDefaultsModule />
    // Admin → Reports
    case 'admin-audit': return <AuditModule />
    // Admin → Master Files
    case 'admin-branches': return <BranchesModule />
    case 'admin-users': return <UsersModule />
    case 'admin-roles': return <RedirectToModule target="admin-users" setActive={setActive} />
    case 'admin-permissions': return <RedirectToModule target="admin-users" setActive={setActive} />
    // Gym → Operations (new)
    case 'gym-fitness-goals': return <FitnessGoalsModule />
    case 'gym-body-progress': return <ProgressModule />
    case 'gym-pt-sessions': return <PTSessionsModule />
    case 'gym-trainer-availability': return <TrainerAvailabilityModule />
    case 'gym-trainer-schedule': return <TrainerScheduleModule />
    // Inventory → Transactions
    case 'inv-purchases': return <PurchasesModule />
    case 'inv-stock-movements': return <StockMovementsModule />
    case 'inv-equipment': return <EquipmentModule />
    // Inventory → Reports
    case 'inv-reports': return <InventoryReportsModule />
    // Inventory → Master
    case 'inv-items': return <InventoryModule />
    case 'inv-suppliers': return <SuppliersModule />
    case 'inv-master-files': return <RedirectToModule target="gym-master-files" setActive={setActive} />
    // HR Reports
    case 'hr-reports': return <HRReportsModule />
    default: return <DashboardModule />
  }
}

// =================================================================
// Page Header
// =================================================================
function PageHeader({ title, action, actionLabel }: { title: string, action?: () => void, actionLabel?: string }) {
  return (
    <div className="flex items-center justify-between mb-4 gap-2 flex-wrap">
      <h1 className="text-xl sm:text-2xl font-semibold tracking-tight">{title}</h1>
      {action && (
        <Button onClick={action} size="sm" className="gap-1.5">
          <Plus className="h-4 w-4" /> {actionLabel || 'Add'}
        </Button>
      )}
    </div>
  )
}

// Stub for many modules to keep file manageable; full implementations below
function NotImplemented({ name }: { name: string }) {
  return (
    <div className="flex items-center justify-center min-h-[60vh] text-muted-foreground">
      <div className="text-center">
        <div className="text-2xl font-medium">{name}</div>
        <div className="text-sm mt-2">Module under construction</div>
      </div>
    </div>
  )
}

// Placeholders — replaced below with actual implementations
function DashboardModule() { return <Dashboard /> }
function CoaModule() { return <CoaModuleImpl /> }
function TaxHeadsModule() { return <TaxHeadsModuleImpl /> }
function ChequesModule() { return <ChequesModuleImpl /> }
function OpeningTrialBalanceModule() { return <OpeningTrialBalanceModuleImpl /> }
function FinanceReportsModule() { return <FinanceReportsModuleImpl /> }
function AccountMappingsModule() { return <AccountMappingsModuleImpl /> }
function FinanceDefaultsModule() { return <FinanceDefaultsModuleImpl /> }
function MembersModule() { return <MembersModuleImpl /> }
function MembershipsModule() { return <MembershipsModuleImpl /> }
function AttendanceModule() { return <AttendanceModuleImpl /> }
function FeesModule() { return <FeesModuleImpl /> }
function ProspectsModule() { return <ProspectsModuleImpl /> }
function FreezesModule() { return <FreezesModuleImpl /> }
function FollowUpsModule() { return <FollowUpsModuleImpl /> }
function MemberStatusModule() { return <MemberStatusModuleImpl /> }
function ExercisesModule() { return <ExercisesModuleImpl /> }
function WorkoutsModule() { return <WorkoutsModuleImpl /> }
function DietModule() { return <DietModuleImpl /> }
function ProgressModule() { return <ProgressModuleImpl /> }
function EquipmentModule() { return <EquipmentModuleImpl /> }
function InventoryModule() { return <InventoryModuleImpl /> }
function StaffModule() { return <StaffModuleImpl /> }
function ShiftsModule() { return <ShiftsModuleImpl /> }
function CalendarModule() { return <CalendarModuleImpl /> }
function LeavesModule() { return <LeavesModuleImpl /> }
function OvertimeModule() { return <OvertimeModuleImpl /> }
function PayrollModule() { return <PayrollModuleImpl /> }
function CompanyModule() { return <CompanyModuleImpl /> }
function BranchesModule() { return <BranchesModuleImpl /> }
function UsersModule() { return <UsersModuleImpl /> }
function AuditModule() { return <AuditModuleImpl /> }
function GymMasterFilesModule() { return <MasterFilesScreen type="gym" title="Gym Master Files" /> }
function FinanceMasterFilesModule() { return <MasterFilesScreen type="finance" title="Finance Master Files" /> }
function PayrollMasterFilesModule() { return <MasterFilesScreen type="payroll" title="Payroll Master File" /> }
function PurchasesModule() { return <NotImplemented name="Purchases" /> }
function StockMovementsModule() { return <NotImplemented name="Stock Movements" /> }
function InventoryReportsModule() { return <ReportsListModule apiPath="/api/inventory-reports" title="Inventory Reports" /> }
function HRReportsModule() { return <ReportsListModule apiPath="/api/hr-reports" title="HR Reports" /> }
function SuppliersModule() { return <NotImplemented name="Suppliers" /> }

// New module screens for the restructured ERP navigation
function VoucherScreenModule({ voucherType, title }: { voucherType: string, title: string }) {
  return <BookVoucherScreenImpl voucherType={voucherType} title={title} />
}
function AgingReportsModule() { return <FinanceReportsModuleImpl presetReport="aging" /> }
function DietAssignmentModule() { return <NotImplemented name="Diet Assignment" /> }
function WorkoutAssignmentModule() { return <WorkoutAssignmentScreen /> }
function FitnessGoalsModule() { return <FitnessGoalsScreen /> }
function TrainerAvailabilityModule() { return <TrainerAvailabilityScreen /> }
function TrainerScheduleModule() { return <TrainerScheduleScreen /> }
function GymReportsModule() { return <ReportsListModule apiPath="/api/gym-reports" title="Gym Reports" /> }
function StaffAttendanceStub() { return <NotImplemented name="Staff Attendance" /> }
function PayrollReportsModule() { return <NotImplemented name="Payroll Reports" /> }
function CoaConfigStub() { return <NotImplemented name="COA Configuration" /> }
function AccountingDefaultsModule() { return <AdminDefaultsModuleImpl /> }
function PTSessionsModule() { return <PTSessionsModuleImpl /> }

// =================================================================
// Generic Reports List Module — shows report names directly on screen
// =================================================================
function ReportsListModule({ apiPath, title }: { apiPath: string, title: string }) {
  const { data, reload } = useFetch<any>(apiPath)
  const [selectedReport, setSelectedReport] = useState<string>('')
  const [reportData, setReportData] = useState<any>(null)
  const [loading, setLoading] = useState(false)

  const reports = data?.reports || []

  const runReport = async (key: string) => {
    setSelectedReport(key)
    setLoading(true)
    try {
      const res = await fetch(`${apiPath}?report=${key}`)
      const json = await res.json()
      if (!res.ok) throw new Error(json.error || 'Failed')
      setReportData(json.report)
    } catch (e: any) {
      toast.error(e.message)
      setReportData(null)
    } finally {
      setLoading(false)
    }
  }

  if (!selectedReport) {
    return (
      <div>
        <PageHeader title={title} />
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
          {reports.map((r: any) => (
            <Card key={r.key} className="cursor-pointer hover:bg-muted/30" onClick={() => runReport(r.key)}>
              <CardContent className="p-4">
                <div className="font-medium text-sm">{r.name}</div>
                <div className="text-xs text-muted-foreground mt-1">Click to view report</div>
              </CardContent>
            </Card>
          ))}
        </div>
      </div>
    )
  }

  const selectedReportInfo = reports.find((r: any) => r.key === selectedReport)

  return (
    <div>
      <PageHeader title={`${title} — ${selectedReportInfo?.name || selectedReport}`}
        action={() => { setSelectedReport(''); setReportData(null) }}
        actionLabel="Back to Reports"
      />
      {loading && <div className="text-muted-foreground text-sm">Loading report…</div>}
      {reportData && (
        <div className="overflow-x-auto">
          <DataTable
            columns={reportData.rows && reportData.rows.length > 0
              ? Object.keys(reportData.rows[0]).map((k: string) => ({
                  key: k, label: k.replace(/([A-Z])/g, ' $1').replace(/^./, c => c.toUpperCase()),
                  mono: ['id', 'memberId', 'code', 'employeeId'].includes(k),
                }))
              : []
            }
            rows={reportData.rows || []}
            empty="No data for this report"
          />
        </div>
      )}
    </div>
  )
}

// =================================================================
// Dashboard
// =================================================================
function Dashboard() {
  const { session, selectedBranchIds } = useApp()
  const branchesParam = selectedBranchIds.length ? `&branches=${selectedBranchIds.join(',')}` : ''
  const { data, loading, reload } = useFetch<any>(`/api/dashboard?${branchesParam}`)

  if (loading && !data) return <div className="text-muted-foreground">Loading dashboard…</div>

  const stats = data?.stats || {}
  const dueAlerts = data?.dueAlerts || []

  const cards = [
    { label: 'Members', value: stats.members ?? 0, sub: `${stats.activeMembers ?? 0} active`, icon: Users, perm: 'members.view' },
    { label: 'Attendance Today', value: stats.todayAttendance ?? 0, sub: 'check-ins', icon: CalendarCheck, perm: 'attendance.view' },
    { label: 'Unpaid Fees', value: fmtMoney(stats.unpaidFeesBalance), sub: 'balance due', icon: AlertCircle, perm: 'fees.view' },
    { label: "Today's Revenue", value: fmtMoney(stats.todayRevenue), sub: 'collected today', icon: Banknote, perm: 'finance.view' },
    { label: 'Prospects', value: stats.prospects ?? 0, sub: 'open leads', icon: UsersRound, perm: 'prospects.view' },
    { label: 'Vouchers Posted', value: stats.postedVouchers ?? 0, sub: `${stats.drafts ?? 0} drafts`, icon: FileText, perm: 'vouchers.view' },
    { label: 'Staff', value: stats.staff ?? 0, sub: 'active', icon: UserCog, perm: 'staff.view' },
    { label: 'Branches', value: stats.branches ?? 0, sub: 'accessible', icon: Building2, perm: 'branches.view' },
  ]

  return (
    <div>
      <PageHeader title="Dashboard" />
      <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-3">
        {cards.map(c => {
          if (!session?.permissions.includes(c.perm)) return null
          const Icon = c.icon
          return (
            <Card key={c.label} className="py-3">
              <CardContent className="px-3">
                <div className="flex items-start justify-between">
                  <div>
                    <div className="text-xs text-muted-foreground">{c.label}</div>
                    <div className="text-2xl font-semibold mt-0.5">{c.value}</div>
                    <div className="text-[11px] text-muted-foreground mt-0.5">{c.sub}</div>
                  </div>
                  <Icon className="h-4 w-4 text-muted-foreground" />
                </div>
              </CardContent>
            </Card>
          )
        })}
      </div>

      <div className="mt-6">
        <div className="flex items-center justify-between mb-2">
          <h2 className="font-semibold text-lg">Due / Grace Alerts</h2>
          <Button variant="ghost" size="sm" onClick={reload}>Refresh</Button>
        </div>
        <Card>
          <CardContent className="p-0">
            {dueAlerts.length === 0 ? (
              <div className="text-center py-8 text-muted-foreground text-sm">No outstanding dues within grace period</div>
            ) : (
              <div className="overflow-x-auto">
                <table className="w-full text-sm">
                  <thead className="border-b bg-muted/40">
                    <tr>
                      <th className="text-left px-3 py-2 font-medium">Member</th>
                      <th className="text-left px-3 py-2 font-medium">Phone</th>
                      <th className="text-left px-3 py-2 font-medium">Fee #</th>
                      <th className="text-left px-3 py-2 font-medium">Due Date</th>
                      <th className="text-left px-3 py-2 font-medium">Grace</th>
                      <th className="text-right px-3 py-2 font-medium">Balance</th>
                      <th className="text-left px-3 py-2 font-medium">Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {dueAlerts.map((a: any) => (
                      <tr key={a.feeId} className="border-b last:border-0 hover:bg-muted/30">
                        <td className="px-3 py-2 font-medium">{a.memberName}</td>
                        <td className="px-3 py-2 text-muted-foreground">{a.phone}</td>
                        <td className="px-3 py-2">{a.feeNo}</td>
                        <td className="px-3 py-2">{fmtDateStr(a.dueDate)}</td>
                        <td className="px-3 py-2">{a.graceDays}d</td>
                        <td className="px-3 py-2 text-right font-mono">{fmtMoney(a.balance)}</td>
                        <td className="px-3 py-2">
                          <Badge variant={a.alertStatus === 'Overdue' ? 'destructive' : 'secondary'}>
                            {a.alertStatus}
                          </Badge>
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
