'use client'

import { useEffect, useState, useCallback, Fragment, type ReactNode } from 'react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription,
} from '@/components/ui/dialog'
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select'
import { Badge } from '@/components/ui/badge'
import { Textarea } from '@/components/ui/textarea'
import { Switch } from '@/components/ui/switch'
import { Checkbox } from '@/components/ui/checkbox'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'
import { toast } from 'sonner'
import { Plus, Search, Edit, Trash2, Eye, X, Save, ChevronDown, ChevronRight, Download, Printer, Send, Snowflake } from 'lucide-react'
import { useApp } from './app-context'

// Re-export useApp for convenience
export { useApp }
export type { SessionUser, Branch, AppCtx } from './app-context'

// =================================================================
// Hooks
// =================================================================
export function useFetch<T>(url: string | null) {
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

export async function apiPost(url: string, body: any) {
  const res = await fetch(url, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  const json = await res.json()
  if (!res.ok) throw new Error(json.error || 'Failed')
  return json
}

export async function apiPatch(url: string, body: any) {
  const res = await fetch(url, {
    method: 'PATCH', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  const json = await res.json()
  if (!res.ok) throw new Error(json.error || 'Failed')
  return json
}

export async function apiDelete(url: string) {
  const res = await fetch(url, { method: 'DELETE' })
  const json = await res.json()
  if (!res.ok) throw new Error(json.error || 'Failed')
  return json
}

// =================================================================
// Common UI
// =================================================================
export function fmtMoney(n: number | null | undefined) {
  if (n === null || n === undefined) return '—'
  return Number(n).toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 2 })
}

export function fmtDateStr(d: string | Date | null | undefined) {
  if (!d) return '—'
  try { return new Intl.DateTimeFormat('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }).format(new Date(d)) } catch { return '—' }
}

export function fmtDateTime(d: string | Date | null | undefined) {
  if (!d) return '—'
  try { return new Intl.DateTimeFormat('en-GB', { day: '2-digit', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }).format(new Date(d)) } catch { return '—' }
}

export function PageHeader({ title, action, actionLabel }: { title: string, action?: () => void, actionLabel?: string }) {
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

export function SearchInput({ value, onChange, placeholder }: any) {
  return (
    <div className="relative">
      <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
      <Input
        value={value}
        onChange={e => onChange(e.target.value)}
        placeholder={placeholder || 'Search…'}
        className="pl-8 w-full"
      />
    </div>
  )
}

export function EmptyState({ message }: { message: string }) {
  return <div className="text-center py-8 text-muted-foreground text-sm">{message}</div>
}

// ============================================================================
// Gym-themed loading animation — cycles through 4 exercises (bench press,
// squat, push-up, pull-up) using lightweight inline SVG + CSS keyframes.
// Respects prefers-reduced-motion (shows a static dumbbell icon).
// ============================================================================
export function GymLoader({ size = 48, label = 'Loading…' }: { size?: number; label?: string }) {
  const exercises = ['Bench Press', 'Squat', 'Push-Up', 'Pull-Up']
  return (
    <div className="flex flex-col items-center justify-center gap-3" style={{ minHeight: size * 2 }}>
      <style>{`
        @keyframes gym-bounce { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-${size * 0.15}px); } }
        @keyframes gym-rotate { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
        @keyframes gym-fade { 0%, 30% { opacity: 1; } 33%, 63% { opacity: 0; } 66%, 100% { opacity: 0; } }
        .gym-icon-wrap { animation: gym-bounce 0.8s ease-in-out infinite; }
        .gym-spinner { animation: gym-rotate 1.2s linear infinite; }
        .gym-label-0 { animation: gym-fade 3.2s infinite; }
        .gym-label-1 { animation: gym-fade 3.2s infinite; animation-delay: 0.8s; }
        .gym-label-2 { animation: gym-fade 3.2s infinite; animation-delay: 1.6s; }
        .gym-label-3 { animation: gym-fade 3.2s infinite; animation-delay: 2.4s; }
        @media (prefers-reduced-motion: reduce) {
          .gym-icon-wrap, .gym-spinner, .gym-label-0, .gym-label-1, .gym-label-2, .gym-label-3 { animation: none; }
          .gym-label-0 { opacity: 1; }
          .gym-label-1, .gym-label-2, .gym-label-3 { opacity: 0; }
        }
      `}</style>
      <div className="gym-icon-wrap" style={{ width: size, height: size }}>
        <svg width={size} height={size} viewBox="0 0 48 48" fill="none" xmlns="http://www.w3.org/2000/svg">
          {/* Dumbbell */}
          <rect x="4" y="20" width="4" height="8" rx="1" fill="currentColor" opacity="0.8"/>
          <rect x="8" y="18" width="3" height="12" rx="1" fill="currentColor"/>
          <rect x="11" y="23" width="26" height="2" rx="1" fill="currentColor"/>
          <rect x="37" y="18" width="3" height="12" rx="1" fill="currentColor"/>
          <rect x="40" y="20" width="4" height="8" rx="1" fill="currentColor" opacity="0.8"/>
        </svg>
      </div>
      <div className="relative h-5">
        {exercises.map((ex, i) => (
          <span key={ex} className={`text-xs text-muted-foreground absolute gym-label-${i}`} style={{ left: '50%', transform: 'translateX(-50%)', whiteSpace: 'nowrap' }}>
            {ex}
          </span>
        ))}
      </div>
      {label && <span className="text-xs text-muted-foreground">{label}</span>}
    </div>
  )
}

export function StatusBadge({ status }: { status: string }) {
  const map: Record<string, any> = {
    Active: 'default', Posted: 'default', Completed: 'default', Cleared: 'default', Paid: 'default', Approved: 'default', Converted: 'default',
    Draft: 'secondary', Pending: 'secondary', Hold: 'secondary', Unpaid: 'secondary', Partial: 'secondary',
    Reversed: 'destructive', Rejected: 'destructive', Cancelled: 'destructive', Suspended: 'destructive', Inactive: 'destructive', Late: 'destructive', Overdue: 'destructive', Broken: 'destructive', Bounced: 'destructive',
  }
  return <Badge variant={map[status] || 'secondary'}>{status}</Badge>
}

export function Modal({ open, onClose, title, children, footer, size = 'md' }: {
  open: boolean, onClose: () => void, title: string, children: ReactNode, footer?: ReactNode, size?: 'sm' | 'md' | 'lg' | 'xl'
}) {
  const maxW = { sm: 'sm:max-w-md', md: 'sm:max-w-lg', lg: 'sm:max-w-2xl', xl: 'sm:max-w-4xl' }[size]
  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className={`${maxW} max-h-[92vh] overflow-y-auto`}>
        <DialogHeader>
          <DialogTitle>{title}</DialogTitle>
        </DialogHeader>
        {children}
        {footer && <DialogFooter className="gap-2">{footer}</DialogFooter>}
      </DialogContent>
    </Dialog>
  )
}

export function FormRow({ label, children, required }: { label: string, children: ReactNode, required?: boolean }) {
  return (
    <div className="space-y-1.5">
      <Label className="text-xs">{label}{required && <span className="text-red-500"> *</span>}</Label>
      {children}
    </div>
  )
}

export function Toolbar({ children }: { children: ReactNode }) {
  return <div className="flex items-center gap-2 flex-wrap mb-3">{children}</div>
}

// =================================================================
// ActionPanel — the shared LEFT-side action panel (Add / Edit / Delete /
// Print) used by every screen that requests "action panel on the left".
// Buttons are context-aware: Edit/Delete/Print enable when a row is selected.
// =================================================================
export type PanelAction = {
  label: string
  icon?: any
  onClick?: () => void
  disabled?: boolean
  variant?: 'default' | 'outline' | 'destructive' | 'ghost' | 'secondary'
  hidden?: boolean
  title?: string
}

export function ActionPanel({ actions, title = 'Actions' }: { actions: PanelAction[], title?: string }) {
  const visible = actions.filter(a => !a.hidden)
  return (
    <Card className="w-36 sm:w-40 shrink-0 self-start lg:sticky lg:top-20">
      <CardContent className="p-2.5 space-y-1.5">
        <div className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground px-1 pb-1">{title}</div>
        {visible.map(a => {
          const Icon = a.icon
          return (
            <Button
              key={a.label}
              variant={a.variant || 'outline'}
              size="sm"
              className="w-full justify-start gap-1.5"
              onClick={a.onClick}
              disabled={a.disabled}
              title={a.title || a.label}
            >
              {Icon ? <Icon className="h-3.5 w-3.5" /> : null}
              {a.label}
            </Button>
          )
        })}
      </CardContent>
    </Card>
  )
}

/** Screen layout with the action panel docked on the LEFT of the content. */
export function ScreenShell({ actions, children, panelTitle }: { actions: PanelAction[], children: ReactNode, panelTitle?: string }) {
  return (
    <div className="flex flex-col lg:flex-row gap-4 items-start">
      <ActionPanel actions={actions} title={panelTitle} />
      <div className="flex-1 min-w-0 w-full">{children}</div>
    </div>
  )
}

export function DataTable({ columns, rows, onRowClick, empty = 'No records' }: any) {
  if (!rows || rows.length === 0) {
    return <div className="text-center py-8 text-muted-foreground text-sm">{empty}</div>
  }
  return (
    <div className="overflow-x-auto border rounded">
      <table className="w-full text-sm">
        <thead className="bg-muted/50 border-b">
          <tr>
            {columns.map((c: any) => (
              <th key={c.key} className={`px-3 py-2 font-medium text-nowrap ${c.align === 'right' ? 'text-right' : 'text-left'} ${c.sticky ? 'sticky left-0 bg-muted/50 z-10' : ''}`}>{c.label}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((r: any, i: number) => (
            <tr key={r.id || i} className="border-b last:border-0 hover:bg-muted/30 cursor-pointer" onClick={() => onRowClick?.(r)}>
              {columns.map((c: any) => {
                const v = c.render ? c.render(r) : r[c.key]
                return <td key={c.key} className={`px-3 py-2 ${c.align === 'right' ? 'text-right' : ''} ${c.mono ? 'font-mono text-xs' : ''} ${c.sticky ? 'sticky left-0 bg-background z-10' : ''}`}>{v ?? '—'}</td>
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

export function ConfirmModal({ open, onClose, onConfirm, title, message }: any) {
  return (
    <Modal open={open} onClose={onClose} title={title} size="sm"
      footer={<>
        <Button variant="outline" onClick={onClose}>Cancel</Button>
        <Button variant="destructive" onClick={() => { onConfirm(); onClose() }}>Confirm</Button>
      </>}
    >
      <p className="text-sm text-muted-foreground">{message}</p>
    </Modal>
  )
}

// =================================================================
// Branches — hierarchical Branch File (tree with arbitrary depth,
// Control / Detail node types, guarded delete, per-node Add Child)
// =================================================================
export function BranchesModule() {
  const { has } = useApp()
  const [search, setSearch] = useState('')
  const { data, reload } = useFetch<any>('/api/branches')
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<any>({})
  const [editing, setEditing] = useState<any>(null)
  const [deleteTarget, setDeleteTarget] = useState<any>(null)
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [expanded, setExpanded] = useState<Set<string>>(new Set())

  const flat: any[] = data?.branches || []
  const tree: any[] = data?.tree || []
  const selected = flat.find(b => b.id === selectedId) || null

  // expand everything by default
  useEffect(() => {
    setExpanded(new Set(flat.map(b => b.id)))
  }, [data])

  const toggle = (id: string) => {
    setExpanded(prev => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id); else next.add(id)
      return next
    })
  }

  // descendants of a branch (for parent-select filtering on edit)
  const descendantIds = (rootId: string): string[] => {
    const byParent = new Map<string, string[]>()
    for (const b of flat) {
      if (!b.parentId) continue
      if (!byParent.has(b.parentId)) byParent.set(b.parentId, [])
      byParent.get(b.parentId)!.push(b.id)
    }
    const out: string[] = []
    const walk = (id: string) => {
      for (const child of byParent.get(id) || []) { out.push(child); walk(child) }
    }
    walk(rootId)
    return out
  }

  const openAdd = (parentId?: string) => {
    setEditing(null)
    setForm({ parentId: parentId || '', nodeType: 'Detail', isActive: true })
    setOpen(true)
  }
  const openEdit = (b: any) => {
    setEditing(b)
    setForm({ ...b, parentId: b.parentId || '' })
    setOpen(true)
  }

  const save = async () => {
    if (!form.name || !String(form.name).trim()) { toast.error('Branch name is required'); return }
    const isControl = form.nodeType === 'Control'
    const payload: any = {
      name: form.name,
      parentId: form.parentId || null,
      nodeType: isControl ? 'Control' : 'Detail',
      // Control-level records cannot hold branch detail data
      address: isControl ? null : form.address,
      city: isControl ? null : form.city,
      phone: isControl ? null : form.phone,
      email: isControl ? null : form.email,
      strn: isControl ? null : form.strn,
      ntn: isControl ? null : form.ntn,
      trn: isControl ? null : form.trn,
      fbr: isControl ? null : form.fbr,
    }
    try {
      if (editing) {
        await apiPatch(`/api/branches/${editing.id}`, { ...payload, isActive: form.isActive !== false })
        toast.success('Branch updated')
      } else {
        await apiPost('/api/branches', payload)
        toast.success('Branch created')
      }
      setOpen(false); reload()
    } catch (e: any) { toast.error(e.message) }
  }

  // search: fall back to a flat filtered list; otherwise render the tree
  const q = search.trim().toLowerCase()
  const matchesFlat = flat.filter(b =>
    !q || b.name.toLowerCase().includes(q) || b.code.toLowerCase().includes(q) || (b.city || '').toLowerCase().includes(q))

  const renderNode = (node: any, depth: number): ReactNode => {
    const children: any[] = node.children || []
    const hasChildren = children.length > 0
    const isOpen = expanded.has(node.id)
    return (
      <Fragment key={node.id}>
        <tr
          className={`border-b last:border-0 hover:bg-muted/30 cursor-pointer ${selectedId === node.id ? 'bg-primary/5' : ''}`}
          onClick={() => setSelectedId(prev => prev === node.id ? null : node.id)}
        >
          <td className="px-3 py-2">
            <div className="flex items-center gap-1" style={{ paddingLeft: depth * 20 }}>
              {hasChildren ? (
                <button onClick={() => toggle(node.id)} className="p-0.5 rounded hover:bg-muted" aria-label={isOpen ? 'Collapse' : 'Expand'}>
                  {isOpen ? <ChevronDown className="h-4 w-4" /> : <ChevronRight className="h-4 w-4" />}
                </button>
              ) : (
                <span className="w-5 shrink-0" />
              )}
              <span className="font-medium">{node.name}</span>
            </div>
          </td>
          <td className="px-3 py-2 font-mono text-xs">{node.code}</td>
          <td className="px-3 py-2">
            <Badge variant={node.nodeType === 'Control' ? 'default' : 'secondary'}>{node.nodeType}</Badge>
          </td>
          <td className="px-3 py-2">{node.city || '—'}</td>
          <td className="px-3 py-2">{node.phone || '—'}</td>
          <td className="px-3 py-2">{node.email || '—'}</td>
          <td className="px-3 py-2"><StatusBadge status={node.isActive ? 'Active' : 'Inactive'} /></td>
          <td className="px-3 py-2">
            <div className="flex gap-1">
              {has('branches.add') && (
                <Button size="sm" variant="ghost" title="Add sub-branch" onClick={() => openAdd(node.id)}><Plus className="h-3.5 w-3.5" /></Button>
              )}
              {has('branches.edit') && (
                <Button size="sm" variant="ghost" title="Edit" onClick={() => openEdit(node)}><Edit className="h-3.5 w-3.5" /></Button>
              )}
              {has('branches.delete') && (
                <Button size="sm" variant="ghost" title="Delete" onClick={() => setDeleteTarget(node)}><Trash2 className="h-3.5 w-3.5" /></Button>
              )}
            </div>
          </td>
        </tr>
        {hasChildren && isOpen && children.map(c => renderNode(c, depth + 1))}
      </Fragment>
    )
  }

  const parentOptions = flat.filter(b => !editing || (b.id !== editing.id && !descendantIds(editing.id).includes(b.id)))
  const isControlForm = form.nodeType === 'Control'

  const panelActions: PanelAction[] = [
    { label: 'Add', icon: Plus, onClick: () => openAdd(), disabled: !has('branches.add') },
    { label: 'Add Sub-branch', icon: Plus, onClick: () => openAdd(selected?.id), disabled: !selected || !has('branches.add'), title: 'Add a branch under the selected node' },
    { label: 'Edit', icon: Edit, onClick: () => selected && openEdit(selected), disabled: !selected || !has('branches.edit') },
    { label: 'Delete', icon: Trash2, variant: 'destructive', onClick: () => setDeleteTarget(selected), disabled: !selected || !has('branches.delete') },
  ]

  return (
    <div>
      <PageHeader title="Branches" />
      <ScreenShell actions={panelActions}>
        <Toolbar>
          <SearchInput value={search} onChange={setSearch} placeholder="Search branches…" />
          <Button variant="ghost" size="sm" onClick={reload}>Refresh</Button>
        </Toolbar>
      <div className="overflow-x-auto border rounded">
        <table className="w-full text-sm">
          <thead className="bg-muted/50 border-b">
            <tr>
              <th className="text-left px-3 py-2 font-medium">Name</th>
              <th className="text-left px-3 py-2 font-medium">Code</th>
              <th className="text-left px-3 py-2 font-medium">Type</th>
              <th className="text-left px-3 py-2 font-medium">City</th>
              <th className="text-left px-3 py-2 font-medium">Phone</th>
              <th className="text-left px-3 py-2 font-medium">Email</th>
              <th className="text-left px-3 py-2 font-medium">Status</th>
              <th className="text-left px-3 py-2 font-medium">Actions</th>
            </tr>
          </thead>
          <tbody>
            {q ? (
              matchesFlat.length ? matchesFlat.map(b => (
                <tr key={b.id}
                  className={`border-b last:border-0 hover:bg-muted/30 cursor-pointer ${selectedId === b.id ? 'bg-primary/5' : ''}`}
                  onClick={() => setSelectedId(prev => prev === b.id ? null : b.id)}
                >
                  <td className="px-3 py-2 font-medium">{b.name}</td>
                  <td className="px-3 py-2 font-mono text-xs">{b.code}</td>
                  <td className="px-3 py-2"><Badge variant={b.nodeType === 'Control' ? 'default' : 'secondary'}>{b.nodeType}</Badge></td>
                  <td className="px-3 py-2">{b.city || '—'}</td>
                  <td className="px-3 py-2">{b.phone || '—'}</td>
                  <td className="px-3 py-2">{b.email || '—'}</td>
                  <td className="px-3 py-2"><StatusBadge status={b.isActive ? 'Active' : 'Inactive'} /></td>
                  <td className="px-3 py-2">
                    <div className="flex gap-1">
                      {has('branches.edit') && <Button size="sm" variant="ghost" onClick={() => openEdit(b)}><Edit className="h-3.5 w-3.5" /></Button>}
                      {has('branches.delete') && <Button size="sm" variant="ghost" onClick={() => setDeleteTarget(b)}><Trash2 className="h-3.5 w-3.5" /></Button>}
                    </div>
                  </td>
                </tr>
              )) : (
                <tr><td colSpan={8} className="text-center py-8 text-muted-foreground text-sm">No branches match your search</td></tr>
              )
            ) : (
              tree.length ? tree.map(n => renderNode(n, 0)) : (
                <tr><td colSpan={8} className="text-center py-8 text-muted-foreground text-sm">No branches yet</td></tr>
              )
            )}
          </tbody>
        </table>
      </div>
      </ScreenShell>

      <Modal open={open} onClose={() => setOpen(false)} size="lg" title={editing ? `Edit Branch — ${editing.code}` : 'New Branch'}
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={save}><Save className="h-4 w-4 mr-1" />Save</Button>
        </>}>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <FormRow label="Code (Branch ID = Branch Code)">
            <Input value={editing ? editing.code : 'Auto (01, 01001, 01002, …)'} disabled className="bg-muted/40" />
          </FormRow>
          <FormRow label="Name" required><Input value={form.name || ''} onChange={e => setForm({ ...form, name: e.target.value })} /></FormRow>
          <FormRow label="Parent Branch">
            <Select value={form.parentId || '__root__'} onValueChange={v => setForm({ ...form, parentId: v === '__root__' ? '' : v })}>
              <SelectTrigger><SelectValue placeholder="— Root —" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="__root__">— Root (top level) —</SelectItem>
                {parentOptions.map((b: any) => (
                  <SelectItem key={b.id} value={b.id}>{b.code} — {b.name}</SelectItem>
                ))}
              </SelectContent>
            </Select>
          </FormRow>
          <FormRow label="Node Type">
            <Select value={form.nodeType || 'Detail'} onValueChange={v => setForm({ ...form, nodeType: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="Control">Control</SelectItem>
                <SelectItem value="Detail">Detail</SelectItem>
              </SelectContent>
            </Select>
          </FormRow>
          {isControlForm && (
            <div className="sm:col-span-2 text-xs text-amber-600 bg-amber-50 dark:bg-amber-950/30 border border-amber-200 dark:border-amber-900 rounded p-2">
              Control-level records are hierarchy containers only — they cannot hold branch detail data (address, tax numbers, logo). Only detail-level branch records can.
            </div>
          )}
          <FormRow label="City"><Input disabled={isControlForm} value={form.city || ''} onChange={e => setForm({ ...form, city: e.target.value })} /></FormRow>
          <FormRow label="Phone"><Input disabled={isControlForm} value={form.phone || ''} onChange={e => setForm({ ...form, phone: e.target.value })} /></FormRow>
          <FormRow label="Email"><Input disabled={isControlForm} value={form.email || ''} onChange={e => setForm({ ...form, email: e.target.value })} /></FormRow>
          <FormRow label="STRN"><Input disabled={isControlForm} value={form.strn || ''} onChange={e => setForm({ ...form, strn: e.target.value })} /></FormRow>
          <FormRow label="NTN"><Input disabled={isControlForm} value={form.ntn || ''} onChange={e => setForm({ ...form, ntn: e.target.value })} /></FormRow>
          <FormRow label="TRN"><Input disabled={isControlForm} value={form.trn || ''} onChange={e => setForm({ ...form, trn: e.target.value })} /></FormRow>
          <FormRow label="FBR Info"><Input disabled={isControlForm} value={form.fbr || ''} onChange={e => setForm({ ...form, fbr: e.target.value })} /></FormRow>
          {editing && (
            <FormRow label="Active"><Switch checked={form.isActive !== false} onCheckedChange={v => setForm({ ...form, isActive: v })} /></FormRow>
          )}
          <div className="sm:col-span-2"><FormRow label="Address"><Input disabled={isControlForm} value={form.address || ''} onChange={e => setForm({ ...form, address: e.target.value })} /></FormRow></div>
        </div>
        <div className="text-xs text-muted-foreground mt-3">
          {editing
            ? 'Branch code is immutable. A branch cannot be moved under itself or one of its sub-branches.'
            : 'Codes are auto-generated hierarchically (parent code + sequence): Company/Head Office = 01, its branches = 01001, 01002, … Only detail-level branches hold address, logo, NTN/TRN/FBR details.'}
        </div>
      </Modal>

      <ConfirmModal
        open={!!deleteTarget}
        onClose={() => setDeleteTarget(null)}
        title="Delete branch"
        message={`Delete branch ${deleteTarget?.code} — ${deleteTarget?.name}? Deletion is blocked if sub-branches, users, members or staff are attached.`}
        onConfirm={async () => {
          try {
            const json = await apiDelete(`/api/branches/${deleteTarget.id}`)
            toast.success(json.message || 'Branch deleted')
            reload()
          } catch (e: any) { toast.error(e.message) }
        }}
      />
    </div>
  )
}
