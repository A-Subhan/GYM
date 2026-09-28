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
import { Plus, Search, Edit, Trash2, Eye, X, Save, ChevronDown, ChevronRight, Download, Printer, Send } from 'lucide-react'
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
  const [expanded, setExpanded] = useState<Set<string>>(new Set())

  const flat: any[] = data?.branches || []
  const tree: any[] = data?.tree || []

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
    const payload: any = {
      name: form.name,
      parentId: form.parentId || null,
      nodeType: form.nodeType === 'Control' ? 'Control' : 'Detail',
      address: form.address, city: form.city, phone: form.phone,
      email: form.email, strn: form.strn, ntn: form.ntn,
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
        <tr className="border-b last:border-0 hover:bg-muted/30">
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

  return (
    <div>
      <PageHeader title="Branches"
        action={has('branches.add') ? () => openAdd() : undefined}
        actionLabel="New Branch" />
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
                <tr key={b.id} className="border-b last:border-0 hover:bg-muted/30">
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

      <Modal open={open} onClose={() => setOpen(false)} size="lg" title={editing ? `Edit Branch — ${editing.code}` : 'New Branch'}
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={save}><Save className="h-4 w-4 mr-1" />Save</Button>
        </>}>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <FormRow label="Code">
            <Input value={editing ? editing.code : 'Auto (BR-001, BR-002, …)'} disabled className="bg-muted/40" />
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
          <FormRow label="City"><Input value={form.city || ''} onChange={e => setForm({ ...form, city: e.target.value })} /></FormRow>
          <FormRow label="Phone"><Input value={form.phone || ''} onChange={e => setForm({ ...form, phone: e.target.value })} /></FormRow>
          <FormRow label="Email"><Input value={form.email || ''} onChange={e => setForm({ ...form, email: e.target.value })} /></FormRow>
          <FormRow label="STRN"><Input value={form.strn || ''} onChange={e => setForm({ ...form, strn: e.target.value })} /></FormRow>
          <FormRow label="NTN"><Input value={form.ntn || ''} onChange={e => setForm({ ...form, ntn: e.target.value })} /></FormRow>
          {editing && (
            <FormRow label="Active"><Switch checked={form.isActive !== false} onCheckedChange={v => setForm({ ...form, isActive: v })} /></FormRow>
          )}
          <div className="sm:col-span-2"><FormRow label="Address"><Input value={form.address || ''} onChange={e => setForm({ ...form, address: e.target.value })} /></FormRow></div>
        </div>
        <div className="text-xs text-muted-foreground mt-3">
          {editing
            ? 'Branch code is immutable. A branch cannot be moved under itself or one of its sub-branches.'
            : 'Branch code is generated automatically (BR-001, BR-002, …). Sub-branches of any depth are allowed.'}
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
