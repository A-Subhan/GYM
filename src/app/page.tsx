'use client'

import { useEffect, useState, useCallback, type ReactNode } from 'react'
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
import { toast } from 'sonner'
import {
  LayoutDashboard, Wallet, Users, ClipboardList, Dumbbell, Apple,
  UserCog, Calendar, Receipt, Stethoscope, FileText, Settings, LogOut,
  Menu, ChevronDown, Search, Plus, Edit, Trash2, Eye, X,
  BarChart3, BookOpen, UsersRound, CalendarCheck, DonutIcon, Coins,
  Briefcase, Truck, ShieldCheck, Building2, IdCard, ScrollText,
  ListTree, Tag, FileBarChart, CheckCircle2, AlertCircle, Banknote,
  Layers, Crown, Cookie, BanknoteIcon, Send, Activity, Hand,
  AlertTriangle, Check, Filter, Download, Printer,
} from 'lucide-react'
import { format as fmtDate } from 'date-fns'
import {
  CoaModule as CoaModuleImpl,
  VouchersModule as VouchersModuleImpl,
  TaxHeadsModule as TaxHeadsModuleImpl,
  ChequesModule as ChequesModuleImpl,
  FinanceReportsModule as FinanceReportsModuleImpl,
  AccountMappingsModule as AccountMappingsModuleImpl,
  FinanceDefaultsModule as FinanceDefaultsModuleImpl,
  AdminDefaultsModule as AdminDefaultsModuleImpl,
  PeriodsModule as PeriodsModuleImpl,
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
  PosModule as PosModuleImpl,
  StaffModule as StaffModuleImpl,
  ShiftsModule as ShiftsModuleImpl,
  CalendarModule as CalendarModuleImpl,
  LeavesModule as LeavesModuleImpl,
  OvertimeModule as OvertimeModuleImpl,
  PayrollModule as PayrollModuleImpl,
  CompanyModule as CompanyModuleImpl,
  UsersModule as UsersModuleImpl,
  RolesModule as RolesModuleImpl,
  AuditModule as AuditModuleImpl,
} from './module-pages'
import { BranchesModule as BranchesModuleImpl } from './modules'
import { AppContext, type AppCtx, type SessionUser, type Branch, useApp } from './app-context'

// =================================================================
// Auth context — types and useApp hook imported from ./app-context
// =================================================================

// =================================================================
// Module router — all module components live in this file (avoids
// multi-route restriction of the sandbox)
// =================================================================
type ModuleKey =
  | 'dashboard' | 'login'
  // Finance
  | 'finance-coa' | 'finance-vouchers' | 'finance-tax' | 'finance-cheques'
  | 'finance-reports' | 'finance-mappings' | 'finance-defaults' | 'finance-periods'
  // Gym
  | 'gym-members' | 'gym-memberships' | 'gym-attendance' | 'gym-fees'
  | 'gym-prospects' | 'gym-freezes' | 'gym-followups' | 'gym-status'
  | 'gym-exercises' | 'gym-workouts' | 'gym-diet' | 'gym-progress'
  // Equipment + Inventory + POS
  | 'equipment' | 'inventory' | 'pos'
  // Staff + Payroll
  | 'staff' | 'staff-shifts' | 'staff-calendar' | 'staff-leaves' | 'staff-overtime'
  | 'payroll'
  // Admin
  | 'admin-defaults' | 'admin-company' | 'admin-branches' | 'admin-users' | 'admin-roles'
  | 'admin-audit'

const NAV = [
  { key: 'dashboard', label: 'Dashboard', icon: LayoutDashboard, perm: 'dashboard.view' },
  {
    label: 'Finance', icon: Wallet, children: [
      { key: 'finance-voucher-crv', label: 'Cash Receipt Voucher', perm: 'vouchers.view' },
      { key: 'finance-voucher-cpv', label: 'Cash Payment Voucher', perm: 'vouchers.view' },
      { key: 'finance-voucher-brv', label: 'Bank Receipt Voucher', perm: 'vouchers.view' },
      { key: 'finance-voucher-bpv', label: 'Bank Payment Voucher', perm: 'vouchers.view' },
      { key: 'finance-voucher-jv', label: 'Journal Voucher', perm: 'vouchers.view' },
      { key: 'finance-voucher-otb', label: 'Opening Trial Balance', perm: 'vouchers.view' },
      { key: 'finance-voucher-cheques', label: 'Update Cheque Status', perm: 'cheques.view' },
      { key: 'finance-reports', label: 'Finance Reports', perm: 'finance.reports' },
      { key: 'finance-coa', label: 'Chart of Accounts', perm: 'finance.coa' },
      { key: 'finance-tax', label: 'Tax Heads', perm: 'tax.view' },
      { key: 'finance-mappings', label: 'Account Mappings', perm: 'accountMappings.view' },
      { key: 'finance-defaults', label: 'Finance Defaults', perm: 'finance.settings' },
      { key: 'finance-periods', label: 'Accounting Periods', perm: 'finance.periods' },
    ],
  },
  {
    label: 'Gym', icon: Dumbbell, children: [
      { key: 'gym-members', label: 'Members', perm: 'members.view' },
      { key: 'gym-memberships', label: 'Membership Plans', perm: 'memberships.view' },
      { key: 'gym-attendance', label: 'Attendance', perm: 'attendance.view' },
      { key: 'gym-fees', label: 'Fees & Invoices', perm: 'fees.view' },
      { key: 'gym-prospects', label: 'Prospects / Inquiries', perm: 'prospects.view' },
      { key: 'gym-freezes', label: 'Membership Freeze', perm: 'freeze.view' },
      { key: 'gym-followups', label: 'Member Follow Up', perm: 'followups.view' },
      { key: 'gym-status', label: 'Member Status', perm: 'members.status' },
      { key: 'gym-exercises', label: 'Exercises', perm: 'workouts.view' },
      { key: 'gym-workouts', label: 'Workout Plans', perm: 'workouts.view' },
      { key: 'gym-diet', label: 'Diet Plans', perm: 'diet.view' },
      { key: 'gym-progress', label: 'Progress Tracking', perm: 'progress.view' },
    ],
  },
  {
    label: 'Equipment & Inventory', icon: Truck, children: [
      { key: 'equipment', label: 'Equipment', perm: 'equipment.view' },
      { key: 'inventory', label: 'Inventory', perm: 'inventory.view' },
      { key: 'pos', label: 'POS / Counter Sales', perm: 'pos.view' },
    ],
  },
  {
    label: 'HR & Payroll', icon: UserCog, children: [
      { key: 'staff', label: 'Staff', perm: 'staff.view' },
      { key: 'staff-shifts', label: 'Shifts', perm: 'shifts.view' },
      { key: 'staff-calendar', label: 'Calendar', perm: 'calendar.view' },
      { key: 'staff-leaves', label: 'Leaves', perm: 'leaves.view' },
      { key: 'staff-overtime', label: 'Overtime', perm: 'overtime.view' },
      { key: 'payroll', label: 'Payroll', perm: 'payroll.view' },
    ],
  },
  {
    label: 'Admin', icon: Settings, children: [
      { key: 'admin-defaults', label: 'Defaults', perm: 'company.view' },
      { key: 'admin-company', label: 'Company', perm: 'company.view' },
      { key: 'admin-branches', label: 'Branches', perm: 'branches.view' },
      { key: 'admin-users', label: 'Users, Roles & Permissions', perm: 'users.view' },
      { key: 'admin-audit', label: 'Audit Log', perm: 'audit.view' },
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
  const [companyName, setCompanyName] = useState('Contoura Gym')
  const [session, setSession] = useState<SessionUser | null>(null)
  const [loadingSession, setLoadingSession] = useState(true)
  const [branches, setBranches] = useState<Branch[]>([])
  const [selectedBranchIds, setSelectedBranchIds] = useState<string[]>([])
  const [activeModule, setActiveModule] = useState<ModuleKey>('dashboard')
  const [sidebarOpen, setSidebarOpen] = useState(false)

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

  useEffect(() => { refreshSession() }, [refreshSession])

  useEffect(() => {
    fetch('/api/company').then(r => r.json()).then(d => {
      if (d.company?.name) setCompanyName(d.company.name)
    }).catch(() => {})
  }, [])

  useEffect(() => {
    if (session) {
      loadBranches()
    } else {
      setActiveModule('login')
    }
  }, [session, loadBranches])

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

  // Filter nav by permissions
  const visibleNav = NAV.map(group => {
    if ((group as any).key) return group
    const children = (group as any).children.filter((c: any) => has(c.perm))
    return children.length ? { ...group, children } : null
  }).filter(Boolean) as any[]

  return (
    <AppContext.Provider value={{
      session, branches, selectedBranchIds, setSelectedBranchIds,
      has, refreshSession, logout, login,
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
                onNavigate={(k) => { setActiveModule(k); setSidebarOpen(false) }}
                session={session}
                onLogout={logout}
              />
            </SheetContent>
          </Sheet>

          <div className="font-semibold text-lg flex items-center gap-2">
            <div className="h-7 w-7 rounded bg-primary/15 text-primary flex items-center justify-center text-sm font-bold">C</div>
            <span className="hidden sm:inline">{companyName}</span>
            <span className="sm:hidden text-base">{companyName.slice(0, 8)}</span>
          </div>

          <div className="flex-1" />

          <BranchSelector
            branches={branches}
            selected={selectedBranchIds}
            onChange={setSelectedBranchIds}
          />

          <div className="hidden md:flex items-center gap-2 px-3 py-1.5 rounded border bg-muted/40">
            <div className="h-7 w-7 rounded-full bg-primary/15 text-primary flex items-center justify-center text-xs font-bold">
              {session.fullName.charAt(0).toUpperCase()}
            </div>
            <div className="text-xs leading-tight">
              <div className="font-medium">{session.fullName}</div>
              <div className="text-muted-foreground">{session.roleName}</div>
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
              onNavigate={setActiveModule}
              session={session}
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
// Sidebar
// =================================================================
function SidebarContent({ nav, active, onNavigate, session, onLogout }: any) {
  return (
    <div className="h-full flex flex-col">
      <div className="h-14 border-b flex items-center px-4 gap-2">
        <div className="h-7 w-7 rounded bg-primary/15 text-primary flex items-center justify-center text-sm font-bold">C</div>
        <div className="font-semibold">{companyName}</div>
      </div>
      <nav className="flex-1 overflow-y-auto py-2 px-2 space-y-0.5 text-sm">
        {nav.map((item: any) => {
          if (item.key) {
            const Icon = item.icon
            return (
              <button
                key={item.key}
                onClick={() => onNavigate(item.key)}
                className={`w-full flex items-center gap-2 px-3 py-2 rounded hover:bg-muted ${active === item.key ? 'bg-primary/10 text-primary font-medium' : 'text-foreground/80'}`}
              >
                <Icon className="h-4 w-4" />
                <span>{item.label}</span>
              </button>
            )
          }
          const Icon = item.icon
          return (
            <CollapsibleNav key={item.label} icon={Icon} label={item.label}>
              {item.children.map((c: any) => (
                <button
                  key={c.key}
                  onClick={() => onNavigate(c.key)}
                  className={`w-full text-left px-3 py-1.5 rounded hover:bg-muted ${active === c.key ? 'bg-primary/10 text-primary font-medium' : 'text-foreground/70'}`}
                >
                  {c.label}
                </button>
              ))}
            </CollapsibleNav>
          )
        })}
      </nav>
      <div className="border-t p-3 text-xs text-muted-foreground">
        <div className="font-medium text-foreground">{session?.fullName}</div>
        <div>{session?.roleName} · {session?.username}</div>
        <button onClick={onLogout} className="mt-2 flex items-center gap-1 text-red-600 hover:underline">
          <LogOut className="h-3 w-3" /> Logout
        </button>
      </div>
    </div>
  )
}

function CollapsibleNav({ icon: Icon, label, children }: { icon: any, label: string, children: ReactNode }) {
  const [open, setOpen] = useState(false)
  return (
    <div>
      <button
        onClick={() => setOpen(o => !o)}
        className="w-full flex items-center gap-2 px-3 py-2 rounded hover:bg-muted text-foreground/80"
      >
        <Icon className="h-4 w-4" />
        <span className="flex-1 text-left">{label}</span>
        <ChevronDown className={`h-4 w-4 transition-transform ${open ? 'rotate-180' : ''}`} />
      </button>
      {open && <div className="ml-4 mt-0.5 space-y-0.5 border-l pl-2">{children}</div>}
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
              <CardTitle className="text-xl">{companyName}</CardTitle>
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
function ModuleRouter({ active, setActive }: { active: ModuleKey, setActive: (m: ModuleKey) => void }) {
  switch (active) {
    case 'dashboard': return <DashboardModule />
    case 'finance-coa': return <CoaModule />
    case 'finance-vouchers': return <VouchersModule />
    case 'finance-voucher-crv': return <VouchersModule presetType="CRV" presetTitle="Cash Receipt Voucher" />
    case 'finance-voucher-cpv': return <VouchersModule presetType="CPV" presetTitle="Cash Payment Voucher" />
    case 'finance-voucher-brv': return <VouchersModule presetType="BRV" presetTitle="Bank Receipt Voucher" />
    case 'finance-voucher-bpv': return <VouchersModule presetType="BPV" presetTitle="Bank Payment Voucher" />
    case 'finance-voucher-jv': return <VouchersModule presetType="JV" presetTitle="Journal Voucher" />
    case 'finance-voucher-otb': return <OpeningTrialBalanceScreen />
    case 'finance-voucher-cheques': return <ChequesModule />
    case 'finance-tax': return <TaxHeadsModule />
    case 'finance-cheques': return <ChequesModule />
    case 'finance-reports': return <FinanceReportsModule />
    case 'finance-mappings': return <AccountMappingsModule />
    case 'finance-defaults': return <FinanceDefaultsModule />
    case 'finance-periods': return <PeriodsModule />
    case 'gym-members': return <MembersModule />
    case 'gym-memberships': return <MembershipsModule />
    case 'gym-attendance': return <AttendanceModule />
    case 'gym-fees': return <FeesModule />
    case 'gym-prospects': return <ProspectsModule />
    case 'gym-freezes': return <FreezesModule />
    case 'gym-followups': return <FollowUpsModule />
    case 'gym-status': return <MemberStatusModule />
    case 'gym-exercises': return <ExercisesModule />
    case 'gym-workouts': return <WorkoutsModule />
    case 'gym-diet': return <DietModule />
    case 'gym-progress': return <ProgressModule />
    case 'equipment': return <EquipmentModule />
    case 'inventory': return <InventoryModule />
    case 'pos': return <PosModule />
    case 'staff': return <StaffModule />
    case 'staff-shifts': return <ShiftsModule />
    case 'staff-calendar': return <CalendarModule />
    case 'staff-leaves': return <LeavesModule />
    case 'staff-overtime': return <OvertimeModule />
    case 'payroll': return <PayrollModule />
    case 'admin-defaults': return <AdminDefaultsModule />
    case 'admin-company': return <CompanyModule />
    case 'admin-branches': return <BranchesModule />
    case 'admin-users': return <UsersModule />
    case 'admin-roles': return <RolesModule />
    case 'admin-audit': return <AuditModule />
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
function VouchersModule() { return <VouchersModuleImpl /> }
function TaxHeadsModule() { return <TaxHeadsModuleImpl /> }
function ChequesModule() { return <ChequesModuleImpl /> }
function FinanceReportsModule() { return <FinanceReportsModuleImpl /> }
function AccountMappingsModule() { return <AccountMappingsModuleImpl /> }
function FinanceDefaultsModule() { return <FinanceDefaultsModuleImpl /> }
function PeriodsModule() { return <PeriodsModuleImpl /> }
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
function PosModule() { return <PosModuleImpl /> }
function StaffModule() { return <StaffModuleImpl /> }
function ShiftsModule() { return <ShiftsModuleImpl /> }
function CalendarModule() { return <CalendarModuleImpl /> }
function LeavesModule() { return <LeavesModuleImpl /> }
function OvertimeModule() { return <OvertimeModuleImpl /> }
function PayrollModule() { return <PayrollModuleImpl /> }
function CompanyModule() { return <CompanyModuleImpl /> }
function BranchesModule() { return <BranchesModuleImpl /> }
function UsersModule() { return <UsersModuleImpl /> }
function RolesModule() { return <RolesModuleImpl /> }
function AuditModule() { return <AuditModuleImpl /> }
function AdminDefaultsModule() { return <AdminDefaultsModuleImpl /> }

// =================================================================
// Opening Trial Balance — COA grid with Dr/Cr, allows unbalanced save
// =================================================================
function OpeningTrialBalanceScreen() {
  const { has } = useApp()
  const [entries, setEntries] = useState<Record<string, { debit: number; credit: number }>>({})
  const [saving, setSaving] = useState(false)

  const { data, reload } = useFetch<any>('/api/opening-balance')

  useEffect(() => {
    if (data?.accounts) {
      const map: Record<string, { debit: number; credit: number }> = {}
      for (const a of data.accounts) {
        map[a.id] = { debit: a.debit || 0, credit: a.credit || 0 }
      }
      setEntries(map)
    }
  }, [data])

  const accounts = data?.accounts || []
  const hasExisting = data?.hasExisting || false

  const totalDebit = Object.values(entries).reduce((s, e) => s + (Number(e.debit) || 0), 0)
  const totalCredit = Object.values(entries).reduce((s, e) => s + (Number(e.credit) || 0), 0)
  const difference = totalCredit - totalDebit

  const setDr = (id: string, val: number) => {
    if (val < 0) val = 0
    setEntries(prev => ({ ...prev, [id]: { debit: val, credit: 0 } }))
  }
  const setCr = (id: string, val: number) => {
    if (val < 0) val = 0
    setEntries(prev => ({ ...prev, [id]: { debit: 0, credit: val } }))
  }

  const save = async () => {
    // NO balance requirement — OTB is allowed to save unbalanced
    setSaving(true)
    try {
      const entryArray = Object.entries(entries).map(([id, v]) => ({ id, debit: Number(v.debit) || 0, credit: Number(v.credit) || 0 }))
      await apiPost('/api/opening-balance', { entries: entryArray })
      toast.success(hasExisting ? 'Opening balances updated' : 'Opening balances saved')
      reload()
    } catch (e: any) {
      toast.error(e.message)
    } finally {
      setSaving(false)
    }
  }

  return (
    <div>
      <PageHeader title="Opening Trial Balance"
        action={has('vouchers.add') ? save : undefined}
        actionLabel={saving ? 'Saving…' : (hasExisting ? 'Save Changes' : 'Save')}
      />
      <div className="text-xs text-muted-foreground mb-3">
        Enter opening amounts against detail accounts. Debit OR Credit per account. Unbalanced entries are allowed.
      </div>
      <div className="border rounded overflow-x-auto max-h-[65vh] overflow-y-auto">
        <table className="w-full text-sm">
          <thead className="bg-muted/50 border-b sticky top-0 z-10">
            <tr>
              <th className="px-3 py-2 text-left font-medium">Code</th>
              <th className="px-3 py-2 text-left font-medium">Account Name</th>
              <th className="px-3 py-2 text-left font-medium">Type</th>
              <th className="px-3 py-2 text-right font-medium w-32">Debit</th>
              <th className="px-3 py-2 text-right font-medium w-32">Credit</th>
            </tr>
          </thead>
          <tbody>
            {accounts.map((a: any) => (
              <tr key={a.id} className={"border-b last:border-0 hover:bg-muted/30 " + (!a.isActive ? 'opacity-50' : '')}>
                <td className="px-3 py-1.5 font-mono text-xs">{a.code}</td>
                <td className="px-3 py-1.5">{a.name}{!a.isActive && <span className="ml-1 text-xs text-muted-foreground">(inactive)</span>}</td>
                <td className="px-3 py-1.5 text-xs">{a.accountType}</td>
                <td className="px-3 py-1.5"><Input type="number" min={0} step="0.01" value={entries[a.id]?.debit || ''} onChange={e => setDr(a.id, Number(e.target.value))} className="h-7 text-right" placeholder="0" /></td>
                <td className="px-3 py-1.5"><Input type="number" min={0} step="0.01" value={entries[a.id]?.credit || ''} onChange={e => setCr(a.id, Number(e.target.value))} className="h-7 text-right" placeholder="0" /></td>
              </tr>
            ))}
            {accounts.length === 0 && <tr><td colSpan={5} className="px-3 py-8 text-center text-muted-foreground">No detail accounts found in COA.</td></tr>}
          </tbody>
        </table>
      </div>
      <div className="sticky bottom-0 mt-3 bg-background border rounded p-3 flex items-center gap-6 shadow">
        <div className="text-sm"><span className="text-muted-foreground">Total Debit: </span><span className="font-mono font-semibold">{fmtMoney(totalDebit)}</span></div>
        <div className="text-sm"><span className="text-muted-foreground">Total Credit: </span><span className="font-mono font-semibold">{fmtMoney(totalCredit)}</span></div>
        <div className="text-sm"><span className="text-muted-foreground">Difference (Cr − Dr): </span><span className={"font-mono font-semibold " + (Math.abs(difference) < 0.01 ? 'text-green-600' : 'text-amber-600')}>{difference > 0 ? '+' : ''}{fmtMoney(difference)}</span></div>
        <div className="flex-1" />
        <div className={"text-xs font-medium " + (Math.abs(difference) < 0.01 ? 'text-green-600' : 'text-amber-600')}>{Math.abs(difference) < 0.01 ? 'Balanced' : 'Unbalanced (save allowed)'}</div>
      </div>
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
