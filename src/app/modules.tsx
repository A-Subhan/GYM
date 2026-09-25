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
              <th key={c.key} className={`px-3 py-2 font-medium text-nowrap ${c.align === 'right' ? 'text-right' : 'text-left'}`}>{c.label}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((r: any, i: number) => (
            <tr key={r.id || i} className="border-b last:border-0 hover:bg-muted/30 cursor-pointer" onClick={() => onRowClick?.(r)}>
              {columns.map((c: any) => {
                const v = c.render ? c.render(r) : r[c.key]
                return <td key={c.key} className={`px-3 py-2 ${c.align === 'right' ? 'text-right' : ''} ${c.mono ? 'font-mono text-xs' : ''}`}>{v ?? '—'}</td>
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
// Branches (with hierarchy: Company → Control → Detail)
// =================================================================
export function BranchesModule() {
  const { has } = useApp()
  const [search, setSearch] = useState('')
  const { data, reload } = useFetch<any>('/api/branches')
  const [open, setOpen] = useState(false)
  const [editOpen, setEditOpen] = useState(false)
  const [editing, setEditing] = useState<any>(null)
  const [form, setForm] = useState<any>({})
  const [confirmDel, setConfirmDel] = useState<any>(null)

  const branches = (data?.branches || []).filter((b: any) =>
    !search || b.name.toLowerCase().includes(search.toLowerCase()) || b.code.toLowerCase().includes(search.toLowerCase()))

  // Build hierarchy
  const byId = new Map(branches.map((b: any) => [b.id, b]))
  const roots = branches.filter((b: any) => !b.parentId)

  const renderBranch = (b: any, depth = 0): ReactNode => {
    const children = branches.filter((c: any) => c.parentId === b.id)
    return (
      <div key={b.id}>
        <div className="flex items-center gap-2 px-2 py-1.5 hover:bg-muted/40" style={{ paddingLeft: `${depth * 20 + 8}px` }}>
          <span className="font-mono text-xs text-muted-foreground w-20">{b.code}</span>
          <span className="flex-1 text-sm">{b.name}</span>
          <Badge variant="outline" className="text-xs">{b.level || 'Detail'}</Badge>
          {b.city && <span className="text-xs text-muted-foreground">{b.city}</span>}
          <Badge variant={b.isActive ? 'default' : 'destructive'} className="text-xs">{b.isActive ? 'Active' : 'Inactive'}</Badge>
          {has('branches.edit') && (
            <button onClick={() => { setEditing(b); setForm(b); setEditOpen(true) }} className="text-xs text-primary hover:underline">Edit</button>
          )}
          {has('branches.delete') && (
            <button onClick={() => setConfirmDel(b)} className="text-xs text-destructive hover:underline">Delete</button>
          )}
        </div>
        {children.map((c: any) => renderBranch(c, depth + 1))}
      </div>
    )
  }

  return (
    <div>
      <PageHeader title="Branches" action={has('branches.add') ? () => { setForm({ level: 'Detail' }); setOpen(true) } : undefined} actionLabel="New Branch" />
      <Toolbar>
        <SearchInput value={search} onChange={setSearch} placeholder="Search branches…" />
        <Button variant="ghost" size="sm" onClick={reload}>Refresh</Button>
      </Toolbar>
      <Card>
        <CardContent className="p-0">
          {branches.length === 0 ? <EmptyState message="No branches" /> : roots.map((b: any) => renderBranch(b, 0))}
        </CardContent>
      </Card>

      {/* Add Modal */}
      <Modal open={open} onClose={() => setOpen(false)} title="New Branch"
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={async () => {
            try { await apiPost('/api/branches', form); toast.success('Branch created'); setOpen(false); reload() }
            catch (e: any) { toast.error(e.message) }
          }}><Save className="h-4 w-4 mr-1" />Save</Button>
        </>}>
        <BranchForm form={form} setForm={setForm} branches={branches} />
        <div className="text-xs text-muted-foreground mt-3">Branch code is generated automatically (BR-001, BR-002, …). Hierarchy: Company → Control (Head Office) → Detail (Branch).</div>
      </Modal>

      {/* Edit Modal */}
      <Modal open={editOpen} onClose={() => setEditOpen(false)} title="Edit Branch"
        footer={<>
          <Button variant="outline" onClick={() => setEditOpen(false)}>Cancel</Button>
          <Button onClick={async () => {
            try { await apiPatch('/api/branches', { ...form, id: editing.id }); toast.success('Branch updated'); setEditOpen(false); reload() }
            catch (e: any) { toast.error(e.message) }
          }}><Save className="h-4 w-4 mr-1" />Save</Button>
        </>}>
        <BranchForm form={form} setForm={setForm} branches={branches} excludeId={editing?.id} />
      </Modal>

      {/* Delete confirmation */}
      <ConfirmModal open={!!confirmDel} onClose={() => setConfirmDel(null)} title="Delete Branch"
        message={`Delete "${confirmDel?.name}"? This will soft-delete the branch.`}
        onConfirm={async () => {
          try { await apiDelete(`/api/branches?id=${confirmDel.id}`); toast.success('Branch deleted'); reload() }
          catch (e: any) { toast.error(e.message) }
        }} />
    </div>
  )
}

function BranchForm({ form, setForm, branches, excludeId }: any) {
  return (
    <div className="grid grid-cols-2 gap-3">
      <FormRow label="Name" required><Input value={form.name || ''} onChange={e => setForm({ ...form, name: e.target.value })} /></FormRow>
      <FormRow label="Level" required>
        <Select value={form.level || 'Detail'} onValueChange={v => setForm({ ...form, level: v })}>
          <SelectTrigger><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="Company">Company (top-level)</SelectItem>
            <SelectItem value="Control">Control (Head Office)</SelectItem>
            <SelectItem value="Detail">Detail (Branch)</SelectItem>
          </SelectContent>
        </Select>
      </FormRow>
      <FormRow label="Parent Branch">
        <Select value={form.parentId || ''} onValueChange={v => setForm({ ...form, parentId: v || null })}>
          <SelectTrigger><SelectValue placeholder="Root (no parent)" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="">Root (no parent)</SelectItem>
            {branches.filter((b: any) => b.id !== excludeId && b.level !== 'Detail').map((b: any) => (
              <SelectItem key={b.id} value={b.id}>{b.code} — {b.name} ({b.level})</SelectItem>
            ))}
          </SelectContent>
        </Select>
      </FormRow>
      <FormRow label="City"><Input value={form.city || ''} onChange={e => setForm({ ...form, city: e.target.value })} /></FormRow>
      <FormRow label="Phone"><Input value={form.phone || ''} onChange={e => setForm({ ...form, phone: e.target.value })} /></FormRow>
      <FormRow label="Email"><Input value={form.email || ''} onChange={e => setForm({ ...form, email: e.target.value })} /></FormRow>
      <FormRow label="STRN"><Input value={form.strn || ''} onChange={e => setForm({ ...form, strn: e.target.value })} /></FormRow>
      <FormRow label="NTN"><Input value={form.ntn || ''} onChange={e => setForm({ ...form, ntn: e.target.value })} /></FormRow>
      <FormRow label="FBR"><Input value={form.fbr || ''} onChange={e => setForm({ ...form, fbr: e.target.value })} /></FormRow>
      <FormRow label="Logo URL"><Input value={form.logo || ''} onChange={e => setForm({ ...form, logo: e.target.value })} /></FormRow>
      <div className="col-span-2"><FormRow label="Address"><Input value={form.address || ''} onChange={e => setForm({ ...form, address: e.target.value })} /></FormRow></div>
    </div>
  )
}
