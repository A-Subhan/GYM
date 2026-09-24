'use client'

import { useEffect, useState, useCallback, type ReactNode } from 'react'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Card, CardContent } from '@/components/ui/card'
import {
  Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter,
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
import { Plus, Search, Edit, Trash2, Eye, X, Save, ChevronDown, ChevronRight, Download, Printer, Banknote, AlertCircle, CheckCircle2 } from 'lucide-react'
import {
  useApp, useFetch, apiPost, apiPatch, apiDelete,
  fmtMoney, fmtDateStr, fmtDateTime, PageHeader, SearchInput, EmptyState,
  StatusBadge, Modal, FormRow, Toolbar, DataTable, ConfirmModal,
} from './modules'

// =================================================================
// CHART OF ACCOUNTS
// =================================================================
export function CoaModule() {
  const { session, has } = useApp()
  const [search, setSearch] = useState('')
  const [type, setType] = useState('all')
  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<any>({})
  const { data, reload } = useFetch<any>(`/api/accounts?accountType=${type !== 'all' ? type : ''}`)

  const accounts = data?.accounts || []
  const byId = new Map(accounts.map((a: any) => [a.id, a]))
  const roots = accounts.filter(a => !a.parentId)
  const matches = (a: any) => !search || a.name.toLowerCase().includes(search.toLowerCase()) || a.code.includes(search)
  const visible = (a: any, ancestors: any[] = []) => {
    if (matches(a)) return true
    return ancestors.some(matches)
  }

  const toggle = (id: string) => {
    setExpanded(prev => {
      const n = new Set(prev)
      if (n.has(id)) n.delete(id); else n.add(id)
      return n
    })
  }
  const expandAll = () => setExpanded(new Set(accounts.map((a: any) => a.id)))
  const collapseAll = () => setExpanded(new Set())

  const renderNode = (a: any, depth = 0): ReactNode => {
    const children = accounts.filter((c: any) => c.parentId === a.id)
    const isExpanded = expanded.has(a.id)
    return (
      <div key={a.id}>
        <div
          className={`flex items-center gap-2 px-2 py-1.5 hover:bg-muted/40 cursor-pointer ${matches(a) ? '' : 'opacity-60'}`}
          style={{ paddingLeft: `${depth * 20 + 8}px` }}
          onClick={() => children.length ? toggle(a.id) : null}
        >
          {children.length ? (
            isExpanded ? <ChevronDown className="h-3 w-3 shrink-0" /> : <ChevronRight className="h-3 w-3 shrink-0" />
          ) : <div className="w-3" />}
          <span className="font-mono text-xs text-muted-foreground w-20">{a.code}</span>
          <span className="flex-1 text-sm">{a.name}</span>
          <Badge variant="outline" className="text-xs">{a.accountType}</Badge>
          {a.bookType && <Badge variant="secondary" className="text-xs">{a.bookType}</Badge>}
          {a.isControl && <Badge className="text-xs">Control</Badge>}
          {a.accountTag && <Badge variant="secondary" className="text-xs">{a.accountTag}</Badge>}
          {has('finance.coa') && (
            <button onClick={(e) => { e.stopPropagation(); setForm({ parentId: a.id, accountType: a.accountType }); setOpen(true) }} className="text-xs text-primary hover:underline">
              Add child
            </button>
          )}
        </div>
        {isExpanded && children.map((c: any) => renderNode(c, depth + 1))}
      </div>
    )
  }

  return (
    <div>
      <PageHeader title="Chart of Accounts"
        action={has('finance.coa') ? () => { setForm({}); setOpen(true) } : undefined}
        actionLabel="Add Account" />
      <Toolbar>
        <SearchInput value={search} onChange={setSearch} placeholder="Search by name or code…" />
        <Select value={type} onValueChange={setType}>
          <SelectTrigger className="w-40"><SelectValue placeholder="Type" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All types</SelectItem>
            <SelectItem value="Asset">Asset</SelectItem>
            <SelectItem value="Liability">Liability</SelectItem>
            <SelectItem value="Equity">Capital / Equity</SelectItem>
            <SelectItem value="Revenue">Revenue</SelectItem>
            <SelectItem value="Expense">Expense</SelectItem>
          </SelectContent>
        </Select>
        <Button variant="outline" size="sm" onClick={expandAll}>Expand All</Button>
        <Button variant="outline" size="sm" onClick={collapseAll}>Collapse All</Button>
        <Button variant="ghost" size="sm" onClick={reload}>Refresh</Button>
      </Toolbar>
      <Card>
        <CardContent className="p-0">
          {accounts.length === 0 ? <EmptyState message="No accounts" /> : roots.map((a: any) => renderNode(a, 0))}
        </CardContent>
      </Card>

      <AccountFormModal open={open} onClose={() => setOpen(false)} form={form} setForm={setForm}
        onSaved={() => { setOpen(false); reload() }} accounts={accounts} />
    </div>
  )
}

function AccountFormModal({ open, onClose, form, setForm, onSaved, accounts }: any) {
  const parent = form.parentId ? accounts.find((a: any) => a.id === form.parentId) : null
  return (
    <Modal open={open} onClose={onClose} title="Add Account"
      footer={<>
        <Button variant="outline" onClick={onClose}>Cancel</Button>
        <Button onClick={async () => {
          try { await apiPost('/api/accounts', form); toast.success('Account created'); onSaved() }
          catch (e: any) { toast.error(e.message) }
        }}><Save className="h-4 w-4 mr-1" />Save</Button>
      </>}>
      <div className="grid grid-cols-2 gap-3">
        <FormRow label="Account Name" required><Input value={form.name || ''} onChange={e => setForm({ ...form, name: e.target.value })} /></FormRow>
        <FormRow label="Parent Account">
          <Select value={form.parentId || ''} onValueChange={v => setForm({ ...form, parentId: v || null })}>
            <SelectTrigger><SelectValue placeholder="Root (no parent)" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="">Root (no parent)</SelectItem>
              {accounts.filter((a: any) => !a.isDetail).map((a: any) => (
                <SelectItem key={a.id} value={a.id}>{a.code} — {a.name}</SelectItem>
              ))}
            </SelectContent>
          </Select>
        </FormRow>
        <FormRow label="Account Type" required>
          <Select value={form.accountType || ''} onValueChange={v => setForm({ ...form, accountType: v })}>
            <SelectTrigger><SelectValue placeholder="Type" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="Asset">Asset</SelectItem>
              <SelectItem value="Liability">Liability</SelectItem>
              <SelectItem value="Equity">Capital / Equity</SelectItem>
              <SelectItem value="Revenue">Revenue</SelectItem>
              <SelectItem value="Expense">Expense</SelectItem>
            </SelectContent>
          </Select>
        </FormRow>
        <FormRow label="Book Type">
          <Select value={form.bookType || ''} onValueChange={v => setForm({ ...form, bookType: v || null })}>
            <SelectTrigger><SelectValue placeholder="General" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="">General</SelectItem>
              <SelectItem value="Cash">Cash</SelectItem>
              <SelectItem value="Bank">Bank</SelectItem>
            </SelectContent>
          </Select>
        </FormRow>
        <FormRow label="Account Tag">
          <Select value={form.accountTag || ''} onValueChange={v => setForm({ ...form, accountTag: v || null })}>
            <SelectTrigger><SelectValue placeholder="None" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="">None</SelectItem>
              <SelectItem value="Customer">Customer</SelectItem>
              <SelectItem value="Vendor">Vendor</SelectItem>
              <SelectItem value="Bank">Bank</SelectItem>
              <SelectItem value="Cash">Cash</SelectItem>
            </SelectContent>
          </Select>
        </FormRow>
        <FormRow label="Control / Detail">
          <Select value={form.isControl ? 'Control' : 'Detail'} onValueChange={v => setForm({ ...form, isControl: v === 'Control' })}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="Control">Control Account</SelectItem>
              <SelectItem value="Detail">Detail Account</SelectItem>
            </SelectContent>
          </Select>
        </FormRow>
        <FormRow label="Status">
          <Select value={form.isActive === false ? 'Inactive' : 'Active'} onValueChange={v => setForm({ ...form, isActive: v === 'Active' })}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="Active">Active</SelectItem>
              <SelectItem value="Inactive">Inactive</SelectItem>
            </SelectContent>
          </Select>
        </FormRow>
        <FormRow label="Code (auto-generated)"><Input value={form.code || 'auto'} disabled className="bg-muted/40" /></FormRow>
        <FormRow label="Contact Name"><Input value={form.contactName || ''} onChange={e => setForm({ ...form, contactName: e.target.value })} /></FormRow>
        <FormRow label="Phone"><Input value={form.phone || ''} onChange={e => setForm({ ...form, phone: e.target.value })} /></FormRow>
        <FormRow label="Email"><Input value={form.email || ''} onChange={e => setForm({ ...form, email: e.target.value })} /></FormRow>
        <FormRow label="CNIC"><Input value={form.cnic || ''} onChange={e => setForm({ ...form, cnic: e.target.value })} /></FormRow>
        <FormRow label="NTN"><Input value={form.ntn || ''} onChange={e => setForm({ ...form, ntn: e.target.value })} /></FormRow>
        <FormRow label="Bank Name"><Input value={form.bankName || ''} onChange={e => setForm({ ...form, bankName: e.target.value })} /></FormRow>
        <FormRow label="Bank A/C #"><Input value={form.bankAccountNo || ''} onChange={e => setForm({ ...form, bankAccountNo: e.target.value })} /></FormRow>
        <FormRow label="Opening Balance"><Input type="number" value={form.openingBalance || 0} onChange={e => setForm({ ...form, openingBalance: Number(e.target.value) })} /></FormRow>
        <FormRow label="Opening Type">
          <Select value={form.openingBalanceType || 'Dr'} onValueChange={v => setForm({ ...form, openingBalanceType: v })}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent><SelectItem value="Dr">Debit</SelectItem><SelectItem value="Cr">Credit</SelectItem></SelectContent>
          </Select>
        </FormRow>
        <div className="col-span-2"><FormRow label="Description"><Textarea rows={2} value={form.description || ''} onChange={e => setForm({ ...form, description: e.target.value })} /></FormRow></div>
      </div>
      {parent && <div className="mt-3 text-xs text-muted-foreground">Parent: <code>{parent.code} — {parent.name}</code>. Code will be auto-generated under this parent.</div>}
    </Modal>
  )
}

// =================================================================
// VOUCHERS
// =================================================================
export function VouchersModule({ presetType, presetTitle }: { presetType?: string, presetTitle?: string } = {}) {
  const { session, has, selectedBranchIds } = useApp()
  const [type, setType] = useState(presetType || 'all')
  const [status, setStatus] = useState('all')
  const [search, setSearch] = useState('')
  const [open, setOpen] = useState(false)
  const [viewOpen, setViewOpen] = useState(false)
  const [viewing, setViewing] = useState<any>(null)
  const [reverseTarget, setReverseTarget] = useState<any>(null)
  const branchesParam = selectedBranchIds.length ? `&branches=${selectedBranchIds.join(',')}` : ''
  const { data, reload } = useFetch<any>(`/api/vouchers?voucherType=${type !== 'all' ? type : ''}&status=${status !== 'all' ? status : ''}${branchesParam}`)

  const vouchers = (data?.vouchers || []).filter((v: any) =>
    !search || v.voucherNo.toLowerCase().includes(search.toLowerCase()) || v.description?.toLowerCase().includes(search.toLowerCase()))

  return (
    <div>
      <PageHeader title={presetTitle || 'Vouchers'}
        action={has('vouchers.add') ? () => setOpen(true) : undefined}
        actionLabel="New Voucher" />
      <Toolbar>
        <SearchInput value={search} onChange={setSearch} placeholder="Search voucher no, description…" />
        {!presetType && (
          <Select value={type} onValueChange={setType}>
            <SelectTrigger className="w-40"><SelectValue placeholder="Type" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">All types</SelectItem>
              <SelectItem value="CRV">CRV — Cash Receipt</SelectItem>
              <SelectItem value="CPV">CPV — Cash Payment</SelectItem>
              <SelectItem value="BRV">BRV — Bank Receipt</SelectItem>
              <SelectItem value="BPV">BPV — Bank Payment</SelectItem>
              <SelectItem value="JV">JV — Journal</SelectItem>
            </SelectContent>
          </Select>
        )}
        <Select value={status} onValueChange={setStatus}>
          <SelectTrigger className="w-32"><SelectValue placeholder="Status" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All</SelectItem>
            <SelectItem value="Draft">Draft</SelectItem>
            <SelectItem value="Posted">Posted</SelectItem>
            <SelectItem value="Reversed">Reversed</SelectItem>
          </SelectContent>
        </Select>
        <Button variant="ghost" size="sm" onClick={reload}>Refresh</Button>
      </Toolbar>
      <DataTable
        columns={[
          { key: 'actions', label: 'Actions', sticky: true, render: (r: any) => (
            <div className="flex gap-0.5">
              <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); setViewing(r); setViewOpen(true) }} title="View"><Eye className="h-3.5 w-3.5" /></Button>
              <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); window.print() }} title="Print"><Printer className="h-3.5 w-3.5" /></Button>
              {r.status === 'Posted' && has('vouchers.reverse') && (
                <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); setReverseTarget(r) }} title="Reverse"><X className="h-3.5 w-3.5 text-amber-600" /></Button>
              )}
            </div>
          ) },
          { key: 'voucherNo', label: 'Voucher #', mono: true },
          { key: 'voucherType', label: 'Type' },
          { key: 'voucherDate', label: 'Date', render: (r: any) => fmtDateStr(r.voucherDate) },
          { key: 'branch', label: 'Branch', render: (r: any) => r.branch?.name || '—' },
          { key: 'description', label: 'Description' },
          { key: 'totalDebit', label: 'Debit', align: 'right', mono: true, render: (r: any) => fmtMoney(r.totalDebit) },
          { key: 'totalCredit', label: 'Credit', align: 'right', mono: true, render: (r: any) => fmtMoney(r.totalCredit) },
          { key: 'status', label: 'Status', render: (r: any) => <StatusBadge status={r.status} /> },
        ]}
        rows={vouchers}
        onRowClick={(r: any) => { setViewing(r); setViewOpen(true) }}
      />

      <VoucherFormModal open={open} onClose={() => setOpen(false)} defaultType={presetType || (type !== 'all' ? type : 'CRV')} onSaved={() => { setOpen(false); reload() }} />
      <VoucherViewModal open={viewOpen} voucher={viewing} onClose={() => setViewOpen(false)} />
      <ReverseModal open={!!reverseTarget} voucher={reverseTarget} onClose={() => setReverseTarget(null)} onDone={() => { setReverseTarget(null); reload() }} />
    </div>
  )
}

function VoucherFormModal({ open, onClose, defaultType, onSaved }: any) {
  const { session, branches } = useApp()
  const { data: accountsData } = useFetch<any>('/api/accounts')
  const { data: taxHeadsData } = useFetch<any>('/api/tax-heads')
  const accounts = accountsData?.accounts || []
  const taxHeads = taxHeadsData?.taxHeads || []
  const isJV = defaultType === 'JV'
  const isCashType = defaultType === 'CRV' || defaultType === 'CPV'
  const isBankType = defaultType === 'BRV' || defaultType === 'BPV'
  const bookAccounts = accounts.filter((a: any) =>
    a.isActive && (isCashType ? a.bookType === 'Cash' : isBankType ? a.bookType === 'Bank' : false)
  )
  const detailAccounts = accounts.filter((a: any) => a.isDetail && a.isActive)

  const emptyLine = () => ({
    accountId: '', lineDescription: '', amount: 0, debit: 0, credit: 0,
    taxAccountId: '', taxRate: 0, taxAmount: 0,
    chequeNo: '', chequeAmount: 0, chequeBankName: '', chequeStatus: '',
    status: 'Active',
  })

  const [form, setForm] = useState<any>({
    voucherDate: new Date().toISOString().slice(0, 10),
    reference: '', bookAccountId: '', branchId: session?.branchId || branches[0]?.id || '',
    description: '', lines: [emptyLine()],
  })

  useEffect(() => {
    if (open) {
      setForm({
        voucherDate: new Date().toISOString().slice(0, 10),
        reference: '', bookAccountId: '', branchId: session?.branchId || branches[0]?.id || '',
        description: '', lines: [emptyLine()],
      })
    }
  }, [open])

  // Tax calc: when amount or taxRate changes, auto-calc taxAmount = amount * taxRate / 100
  const onLineAmountChange = (i: number, amt: number) => {
    setForm((f: any) => ({
      ...f,
      lines: f.lines.map((l: any, idx: number) => {
        if (idx !== i) return l
        const taxRate = Number(l.taxRate) || 0
        const taxAmount = l.taxAccountId ? Math.round(amt * taxRate) / 100 : 0
        return { ...l, amount: amt, taxAmount }
      }),
    }))
  }
  const onLineTaxAccountChange = (i: number, taxAccountId: string) => {
    setForm((f: any) => ({
      ...f,
      lines: f.lines.map((l: any, idx: number) => {
        if (idx !== i) return l
        const th = taxHeads.find((t: any) => t.id === taxAccountId)
        const taxRate = th?.rate || 0
        const amt = Number(l.amount) || 0
        return { ...l, taxAccountId, taxRate, taxAmount: taxAccountId ? Math.round(amt * taxRate) / 100 : 0 }
      }),
    }))
  }
  const onLineTaxRateChange = (i: number, taxRate: number) => {
    setForm((f: any) => ({
      ...f,
      lines: f.lines.map((l: any, idx: number) => {
        if (idx !== i) return l
        const amt = Number(l.amount) || 0
        return { ...l, taxRate, taxAmount: l.taxAccountId ? Math.round(amt * taxRate) / 100 : 0 }
      }),
    }))
  }

  const setLine = (i: number, patch: any) => {
    setForm((f: any) => ({ ...f, lines: f.lines.map((l: any, idx: number) => idx === i ? { ...l, ...patch } : l) }))
  }
  const addLine = () => setForm((f: any) => ({ ...f, lines: [...f.lines, emptyLine()] }))
  const removeLine = (i: number) => setForm((f: any) => ({ ...f, lines: f.lines.filter((_: any, idx: number) => idx !== i) }))

  // Totals
  const totalDetailAmount = form.lines.reduce((s: number, l: any) => s + (Number(l.amount) || 0), 0)
  const totalTaxAmount = form.lines.reduce((s: number, l: any) => s + (Number(l.taxAmount) || 0), 0)
  const grandTotal = totalDetailAmount + totalTaxAmount
  const totalDebitJV = form.lines.reduce((s: number, l: any) => s + (Number(l.debit) || 0), 0)
  const totalCreditJV = form.lines.reduce((s: number, l: any) => s + (Number(l.credit) || 0), 0)
  const balancedJV = Math.abs(totalDebitJV - totalCreditJV) < 0.01
  const canSave = isJV ? balancedJV : (form.bookAccountId && form.lines.length > 0 && form.lines.every((l: any) => l.accountId) && totalDetailAmount > 0)

  const save = async () => {
    if (!form.voucherDate || !form.branchId) { toast.error('Date and branch are required'); return }
    if (!isJV && !form.bookAccountId) { toast.error('Book Account is required'); return }
    if (isJV && !balancedJV) { toast.error(`JV not balanced: Dr ${totalDebitJV} vs Cr ${totalCreditJV}`); return }
    try {
      const payload: any = {
        voucherType: defaultType,
        voucherDate: form.voucherDate,
        branchId: form.branchId,
        bookAccountId: isJV ? null : form.bookAccountId,
        description: form.description,
        reference: form.reference,
        status: 'Posted',
        lines: form.lines.map((l: any) => ({
          accountId: l.accountId,
          amount: Number(l.amount) || 0,
          debit: isJV ? (Number(l.debit) || 0) : 0,
          credit: isJV ? (Number(l.credit) || 0) : 0,
          lineDescription: l.lineDescription,
          taxAccountId: l.taxAccountId || null,
          taxRate: Number(l.taxRate) || 0,
          taxAmount: Number(l.taxAmount) || 0,
          chequeNo: l.chequeNo || null,
          chequeAmount: l.chequeAmount ? Number(l.chequeAmount) : null,
          chequeBankName: l.chequeBankName || null,
          chequeStatus: l.chequeStatus || null,
          status: l.status || 'Active',
        })),
      }
      await apiPost('/api/vouchers', payload)
      toast.success('Voucher posted')
      onSaved()
    } catch (e: any) { toast.error(e.message) }
  }

  const title = `New ${defaultType === 'CRV' ? 'Cash Receipt' : defaultType === 'CPV' ? 'Cash Payment' : defaultType === 'BRV' ? 'Bank Receipt' : defaultType === 'BPV' ? 'Bank Payment' : 'Journal'} Voucher`

  return (
    <Modal open={open} onClose={onClose} title={title} size="xl"
      footer={<>
        <Button variant="outline" onClick={onClose}>Cancel</Button>
        <Button onClick={save} disabled={!canSave}>
          <Save className="h-4 w-4 mr-1" />
          {isJV ? (balancedJV ? 'Post Voucher' : `Out of balance: ${Math.abs(totalDebitJV - totalCreditJV).toFixed(2)}`)
                : (canSave ? 'Post Voucher' : 'Fill all required fields')}
        </Button>
      </>}>
      {/* HEADER: Date | Reference | Book Account | Branch */}
      <div className="grid grid-cols-2 sm:grid-cols-12 gap-3 items-end">
        <div className="sm:col-span-3"><FormRow label="Date" required><Input type="date" value={form.voucherDate} onChange={e => setForm({ ...form, voucherDate: e.target.value })} /></FormRow></div>
        <div className="sm:col-span-3"><FormRow label="Reference #"><Input value={form.reference || ''} onChange={e => setForm({ ...form, reference: e.target.value })} /></FormRow></div>
        <div className="sm:col-span-3">
          {isJV ? (
            <FormRow label="Book Account"><Input disabled value="— Not required for JV —" className="bg-muted/40 text-xs" /></FormRow>
          ) : (
            <FormRow label="Book Account" required>
              <Select value={form.bookAccountId || '__none__'} onValueChange={v => setForm({ ...form, bookAccountId: v === '__none__' ? '' : v })}>
                <SelectTrigger><SelectValue placeholder="Select…" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="__none__">— Select —</SelectItem>
                  {bookAccounts.map((a: any) => <SelectItem key={a.id} value={a.id}>{a.code} — {a.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </FormRow>
          )}
        </div>
        <div className="sm:col-span-3">
          <FormRow label="Branch" required>
            <Select value={form.branchId || '__none__'} onValueChange={v => setForm({ ...form, branchId: v === '__none__' ? '' : v })}>
              <SelectTrigger><SelectValue placeholder="Select branch" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="__none__">— Select —</SelectItem>
                {branches.map((b: any) => <SelectItem key={b.id} value={b.id}>{b.name}</SelectItem>)}
              </SelectContent>
            </Select>
          </FormRow>
        </div>
        <div className="sm:col-span-12"><FormRow label="Description"><Input value={form.description || ''} onChange={e => setForm({ ...form, description: e.target.value })} /></FormRow></div>
      </div>

      <div className="mt-4 border rounded">
        <div className="px-3 py-2 bg-muted/40 border-b font-medium text-sm flex items-center justify-between">
          <span>Detail Lines {isJV ? '(manual Debit / Credit)' : `(${defaultType === 'CRV' || defaultType === 'BRV' ? 'Credit side' : 'Debit side'} — Book Account auto-${defaultType === 'CRV' || defaultType === 'BRV' ? 'Debited' : 'Credited'})`}</span>
          <span className="text-xs text-muted-foreground">
            {isJV ? `Dr: ${fmtMoney(totalDebitJV)} · Cr: ${fmtMoney(totalCreditJV)} · ${balancedJV ? 'Balanced' : 'Not balanced'}`
                  : `Base: ${fmtMoney(totalDetailAmount)} · Tax: ${fmtMoney(totalTaxAmount)} · Total: ${fmtMoney(grandTotal)}`}
          </span>
        </div>
        <div className="overflow-x-auto max-h-[420px] overflow-y-auto">
          <table className="w-full text-xs">
            <thead className="bg-muted/30 border-b sticky top-0">
              <tr>
                <th className="px-2 py-1.5 text-left">Account</th>
                <th className="px-2 py-1.5 text-left">Description</th>
                {isJV ? (
                  <><th className="px-2 py-1.5 text-right">Debit</th><th className="px-2 py-1.5 text-right">Credit</th></>
                ) : (
                  <th className="px-2 py-1.5 text-right">Amount</th>
                )}
                <th className="px-2 py-1.5 text-left">Tax Account</th>
                <th className="px-2 py-1.5 text-right">Tax %</th>
                <th className="px-2 py-1.5 text-right">Tax Amount</th>
                {isBankType && <><th className="px-2 py-1.5 text-left">Cheque #</th><th className="px-2 py-1.5 text-right">Cheque Amt</th><th className="px-2 py-1.5 text-left">Bank Name</th><th className="px-2 py-1.5 text-left">Cheque Status</th></>}
                <th className="px-2 py-1.5"></th>
              </tr>
            </thead>
            <tbody>
              {form.lines.map((l: any, i: number) => (
                <tr key={i} className="border-b last:border-0 align-top">
                  <td className="px-2 py-1.5 min-w-[180px]">
                    <Select value={l.accountId || '__none__'} onValueChange={v => setLine(i, { accountId: v === '__none__' ? '' : v })}>
                      <SelectTrigger className="h-7"><SelectValue placeholder="Account" /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="__none__">—</SelectItem>
                        {detailAccounts.map((a: any) => <SelectItem key={a.id} value={a.id}>{a.code} — {a.name}</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </td>
                  <td className="px-2 py-1.5 min-w-[140px]"><Input value={l.lineDescription || ''} onChange={e => setLine(i, { lineDescription: e.target.value })} className="h-7" /></td>
                  {isJV ? (
                    <>
                      <td className="px-2 py-1.5 w-24"><Input type="number" value={l.debit || 0} onChange={e => setLine(i, { debit: Number(e.target.value), credit: 0, amount: Number(e.target.value) })} className="h-7 text-right" /></td>
                      <td className="px-2 py-1.5 w-24"><Input type="number" value={l.credit || 0} onChange={e => setLine(i, { credit: Number(e.target.value), debit: 0, amount: Number(e.target.value) })} className="h-7 text-right" /></td>
                    </>
                  ) : (
                    <td className="px-2 py-1.5 w-28"><Input type="number" value={l.amount || 0} onChange={e => onLineAmountChange(i, Number(e.target.value))} className="h-7 text-right" /></td>
                  )}
                  <td className="px-2 py-1.5 min-w-[160px]">
                    <Select value={l.taxAccountId || '__none__'} onValueChange={v => onLineTaxAccountChange(i, v === '__none__' ? '' : v)}>
                      <SelectTrigger className="h-7"><SelectValue placeholder="None" /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="__none__">None</SelectItem>
                        {taxHeads.filter((t: any) => t.isActive).map((t: any) => <SelectItem key={t.id} value={t.id}>{t.code} — {t.shortName} ({t.rate}%)</SelectItem>)}
                      </SelectContent>
                    </Select>
                  </td>
                  <td className="px-2 py-1.5 w-20"><Input type="number" step="0.01" value={l.taxRate || 0} onChange={e => onLineTaxRateChange(i, Number(e.target.value))} className="h-7 text-right" /></td>
                  <td className="px-2 py-1.5 w-24"><Input type="number" value={l.taxAmount || 0} readOnly className="h-7 text-right bg-muted/30" /></td>
                  {isBankType && (
                    <>
                      <td className="px-2 py-1.5 min-w-[120px]"><Input value={l.chequeNo || ''} onChange={e => setLine(i, { chequeNo: e.target.value })} className="h-7" placeholder="Cheque #" /></td>
                      <td className="px-2 py-1.5 w-28"><Input type="number" value={l.amount || 0} readOnly className="h-7 text-right bg-muted/30" title="Linked to Amount" /></td>
                      <td className="px-2 py-1.5 min-w-[120px]"><Input value={l.chequeBankName || ''} onChange={e => setLine(i, { chequeBankName: e.target.value })} className="h-7" placeholder="Bank name" /></td>
                      <td className="px-2 py-1.5 min-w-[120px]">
                        <Select value={l.chequeStatus || '__none__'} onValueChange={v => setLine(i, { chequeStatus: v === '__none__' ? '' : v })}>
                          <SelectTrigger className="h-7"><SelectValue placeholder="—" /></SelectTrigger>
                          <SelectContent>
                            <SelectItem value="__none__">—</SelectItem>
                            <SelectItem value="Hold">Hold</SelectItem>
                            <SelectItem value="Clear">Clear</SelectItem>
                            <SelectItem value="Bounced">Bounced</SelectItem>
                            <SelectItem value="Deposited">Deposited</SelectItem>
                          </SelectContent>
                        </Select>
                      </td>
                    </>
                  )}
                  <td className="px-2 py-1.5"><Button size="sm" variant="ghost" onClick={() => removeLine(i)} disabled={form.lines.length === 1}><Trash2 className="h-3 w-3" /></Button></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="p-2 border-t"><Button size="sm" variant="outline" onClick={addLine}><Plus className="h-3 w-3 mr-1" />Add Line</Button></div>
      </div>
      <div className="mt-2 text-xs text-muted-foreground">
        {defaultType === 'CRV' && 'CRV: Book Account (cash) is auto-DEBITED. Detail lines are credited. Tax Amount is auto-calculated.'}
        {defaultType === 'CPV' && 'CPV: Book Account (cash) is auto-CREDITED. Detail lines are debited. Tax Amount is auto-calculated.'}
        {defaultType === 'BRV' && 'BRV: Book Account (bank) is auto-DEBITED. Detail lines are credited. Tax Amount is auto-calculated.'}
        {defaultType === 'BPV' && 'BPV: Book Account (bank) is auto-CREDITED. Detail lines are debited. Tax Amount is auto-calculated. Cheque Amount is linked to line Amount.'}
        {defaultType === 'JV' && 'JV: Manual Debit and Credit entry. Total Debit must equal Total Credit.'}
      </div>
    </Modal>
  )
}

function VoucherViewModal({ open, voucher, onClose }: any) {
  if (!voucher) return null
  return (
    <Modal open={open} onClose={onClose} title={`Voucher ${voucher.voucherNo}`} size="lg">
      <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 text-sm">
        <div><div className="text-xs text-muted-foreground">Type</div><div className="font-medium">{voucher.voucherType}</div></div>
        <div><div className="text-xs text-muted-foreground">Date</div><div className="font-medium">{fmtDateStr(voucher.voucherDate)}</div></div>
        <div><div className="text-xs text-muted-foreground">Status</div><div><StatusBadge status={voucher.status} /></div></div>
        <div><div className="text-xs text-muted-foreground">Branch</div><div className="font-medium">{voucher.branch?.name}</div></div>
        <div><div className="text-xs text-muted-foreground">Book Account</div><div className="font-medium">{voucher.bookAccount?.name || '—'}</div></div>
        <div><div className="text-xs text-muted-foreground">Reference</div><div className="font-medium">{voucher.reference || '—'}</div></div>
        <div className="col-span-3"><div className="text-xs text-muted-foreground">Description</div><div>{voucher.description || '—'}</div></div>
      </div>
      <div className="mt-4 border rounded overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-muted/40 border-b">
            <tr>
              <th className="px-3 py-2 text-left">Account</th>
              <th className="px-3 py-2 text-left">Description</th>
              <th className="px-3 py-2 text-right">Debit</th>
              <th className="px-3 py-2 text-right">Credit</th>
            </tr>
          </thead>
          <tbody>
            {voucher.lines?.map((l: any) => (
              <tr key={l.id} className="border-b last:border-0">
                <td className="px-3 py-2"><span className="font-mono text-xs">{l.account?.code}</span> · {l.account?.name}</td>
                <td className="px-3 py-2">{l.lineDescription || '—'}</td>
                <td className="px-3 py-2 text-right font-mono">{fmtMoney(l.debit)}</td>
                <td className="px-3 py-2 text-right font-mono">{fmtMoney(l.credit)}</td>
              </tr>
            ))}
          </tbody>
          <tfoot className="bg-muted/30 border-t font-medium">
            <tr>
              <td colSpan={2} className="px-3 py-2 text-right">Total</td>
              <td className="px-3 py-2 text-right font-mono">{fmtMoney(voucher.totalDebit)}</td>
              <td className="px-3 py-2 text-right font-mono">{fmtMoney(voucher.totalCredit)}</td>
            </tr>
          </tfoot>
        </table>
      </div>
      {voucher.cheques?.length > 0 && (
        <div className="mt-3">
          <div className="text-xs text-muted-foreground mb-1">Cheques</div>
          <div className="space-y-1">
            {voucher.cheques.map((c: any) => (
              <div key={c.id} className="flex items-center gap-2 text-sm">
                <span className="font-mono">{c.chequeNo}</span>
                <span className="text-muted-foreground">{fmtDateStr(c.chequeDate)}</span>
                <span className="font-mono">{fmtMoney(c.amount)}</span>
                <StatusBadge status={c.status} />
              </div>
            ))}
          </div>
        </div>
      )}
    </Modal>
  )
}

function ReverseModal({ open, voucher, onClose, onDone }: any) {
  const [reason, setReason] = useState('')
  if (!voucher) return null
  return (
    <Modal open={open} onClose={onClose} title={`Reverse ${voucher.voucherNo}`} size="sm"
      footer={<>
        <Button variant="outline" onClick={onClose}>Cancel</Button>
        <Button variant="destructive" onClick={async () => {
          try { await apiPatch(`/api/vouchers/${voucher.id}`, { action: 'reverse', reason }); toast.success('Voucher reversed'); onDone() }
          catch (e: any) { toast.error(e.message) }
        }}>Reverse</Button>
      </>}>
      <p className="text-sm mb-2">This will create a reversal voucher swapping debit and credit sides. The original voucher will be marked as reversed.</p>
      <FormRow label="Reason"><Textarea value={reason} onChange={e => setReason(e.target.value)} rows={3} /></FormRow>
    </Modal>
  )
}

// =================================================================
// TAX HEADS
// =================================================================
export function TaxHeadsModule() {
  const { has } = useApp()
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<any>({})
  const { data, reload } = useFetch<any>('/api/tax-heads')
  const taxHeads = data?.taxHeads || []
  return (
    <div>
      <PageHeader title="Tax Heads"
        action={has('tax.add') ? () => { setForm({}); setOpen(true) } : undefined}
        actionLabel="Add Tax Head" />
      <Toolbar><Button variant="ghost" size="sm" onClick={reload}>Refresh</Button></Toolbar>
      <DataTable
        columns={[
          { key: 'code', label: 'Code', mono: true },
          { key: 'shortName', label: 'Short Name' },
          { key: 'name', label: 'Name' },
          { key: 'taxType', label: 'Type' },
          { key: 'rate', label: 'Rate', align: 'right', render: (r: any) => `${r.rate}%` },
          { key: 'isActive', label: 'Status', render: (r: any) => <StatusBadge status={r.isActive ? 'Active' : 'Inactive'} /> },
        ]}
        rows={taxHeads}
      />
      <Modal open={open} onClose={() => setOpen(false)} title="Add Tax Head"
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={async () => {
            try { await apiPost('/api/tax-heads', form); toast.success('Tax head created'); setOpen(false); reload() }
            catch (e: any) { toast.error(e.message) }
          }}><Save className="h-4 w-4 mr-1" />Save</Button>
        </>}>
        <div className="grid grid-cols-2 gap-3">
          <FormRow label="Code (auto-generated 001, 002…)"><Input disabled value="auto" className="bg-muted/40" /></FormRow>
          <FormRow label="Short Name" required><Input value={form.shortName || ''} onChange={e => setForm({ ...form, shortName: e.target.value })} placeholder="ST-18" /></FormRow>
          <FormRow label="Tax Name" required><Input value={form.name || ''} onChange={e => setForm({ ...form, name: e.target.value })} placeholder="Sales Tax 18%" /></FormRow>
          <FormRow label="Tax Type">
            <Select value={form.taxType || 'Sales'} onValueChange={v => setForm({ ...form, taxType: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="Sales">Sales</SelectItem>
                <SelectItem value="Withholding">Withholding</SelectItem>
                <SelectItem value="Income">Income</SelectItem>
                <SelectItem value="Other">Other</SelectItem>
              </SelectContent>
            </Select>
          </FormRow>
          <FormRow label="Rate %"><Input type="number" value={form.rate || 0} onChange={e => setForm({ ...form, rate: Number(e.target.value) })} /></FormRow>
          <FormRow label="Active"><Switch checked={form.isActive !== false} onCheckedChange={v => setForm({ ...form, isActive: v })} /></FormRow>
        </div>
        <div className="mt-3 text-xs text-muted-foreground">Code is auto-generated as a 3-digit sequence per branch (001, 002, 003…).</div>
      </Modal>
    </div>
  )
}

// =================================================================
// CHEQUES
// =================================================================
export function ChequesModule() {
  const { has, selectedBranchIds } = useApp()
  const [status, setStatus] = useState('all')
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [bulkStatus, setBulkStatus] = useState('Clear')
  const branchesParam = selectedBranchIds.length ? `&branchId=${selectedBranchIds.join(',')}` : ''
  const { data, reload } = useFetch<any>(`/api/cheques?status=${status !== 'all' ? status : ''}${branchesParam}`)
  const cheques = data?.cheques || []

  const toggleAll = () => {
    if (selected.size === cheques.length) setSelected(new Set())
    else setSelected(new Set(cheques.map((c: any) => c.id)))
  }
  const toggle = (id: string) => {
    const n = new Set(selected)
    if (n.has(id)) n.delete(id); else n.add(id)
    setSelected(n)
  }
  const bulkUpdate = async () => {
    if (selected.size === 0) { toast.error('Select at least one cheque'); return }
    try {
      await apiPatch('/api/cheques', { ids: Array.from(selected), status: bulkStatus })
      toast.success(`${selected.size} cheque(s) updated to ${bulkStatus}`)
      setSelected(new Set())
      reload()
    } catch (e: any) { toast.error(e.message) }
  }

  return (
    <div>
      <PageHeader title="Update Cheque Status" />
      <Toolbar>
        <Select value={status} onValueChange={setStatus}>
          <SelectTrigger className="w-36"><SelectValue placeholder="Status" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All statuses</SelectItem>
            <SelectItem value="Hold">Hold</SelectItem>
            <SelectItem value="Clear">Clear</SelectItem>
            <SelectItem value="Bounced">Bounced</SelectItem>
            <SelectItem value="Deposited">Deposited</SelectItem>
          </SelectContent>
        </Select>
        <Button variant="ghost" size="sm" onClick={reload}>Refresh</Button>
        <div className="flex-1" />
        {has('cheques.status') && selected.size > 0 && (
          <div className="flex items-center gap-2">
            <Select value={bulkStatus} onValueChange={setBulkStatus}>
              <SelectTrigger className="w-32"><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="Hold">Hold</SelectItem>
                <SelectItem value="Clear">Clear</SelectItem>
                <SelectItem value="Bounced">Bounced</SelectItem>
                <SelectItem value="Deposited">Deposited</SelectItem>
              </SelectContent>
            </Select>
            <Button size="sm" onClick={bulkUpdate}>Update {selected.size} selected</Button>
          </div>
        )}
      </Toolbar>
      <DataTable
        columns={[
          { key: 'select', label: '', render: (r: any) => (
            <Checkbox checked={selected.has(r.id)} onCheckedChange={() => toggle(r.id)} onClick={(e: any) => e.stopPropagation()} />
          ) },
          { key: 'chequeNo', label: 'Cheque #', mono: true },
          { key: 'chequeDate', label: 'Date', render: (r: any) => fmtDateStr(r.chequeDate) },
          { key: 'bankName', label: 'Bank' },
          { key: 'amount', label: 'Amount', align: 'right', mono: true, render: (r: any) => fmtMoney(r.amount) },
          { key: 'voucher', label: 'Voucher', render: (r: any) => r.voucher?.voucherNo || '—' },
          { key: 'voucher', label: 'Branch', render: (r: any) => r.voucher?.branch?.name || '—' },
          { key: 'status', label: 'Status', render: (r: any) => <StatusBadge status={r.status} /> },
        ]}
        rows={cheques}
      />
    </div>
  )
}

// =================================================================
// MEMBERS
// =================================================================
export function MembersModule() {
  const { has, selectedBranchIds } = useApp()
  const [search, setSearch] = useState('')
  const [status, setStatus] = useState('all')
  const [open, setOpen] = useState(false)
  const [editing, setEditing] = useState<any>(null)
  const [viewing, setViewing] = useState<any>(null)
  const [deleteTarget, setDeleteTarget] = useState<any>(null)
  const branchesParam = selectedBranchIds.length ? `&branches=${selectedBranchIds.join(',')}` : ''
  const { data, reload } = useFetch<any>(`/api/members?status=${status !== 'all' ? status : ''}${branchesParam}`)
  const { data: plansData } = useFetch<any>('/api/memberships')
  const plans = plansData?.plans || []
  const members = (data?.members || []).filter((m: any) =>
    !search || m.memberId.toLowerCase().includes(search.toLowerCase()) || (m.firstName + ' ' + (m.lastName || '')).toLowerCase().includes(search.toLowerCase()) || m.phone?.includes(search))

  const doDelete = async () => {
    if (!deleteTarget) return
    try {
      await apiDelete(`/api/members/${deleteTarget.id}`)
      toast.success('Member deleted (soft delete)')
      setDeleteTarget(null); reload()
    } catch (e: any) { toast.error(e.message); setDeleteTarget(null) }
  }

  return (
    <div>
      <PageHeader title="Members"
        action={has('members.add') ? () => { setEditing(null); setOpen(true) } : undefined}
        actionLabel="Add Member" />
      <Toolbar>
        <SearchInput value={search} onChange={setSearch} placeholder="Search by ID, name, phone…" />
        <Select value={status} onValueChange={setStatus}>
          <SelectTrigger className="w-36"><SelectValue placeholder="Status" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All</SelectItem>
            <SelectItem value="Active">Active</SelectItem>
            <SelectItem value="Inactive">Inactive</SelectItem>
            <SelectItem value="Cancelled">Cancelled</SelectItem>
            <SelectItem value="Suspended">Suspended</SelectItem>
          </SelectContent>
        </Select>
        <Button variant="ghost" size="sm" onClick={reload}>Refresh</Button>
      </Toolbar>
      <DataTable
        columns={[
          { key: 'actions', label: 'Actions', sticky: true, render: (r: any) => (
            <div className="flex gap-0.5">
              <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); setViewing(r) }} title="View"><Eye className="h-3.5 w-3.5" /></Button>
              {has('members.edit') && <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); setEditing(r); setOpen(true) }} title="Edit"><Edit className="h-3.5 w-3.5" /></Button>}
              {has('members.delete') && <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); setDeleteTarget(r) }} title="Delete"><Trash2 className="h-3.5 w-3.5 text-red-600" /></Button>}
            </div>
          ) },
          { key: 'memberId', label: 'ID', mono: true },
          { key: 'name', label: 'Name', render: (r: any) => `${r.firstName} ${r.lastName || ''}` },
          { key: 'phone', label: 'Phone' },
          { key: 'gender', label: 'Gender' },
          { key: 'joiningDate', label: 'Joined', render: (r: any) => fmtDateStr(r.joiningDate) },
          { key: 'membershipPlan', label: 'Plan', render: (r: any) => r.membershipPlan?.name || '—' },
          { key: 'feeRelaxationDays', label: 'Grace', align: 'right', render: (r: any) => `${r.feeRelaxationDays}d` },
          { key: 'status', label: 'Status', render: (r: any) => <StatusBadge status={r.status} /> },
        ]}
        rows={members}
        onRowClick={(r: any) => setViewing(r)}
      />
      <MemberFormModal open={open} onClose={() => setOpen(false)} editing={editing} plans={plans} onSaved={() => { setOpen(false); reload() }} />
      <MemberViewModal open={!!viewing} member={viewing} onClose={() => setViewing(null)} onEdit={() => { setEditing(viewing); setViewing(null); setOpen(true) }} />
      <ConfirmModal open={!!deleteTarget} onClose={() => setDeleteTarget(null)} onConfirm={doDelete} title="Delete Member" message={deleteTarget ? `Soft-delete member "${deleteTarget.firstName} ${deleteTarget.lastName || ''}"? The record will remain in the database but disappear from the list.` : ''} />
    </div>
  )
}

function MemberFormModal({ open, onClose, editing, plans, onSaved }: any) {
  const { session, branches } = useApp()
  const [form, setForm] = useState<any>({})

  useEffect(() => {
    if (open) {
      setForm(editing ? { ...editing, joiningDate: editing.joiningDate?.slice(0, 10), billingStartDate: editing.billingStartDate?.slice(0, 10), dob: editing.dob?.slice(0, 10) } : {
        joiningDate: new Date().toISOString().slice(0, 10),
        billingStartDate: new Date().toISOString().slice(0, 10),
        branchId: session?.branchId || branches[0]?.id,
        feeRelaxationDays: 0,
        status: 'Active',
      })
    }
  }, [open, editing])

  const save = async () => {
    try {
      if (editing) {
        await apiPatch(`/api/members/${editing.id}`, form)
        toast.success('Member updated')
      } else {
        await apiPost('/api/members', form)
        toast.success('Member created')
      }
      onSaved()
    } catch (e: any) { toast.error(e.message) }
  }

  return (
    <Modal open={open} onClose={onClose} title={editing ? `Edit Member ${editing.memberId}` : 'New Member'} size="lg"
      footer={<>
        <Button variant="outline" onClick={onClose}>Cancel</Button>
        <Button onClick={save}><Save className="h-4 w-4 mr-1" />Save</Button>
      </>}>
      <Tabs defaultValue="basic">
        <TabsList className="grid grid-cols-3 mb-3">
          <TabsTrigger value="basic">Basic</TabsTrigger>
          <TabsTrigger value="contact">Contact</TabsTrigger>
          <TabsTrigger value="membership">Membership</TabsTrigger>
        </TabsList>
        <TabsContent value="basic" className="grid grid-cols-2 gap-3">
          <FormRow label="First Name" required><Input value={form.firstName || ''} onChange={e => setForm({ ...form, firstName: e.target.value })} /></FormRow>
          <FormRow label="Last Name"><Input value={form.lastName || ''} onChange={e => setForm({ ...form, lastName: e.target.value })} /></FormRow>
          <FormRow label="Gender">
            <Select value={form.gender || ''} onValueChange={v => setForm({ ...form, gender: v })}>
              <SelectTrigger><SelectValue placeholder="—" /></SelectTrigger>
              <SelectContent><SelectItem value="Male">Male</SelectItem><SelectItem value="Female">Female</SelectItem><SelectItem value="Other">Other</SelectItem></SelectContent>
            </Select>
          </FormRow>
          <FormRow label="Date of Birth"><Input type="date" value={form.dob || ''} onChange={e => setForm({ ...form, dob: e.target.value })} /></FormRow>
          <FormRow label="CNIC"><Input value={form.cnic || ''} onChange={e => setForm({ ...form, cnic: e.target.value })} /></FormRow>
          <FormRow label="Photo URL"><Input value={form.photo || ''} onChange={e => setForm({ ...form, photo: e.target.value })} /></FormRow>
          <FormRow label="Branch" required>
            <Select value={form.branchId || ''} onValueChange={v => setForm({ ...form, branchId: v })}>
              <SelectTrigger><SelectValue placeholder="Select branch" /></SelectTrigger>
              <SelectContent>{branches.map((b: any) => <SelectItem key={b.id} value={b.id}>{b.name}</SelectItem>)}</SelectContent>
            </Select>
          </FormRow>
        </TabsContent>
        <TabsContent value="contact" className="grid grid-cols-2 gap-3">
          <FormRow label="Phone"><Input value={form.phone || ''} onChange={e => setForm({ ...form, phone: e.target.value })} /></FormRow>
          <FormRow label="WhatsApp">
            <div className="flex gap-2 items-center">
              <Input value={form.whatsapp || ''} onChange={e => setForm({ ...form, whatsapp: e.target.value })} />
              <label className="flex items-center gap-1 text-xs whitespace-nowrap cursor-pointer">
                <input type="checkbox" checked={form.sameAsPhone || false} onChange={e => {
                  if (e.target.checked) setForm({ ...form, sameAsPhone: true, whatsapp: form.phone || '' })
                  else setForm({ ...form, sameAsPhone: false })
                }} />
                Same as Phone
              </label>
            </div>
          </FormRow>
          <FormRow label="Email"><Input value={form.email || ''} onChange={e => setForm({ ...form, email: e.target.value })} /></FormRow>
          <FormRow label="Emergency Contact"><Input value={form.emergencyContact || ''} onChange={e => setForm({ ...form, emergencyContact: e.target.value })} /></FormRow>
          <FormRow label="Emergency #"><Input value={form.emergencyContactNo || ''} onChange={e => setForm({ ...form, emergencyContactNo: e.target.value })} /></FormRow>
          <div className="col-span-2"><FormRow label="Address"><Textarea rows={2} value={form.address || ''} onChange={e => setForm({ ...form, address: e.target.value })} /></FormRow></div>
        </TabsContent>
        <TabsContent value="membership" className="grid grid-cols-2 gap-3">
          <FormRow label="Joining Date" required><Input type="date" value={form.joiningDate || ''} onChange={e => setForm({ ...form, joiningDate: e.target.value })} /></FormRow>
          <FormRow label="Billing Start Date"><Input type="date" value={form.billingStartDate || ''} onChange={e => setForm({ ...form, billingStartDate: e.target.value })} /></FormRow>
          <FormRow label="Fee Relaxation Days (0–27)">
            <Input type="number" min={0} max={27} value={form.feeRelaxationDays || 0} onChange={e => setForm({ ...form, feeRelaxationDays: Math.max(0, Math.min(27, Number(e.target.value))) })} />
          </FormRow>
          <FormRow label="Membership Plan">
            <Select value={form.membershipPlanId || ''} onValueChange={v => setForm({ ...form, membershipPlanId: v })}>
              <SelectTrigger><SelectValue placeholder="—" /></SelectTrigger>
              <SelectContent>{plans.map((p: any) => <SelectItem key={p.id} value={p.id}>{p.name} — {fmtMoney(p.amount)}</SelectItem>)}</SelectContent>
            </Select>
          </FormRow>
          <FormRow label="Status">
            <Select value={form.status || 'Active'} onValueChange={v => setForm({ ...form, status: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="Active">Active</SelectItem>
                <SelectItem value="Inactive">Inactive</SelectItem>
                <SelectItem value="Cancelled">Cancelled</SelectItem>
                <SelectItem value="Suspended">Suspended</SelectItem>
              </SelectContent>
            </Select>
          </FormRow>
          <div className="col-span-2"><FormRow label="Notes"><Textarea rows={2} value={form.notes || ''} onChange={e => setForm({ ...form, notes: e.target.value })} /></FormRow></div>
        </TabsContent>
      </Tabs>
    </Modal>
  )
}

function MemberViewModal({ open, member, onClose, onEdit }: any) {
  const { data } = useFetch<any>(member ? `/api/members/${member.id}` : null)
  const m = data?.member
  if (!m) return null
  return (
    <Modal open={open} onClose={onClose} title={`${m.memberId} — ${m.firstName} ${m.lastName || ''}`} size="lg"
      footer={<><Button variant="outline" onClick={onClose}>Close</Button><Button onClick={onEdit}><Edit className="h-3.5 w-3.5 mr-1" />Edit</Button></>}>
      <Tabs defaultValue="profile">
        <TabsList className="grid grid-cols-5 mb-3">
          <TabsTrigger value="profile">Profile</TabsTrigger>
          <TabsTrigger value="fees">Fees</TabsTrigger>
          <TabsTrigger value="attendance">Attendance</TabsTrigger>
          <TabsTrigger value="freezes">Freezes</TabsTrigger>
          <TabsTrigger value="progress">Progress</TabsTrigger>
        </TabsList>
        <TabsContent value="profile">
          <div className="grid grid-cols-2 gap-3 text-sm">
            <div><div className="text-xs text-muted-foreground">Phone</div><div>{m.phone || '—'}</div></div>
            <div><div className="text-xs text-muted-foreground">WhatsApp</div><div>{m.whatsapp || '—'}</div></div>
            <div><div className="text-xs text-muted-foreground">CNIC</div><div>{m.cnic || '—'}</div></div>
            <div><div className="text-xs text-muted-foreground">Gender</div><div>{m.gender || '—'}</div></div>
            <div><div className="text-xs text-muted-foreground">Joining</div><div>{fmtDateStr(m.joiningDate)}</div></div>
            <div><div className="text-xs text-muted-foreground">Billing Start</div><div>{fmtDateStr(m.billingStartDate)}</div></div>
            <div><div className="text-xs text-muted-foreground">Fee Relaxation</div><div>{m.feeRelaxationDays} days</div></div>
            <div><div className="text-xs text-muted-foreground">Plan</div><div>{m.membershipPlan?.name || '—'}</div></div>
            <div><div className="text-xs text-muted-foreground">Branch</div><div>{m.branch?.name}</div></div>
            <div><div className="text-xs text-muted-foreground">Status</div><div><StatusBadge status={m.status} /></div></div>
            <div className="col-span-2"><div className="text-xs text-muted-foreground">Address</div><div>{m.address || '—'}</div></div>
          </div>
        </TabsContent>
        <TabsContent value="fees">
          <DataTable
            columns={[
              { key: 'feeNo', label: 'Fee #', mono: true },
              { key: 'dueDate', label: 'Due', render: (r: any) => fmtDateStr(r.dueDate) },
              { key: 'amount', label: 'Amount', align: 'right', mono: true, render: (r: any) => fmtMoney(r.amount) },
              { key: 'paidAmount', label: 'Paid', align: 'right', mono: true, render: (r: any) => fmtMoney(r.paidAmount) },
              { key: 'balance', label: 'Balance', align: 'right', mono: true, render: (r: any) => fmtMoney(r.balance) },
              { key: 'status', label: 'Status', render: (r: any) => <StatusBadge status={r.status} /> },
            ]}
            rows={m.fees || []}
            empty="No fees"
          />
        </TabsContent>
        <TabsContent value="attendance">
          <DataTable
            columns={[
              { key: 'date', label: 'Date', render: (r: any) => fmtDateStr(r.date) },
              { key: 'checkIn', label: 'Check In', render: (r: any) => r.checkIn ? fmtDateTime(r.checkIn) : '—' },
              { key: 'checkOut', label: 'Check Out', render: (r: any) => r.checkOut ? fmtDateTime(r.checkOut) : '—' },
              { key: 'notes', label: 'Notes' },
            ]}
            rows={m.attendance || []}
            empty="No attendance"
          />
        </TabsContent>
        <TabsContent value="freezes">
          <DataTable
            columns={[
              { key: 'freezeFrom', label: 'From', render: (r: any) => fmtDateStr(r.freezeFrom) },
              { key: 'freezeTo', label: 'To', render: (r: any) => fmtDateStr(r.freezeTo) },
              { key: 'days', label: 'Days', align: 'right' },
              { key: 'reason', label: 'Reason' },
              { key: 'status', label: 'Status', render: (r: any) => <StatusBadge status={r.status} /> },
            ]}
            rows={m.freezes || []}
            empty="No freezes"
          />
        </TabsContent>
        <TabsContent value="progress">
          <DataTable
            columns={[
              { key: 'date', label: 'Date', render: (r: any) => fmtDateStr(r.date) },
              { key: 'weight', label: 'Weight', align: 'right', render: (r: any) => r.weight || '—' },
              { key: 'chest', label: 'Chest', align: 'right', render: (r: any) => r.chest || '—' },
              { key: 'waist', label: 'Waist', align: 'right', render: (r: any) => r.waist || '—' },
              { key: 'notes', label: 'Notes' },
            ]}
            rows={m.progress || []}
            empty="No progress entries"
          />
        </TabsContent>
      </Tabs>
    </Modal>
  )
}

// =================================================================
// MEMBERSHIPS
// =================================================================
export function MembershipsModule() {
  const { has } = useApp()
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<any>({})
  const { data, reload } = useFetch<any>('/api/memberships')
  const plans = data?.plans || []
  return (
    <div>
      <PageHeader title="Membership Plans"
        action={has('memberships.add') ? () => { setForm({}); setOpen(true) } : undefined}
        actionLabel="Add Plan" />
      <Toolbar><Button variant="ghost" size="sm" onClick={reload}>Refresh</Button></Toolbar>
      <DataTable
        columns={[
          { key: 'code', label: 'Code', mono: true },
          { key: 'name', label: 'Name' },
          { key: 'durationDays', label: 'Duration', align: 'right', render: (r: any) => `${r.durationDays} days` },
          { key: 'amount', label: 'Amount', align: 'right', mono: true, render: (r: any) => fmtMoney(r.amount) },
          { key: 'description', label: 'Description' },
          { key: 'isActive', label: 'Status', render: (r: any) => <StatusBadge status={r.isActive ? 'Active' : 'Inactive'} /> },
        ]}
        rows={plans}
      />
      <Modal open={open} onClose={() => setOpen(false)} title="Add Plan"
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={async () => {
            try { await apiPost('/api/memberships', form); toast.success('Plan created'); setOpen(false); reload() }
            catch (e: any) { toast.error(e.message) }
          }}><Save className="h-4 w-4 mr-1" />Save</Button>
        </>}>
        <div className="grid grid-cols-2 gap-3">
          <FormRow label="Name" required><Input value={form.name || ''} onChange={e => setForm({ ...form, name: e.target.value })} /></FormRow>
          <FormRow label="Duration (days)" required><Input type="number" value={form.durationDays || 30} onChange={e => setForm({ ...form, durationDays: Number(e.target.value) })} /></FormRow>
          <FormRow label="Amount" required><Input type="number" value={form.amount || 0} onChange={e => setForm({ ...form, amount: Number(e.target.value) })} /></FormRow>
          <FormRow label="Active"><Switch checked={form.isActive !== false} onCheckedChange={v => setForm({ ...form, isActive: v })} /></FormRow>
          <div className="col-span-2"><FormRow label="Description"><Textarea rows={2} value={form.description || ''} onChange={e => setForm({ ...form, description: e.target.value })} /></FormRow></div>
        </div>
      </Modal>
    </div>
  )
}

// =================================================================
// ATTENDANCE
// =================================================================
export function AttendanceModule() {
  const { has, selectedBranchIds } = useApp()
  const [date, setDate] = useState(new Date().toISOString().slice(0, 10))
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<any>({ memberId: '', checkIn: new Date().toISOString().slice(0, 16) })
  const branchesParam = selectedBranchIds.length ? `&branches=${selectedBranchIds.join(',')}` : ''
  const { data, reload } = useFetch<any>(`/api/attendance?date=${date}${branchesParam}`)
  const { data: membersData } = useFetch<any>('/api/members' + (branchesParam ? `?${branchesParam.slice(1)}` : ''))
  const records = data?.records || []

  return (
    <div>
      <PageHeader title="Attendance"
        action={has('attendance.add') ? () => { setForm({ memberId: '', checkIn: new Date().toISOString().slice(0, 16) }); setOpen(true) } : undefined}
        actionLabel="Check In" />
      <Toolbar>
        <FormRow label="Date"><Input type="date" value={date} onChange={e => setDate(e.target.value)} className="w-40" /></FormRow>
        <Button variant="ghost" size="sm" onClick={reload}>Refresh</Button>
      </Toolbar>
      <DataTable
        columns={[
          { key: 'member', label: 'Member', render: (r: any) => `${r.member?.firstName} ${r.member?.lastName || ''}` },
          { key: 'member', label: 'Member ID', render: (r: any) => r.member?.memberId, mono: true },
          { key: 'date', label: 'Date', render: (r: any) => fmtDateStr(r.date) },
          { key: 'checkIn', label: 'Check In', render: (r: any) => r.checkIn ? fmtDateTime(r.checkIn) : '—' },
          { key: 'checkOut', label: 'Check Out', render: (r: any) => r.checkOut ? fmtDateTime(r.checkOut) : '—' },
          { key: 'notes', label: 'Notes' },
        ]}
        rows={records}
      />
      <Modal open={open} onClose={() => setOpen(false)} title="Manual Check In"
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={async () => {
            try { await apiPost('/api/attendance', { memberId: form.memberId, checkIn: form.checkIn }); toast.success('Checked in'); setOpen(false); reload() }
            catch (e: any) { toast.error(e.message) }
          }}><Save className="h-4 w-4 mr-1" />Check In</Button>
        </>}>
        <FormRow label="Member" required>
          <Select value={form.memberId} onValueChange={v => setForm({ ...form, memberId: v })}>
            <SelectTrigger><SelectValue placeholder="Select member" /></SelectTrigger>
            <SelectContent>{(membersData?.members || []).map((m: any) => <SelectItem key={m.id} value={m.id}>{m.memberId} — {m.firstName} {m.lastName || ''}</SelectItem>)}</SelectContent>
          </Select>
        </FormRow>
        <FormRow label="Check In Time"><Input type="datetime-local" value={form.checkIn} onChange={e => setForm({ ...form, checkIn: e.target.value })} /></FormRow>
      </Modal>
    </div>
  )
}

// =================================================================
// FEES
// =================================================================
export function FeesModule() {
  const { has, selectedBranchIds } = useApp()
  const [status, setStatus] = useState('all')
  const [search, setSearch] = useState('')
  const [open, setOpen] = useState(false)
  const [payOpen, setPayOpen] = useState(false)
  const [payTarget, setPayTarget] = useState<any>(null)
  const branchesParam = selectedBranchIds.length ? `&branches=${selectedBranchIds.join(',')}` : ''
  const { data, reload } = useFetch<any>(`/api/fees?status=${status !== 'all' ? status : ''}${branchesParam}`)
  const { data: membersData } = useFetch<any>('/api/members' + (branchesParam ? `?${branchesParam.slice(1)}` : ''))
  const { data: accountsData } = useFetch<any>('/api/accounts?bookType=Cash')
  const { data: bankAccountsData } = useFetch<any>('/api/accounts?bookType=Bank')
  const fees = (data?.fees || []).filter((f: any) =>
    !search || f.feeNo.toLowerCase().includes(search.toLowerCase()) || f.member?.firstName?.toLowerCase().includes(search.toLowerCase()))

  return (
    <div>
      <PageHeader title="Fees & Invoices"
        action={has('fees.add') ? () => setOpen(true) : undefined}
        actionLabel="Create Fee" />
      <Toolbar>
        <SearchInput value={search} onChange={setSearch} placeholder="Search by fee # or member…" />
        <Select value={status} onValueChange={setStatus}>
          <SelectTrigger className="w-36"><SelectValue placeholder="Status" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All</SelectItem>
            <SelectItem value="Unpaid">Unpaid</SelectItem>
            <SelectItem value="Partial">Partial</SelectItem>
            <SelectItem value="Paid">Paid</SelectItem>
            <SelectItem value="Late">Late</SelectItem>
            <SelectItem value="Overdue">Overdue</SelectItem>
          </SelectContent>
        </Select>
        <Button variant="ghost" size="sm" onClick={reload}>Refresh</Button>
      </Toolbar>
      <DataTable
        columns={[
          { key: 'feeNo', label: 'Fee #', mono: true },
          { key: 'member', label: 'Member', render: (r: any) => `${r.member?.firstName} ${r.member?.lastName || ''}` },
          { key: 'billingPeriodStart', label: 'Period', render: (r: any) => `${fmtDateStr(r.billingPeriodStart)} — ${fmtDateStr(r.billingPeriodEnd)}` },
          { key: 'amount', label: 'Amount', align: 'right', mono: true, render: (r: any) => fmtMoney(r.amount) },
          { key: 'paidAmount', label: 'Paid', align: 'right', mono: true, render: (r: any) => fmtMoney(r.paidAmount) },
          { key: 'balance', label: 'Balance', align: 'right', mono: true, render: (r: any) => fmtMoney(r.balance) },
          { key: 'dueDate', label: 'Due', render: (r: any) => fmtDateStr(r.dueDate) },
          { key: 'status', label: 'Status', render: (r: any) => <StatusBadge status={r.status} /> },
          { key: 'actions', label: '', align: 'right', render: (r: any) => (
            r.status !== 'Paid' && has('fees.post') ? (
              <Button size="sm" onClick={(e) => { e.stopPropagation(); setPayTarget(r); setPayOpen(true) }}>Collect</Button>
            ) : null
          ) },
        ]}
        rows={fees}
      />
      <FeeCreateModal open={open} onClose={() => setOpen(false)} members={membersData?.members || []} onSaved={() => { setOpen(false); reload() }} />
      <FeePayModal open={payOpen} fee={payTarget} cashAccounts={accountsData?.accounts || []} bankAccounts={bankAccountsData?.accounts || []} onClose={() => setPayOpen(false)} onPaid={() => { setPayOpen(false); reload() }} />
    </div>
  )
}

function FeeCreateModal({ open, onClose, members, onSaved }: any) {
  const { session, branches } = useApp()
  const [form, setForm] = useState<any>({ amount: 0, dueDate: new Date().toISOString().slice(0, 10) })
  return (
    <Modal open={open} onClose={onClose} title="Create Fee"
      footer={<>
        <Button variant="outline" onClick={onClose}>Cancel</Button>
        <Button onClick={async () => {
          try { await apiPost('/api/fees', form); toast.success('Fee created'); onSaved() }
          catch (e: any) { toast.error(e.message) }
        }}><Save className="h-4 w-4 mr-1" />Create</Button>
      </>}>
      <FormRow label="Member" required>
        <Select value={form.memberId || ''} onValueChange={v => {
          const m = members.find((x: any) => x.id === v)
          setForm({ ...form, memberId: v, amount: m?.membershipPlan?.amount || 0 })
        }}>
          <SelectTrigger><SelectValue placeholder="Select member" /></SelectTrigger>
          <SelectContent>{members.map((m: any) => <SelectItem key={m.id} value={m.id}>{m.memberId} — {m.firstName} {m.lastName || ''}</SelectItem>)}</SelectContent>
        </Select>
      </FormRow>
      <div className="grid grid-cols-2 gap-3 mt-3">
        <FormRow label="Billing Start"><Input type="date" value={form.billingPeriodStart || ''} onChange={e => setForm({ ...form, billingPeriodStart: e.target.value })} /></FormRow>
        <FormRow label="Billing End"><Input type="date" value={form.billingPeriodEnd || ''} onChange={e => setForm({ ...form, billingPeriodEnd: e.target.value })} /></FormRow>
        <FormRow label="Amount"><Input type="number" value={form.amount || 0} onChange={e => setForm({ ...form, amount: Number(e.target.value) })} /></FormRow>
        <FormRow label="Discount"><Input type="number" value={form.discount || 0} onChange={e => setForm({ ...form, discount: Number(e.target.value) })} /></FormRow>
        <FormRow label="Due Date"><Input type="date" value={form.dueDate || ''} onChange={e => setForm({ ...form, dueDate: e.target.value })} /></FormRow>
      </div>
    </Modal>
  )
}

function FeePayModal({ open, fee, cashAccounts, bankAccounts, onClose, onPaid }: any) {
  const { session } = useApp()
  const [form, setForm] = useState<any>({ amount: 0, method: 'Cash', accountId: '', reference: '', paymentDate: new Date().toISOString().slice(0, 10) })
  useEffect(() => { if (fee) setForm({ amount: fee.balance || 0, method: 'Cash', accountId: '', reference: '', paymentDate: new Date().toISOString().slice(0, 10) }) }, [fee])

  const accounts = form.method === 'Cash' ? cashAccounts : form.method === 'Bank' ? bankAccounts : [...cashAccounts, ...bankAccounts]

  return (
    <Modal open={open} onClose={onClose} title={`Collect Payment — ${fee?.feeNo || ''}`}
      footer={<>
        <Button variant="outline" onClick={onClose}>Cancel</Button>
        <Button onClick={async () => {
          try { await apiPost('/api/fees/pay', { feeId: fee.id, ...form }); toast.success('Payment recorded and voucher posted'); onPaid() }
          catch (e: any) { toast.error(e.message) }
        }}><Banknote className="h-4 w-4 mr-1" />Collect & Post</Button>
      </>}>
      {fee && (
        <div className="mb-3 grid grid-cols-3 gap-3 text-sm border rounded p-3 bg-muted/30">
          <div><div className="text-xs text-muted-foreground">Member</div><div className="font-medium">{fee.member?.firstName} {fee.member?.lastName || ''}</div></div>
          <div><div className="text-xs text-muted-foreground">Total</div><div className="font-mono">{fmtMoney(fee.amount)}</div></div>
          <div><div className="text-xs text-muted-foreground">Balance</div><div className="font-mono font-semibold">{fmtMoney(fee.balance)}</div></div>
        </div>
      )}
      <div className="grid grid-cols-2 gap-3">
        <FormRow label="Payment Method" required>
          <Select value={form.method} onValueChange={v => setForm({ ...form, method: v, accountId: '' })}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="Cash">Cash</SelectItem>
              <SelectItem value="Bank">Bank</SelectItem>
              <SelectItem value="Online">Online</SelectItem>
            </SelectContent>
          </Select>
        </FormRow>
        <FormRow label="Amount" required><Input type="number" value={form.amount || 0} onChange={e => setForm({ ...form, amount: Number(e.target.value) })} /></FormRow>
        <FormRow label="Account" required>
          <Select value={form.accountId} onValueChange={v => setForm({ ...form, accountId: v })}>
            <SelectTrigger><SelectValue placeholder="Select account" /></SelectTrigger>
            <SelectContent>{accounts.map((a: any) => <SelectItem key={a.id} value={a.id}>{a.code} — {a.name}</SelectItem>)}</SelectContent>
          </Select>
        </FormRow>
        <FormRow label="Payment Date"><Input type="date" value={form.paymentDate} onChange={e => setForm({ ...form, paymentDate: e.target.value })} /></FormRow>
        <div className="col-span-2"><FormRow label="Reference"><Input value={form.reference} onChange={e => setForm({ ...form, reference: e.target.value })} placeholder="Optional receipt/cheque no." /></FormRow></div>
      </div>
      <div className="mt-3 text-xs text-muted-foreground">
        Collecting will automatically post a {form.method === 'Cash' ? 'Cash Receipt Voucher (CRV)' : 'Bank Receipt Voucher (BRV)'} to the books. No manual voucher needed.
      </div>
    </Modal>
  )
}

// =================================================================
// PROSPECTS
// =================================================================
export function ProspectsModule() {
  const { has, selectedBranchIds } = useApp()
  const [status, setStatus] = useState('all')
  const [search, setSearch] = useState('')
  const [open, setOpen] = useState(false)
  const [editing, setEditing] = useState<any>(null)
  const [deleteTarget, setDeleteTarget] = useState<any>(null)
  const [form, setForm] = useState<any>({})
  const branchesParam = selectedBranchIds.length ? `&branches=${selectedBranchIds.join(',')}` : ''
  const { data, reload } = useFetch<any>(`/api/prospects?status=${status !== 'all' ? status : ''}${branchesParam}`)
  const prospects = (data?.prospects || []).filter((p: any) =>
    !search || p.name?.toLowerCase().includes(search.toLowerCase()) || p.phone?.includes(search))

  const openAdd = () => { setEditing(null); setForm({ source: 'WalkIn', status: 'New' }); setOpen(true) }
  const openEdit = (p: any) => { setEditing(p); setForm({ ...p }); setOpen(true) }
  const doDelete = async () => {
    if (!deleteTarget) return
    try { await apiDelete(`/api/prospects/${deleteTarget.id}`); toast.success('Prospect deleted'); setDeleteTarget(null); reload() }
    catch (e: any) { toast.error(e.message); setDeleteTarget(null) }
  }

  return (
    <div>
      <PageHeader title="Prospects / Inquiries"
        action={has('prospects.add') ? openAdd : undefined}
        actionLabel="Add Prospect" />
      <Toolbar>
        <SearchInput value={search} onChange={setSearch} placeholder="Search name or phone…" />
        <Select value={status} onValueChange={setStatus}>
          <SelectTrigger className="w-36"><SelectValue placeholder="Status" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All</SelectItem>
            <SelectItem value="New">New</SelectItem>
            <SelectItem value="Contacted">Contacted</SelectItem>
            <SelectItem value="Interested">Interested</SelectItem>
            <SelectItem value="TrialScheduled">Trial Scheduled</SelectItem>
            <SelectItem value="FollowUp">Follow Up</SelectItem>
            <SelectItem value="Converted">Converted</SelectItem>
            <SelectItem value="Lost">Lost</SelectItem>
          </SelectContent>
        </Select>
        <Button variant="ghost" size="sm" onClick={reload}>Refresh</Button>
      </Toolbar>
      <DataTable
        columns={[
          { key: 'actions', label: 'Actions', sticky: true, render: (r: any) => (
            <div className="flex gap-0.5">
              {has('prospects.edit') && <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); openEdit(r) }} title="Edit"><Edit className="h-3.5 w-3.5" /></Button>}
              {has('prospects.delete') && <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); setDeleteTarget(r) }} title="Delete"><Trash2 className="h-3.5 w-3.5 text-red-600" /></Button>}
              {r.status !== 'Converted' && has('prospects.convert') && (
                <Button size="sm" variant="outline" onClick={async (e) => {
                  e.stopPropagation()
                  if (confirm(`Mark ${r.name} as converted?`)) {
                    try { await apiPatch(`/api/prospects/${r.id}`, { action: 'convert', convertedMemberId: null }); toast.success('Marked as converted'); reload() }
                    catch (e: any) { toast.error(e.message) }
                  }
                }}>Convert</Button>
              )}
            </div>
          ) },
          { key: 'prospectId', label: 'ID', mono: true },
          { key: 'name', label: 'Name' },
          { key: 'phone', label: 'Phone' },
          { key: 'source', label: 'Source' },
          { key: 'interestedMembership', label: 'Interested In' },
          { key: 'inquiryDate', label: 'Inquiry', render: (r: any) => fmtDateStr(r.inquiryDate) },
          { key: 'followUpDate', label: 'Follow Up', render: (r: any) => fmtDateStr(r.followUpDate) },
          { key: 'status', label: 'Status', render: (r: any) => <StatusBadge status={r.status} /> },
        ]}
        rows={prospects}
      />
      <Modal open={open} onClose={() => setOpen(false)} title={editing ? 'Edit Prospect' : 'Add Prospect'}
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={async () => {
            try {
              if (editing) { await apiPatch(`/api/prospects/${editing.id}`, form); toast.success('Prospect updated') }
              else { await apiPost('/api/prospects', form); toast.success('Prospect added') }
              setOpen(false); reload() }
            catch (e: any) { toast.error(e.message) }
          }}><Save className="h-4 w-4 mr-1" />Save</Button>
        </>}>
        <div className="grid grid-cols-2 gap-3">
          <FormRow label="Name" required><Input value={form.name || ''} onChange={e => setForm({ ...form, name: e.target.value })} /></FormRow>
          <FormRow label="Phone"><Input value={form.phone || ''} onChange={e => setForm({ ...form, phone: e.target.value })} /></FormRow>
          <FormRow label="WhatsApp">
            <div className="flex gap-2 items-center">
              <Input value={form.whatsapp || ''} onChange={e => setForm({ ...form, whatsapp: e.target.value })} />
              <label className="flex items-center gap-1 text-xs whitespace-nowrap cursor-pointer">
                <input type="checkbox" checked={form.sameAsPhone || false} onChange={e => {
                  if (e.target.checked) setForm({ ...form, sameAsPhone: true, whatsapp: form.phone || '' })
                  else setForm({ ...form, sameAsPhone: false })
                }} />
                Same as Phone
              </label>
            </div>
          </FormRow>
          <FormRow label="Gender">
            <Select value={form.gender || ''} onValueChange={v => setForm({ ...form, gender: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent><SelectItem value="Male">Male</SelectItem><SelectItem value="Female">Female</SelectItem><SelectItem value="Other">Other</SelectItem></SelectContent>
            </Select>
          </FormRow>
          <FormRow label="Age"><Input type="number" value={form.age || ''} onChange={e => setForm({ ...form, age: e.target.value })} /></FormRow>
          <FormRow label="Source">
            <Select value={form.source} onValueChange={v => setForm({ ...form, source: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="WalkIn">Walk In</SelectItem>
                <SelectItem value="Phone">Phone</SelectItem>
                <SelectItem value="WhatsApp">WhatsApp</SelectItem>
                <SelectItem value="Website">Website</SelectItem>
                <SelectItem value="Referral">Referral</SelectItem>
                <SelectItem value="Other">Other</SelectItem>
              </SelectContent>
            </Select>
          </FormRow>
          <FormRow label="Interested In"><Input value={form.interestedMembership || ''} onChange={e => setForm({ ...form, interestedMembership: e.target.value })} /></FormRow>
          <FormRow label="Status">
            <Select value={form.status} onValueChange={v => setForm({ ...form, status: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="New">New</SelectItem>
                <SelectItem value="Contacted">Contacted</SelectItem>
                <SelectItem value="Interested">Interested</SelectItem>
                <SelectItem value="TrialScheduled">Trial Scheduled</SelectItem>
                <SelectItem value="FollowUp">Follow Up</SelectItem>
              </SelectContent>
            </Select>
          </FormRow>
          <FormRow label="Inquiry Date"><Input type="date" value={form.inquiryDate || new Date().toISOString().slice(0, 10)} onChange={e => setForm({ ...form, inquiryDate: e.target.value })} /></FormRow>
          <FormRow label="Follow Up Date"><Input type="date" value={form.followUpDate || ''} onChange={e => setForm({ ...form, followUpDate: e.target.value })} /></FormRow>
          <div className="col-span-2"><FormRow label="Notes"><Textarea rows={2} value={form.notes || ''} onChange={e => setForm({ ...form, notes: e.target.value })} /></FormRow></div>
        </div>
      </Modal>
      <ConfirmModal open={!!deleteTarget} onClose={() => setDeleteTarget(null)} onConfirm={doDelete} title="Delete Prospect" message={deleteTarget ? `Delete prospect "${deleteTarget.name}"?` : ''} />
    </div>
  )
}

// =================================================================
// FREEZES
// =================================================================
export function FreezesModule() {
  const { has, selectedBranchIds } = useApp()
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<any>({})
  const { data, reload } = useFetch<any>('/api/freezes')
  const { data: membersData } = useFetch<any>('/api/members')
  const freezes = data?.freezes || []

  return (
    <div>
      <PageHeader title="Membership Freeze"
        action={has('freeze.add') ? () => { setForm({ freezeFrom: new Date().toISOString().slice(0, 10) }); setOpen(true) } : undefined}
        actionLabel="Freeze Membership" />
      <Toolbar><Button variant="ghost" size="sm" onClick={reload}>Refresh</Button></Toolbar>
      <DataTable
        columns={[
          { key: 'member', label: 'Member', render: (r: any) => `${r.member?.firstName} ${r.member?.lastName || ''}` },
          { key: 'freezeFrom', label: 'From', render: (r: any) => fmtDateStr(r.freezeFrom) },
          { key: 'freezeTo', label: 'To', render: (r: any) => fmtDateStr(r.freezeTo) },
          { key: 'days', label: 'Days', align: 'right' },
          { key: 'reason', label: 'Reason' },
          { key: 'status', label: 'Status', render: (r: any) => <StatusBadge status={r.status} /> },
          { key: 'actions', label: '', align: 'right', render: (r: any) =>
            r.status === 'Active' && has('freeze.edit') ? (
              <Button size="sm" variant="outline" onClick={async (e) => {
                e.stopPropagation()
                try { await apiPatch('/api/freezes', { id: r.id, action: 'lift' }); toast.success('Freeze lifted'); reload() }
                catch (e: any) { toast.error(e.message) }
              }}>Lift</Button>
            ) : null
          },
        ]}
        rows={freezes}
      />
      <Modal open={open} onClose={() => setOpen(false)} title="Freeze Membership"
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={async () => {
            try { await apiPost('/api/freezes', form); toast.success('Freeze applied'); setOpen(false); reload() }
            catch (e: any) { toast.error(e.message) }
          }}><Save className="h-4 w-4 mr-1" />Apply Freeze</Button>
        </>}>
        <FormRow label="Member" required>
          <Select value={form.memberId || ''} onValueChange={v => setForm({ ...form, memberId: v })}>
            <SelectTrigger><SelectValue placeholder="Select member" /></SelectTrigger>
            <SelectContent>{(membersData?.members || []).map((m: any) => <SelectItem key={m.id} value={m.id}>{m.memberId} — {m.firstName} {m.lastName || ''}</SelectItem>)}</SelectContent>
          </Select>
        </FormRow>
        <div className="grid grid-cols-2 gap-3 mt-3">
          <FormRow label="From" required><Input type="date" value={form.freezeFrom || ''} onChange={e => setForm({ ...form, freezeFrom: e.target.value })} /></FormRow>
          <FormRow label="To" required><Input type="date" value={form.freezeTo || ''} onChange={e => setForm({ ...form, freezeTo: e.target.value })} /></FormRow>
          <div className="col-span-2"><FormRow label="Reason"><Textarea rows={2} value={form.reason || ''} onChange={e => setForm({ ...form, reason: e.target.value })} /></FormRow></div>
        </div>
      </Modal>
    </div>
  )
}

// =================================================================
// FOLLOW-UPS
// =================================================================
export function FollowUpsModule() {
  const { has, selectedBranchIds } = useApp()
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<any>({ type: 'WhatsApp' })
  const { data, reload } = useFetch<any>('/api/followups')
  const records = data?.records || []
  return (
    <div>
      <PageHeader title="Member Follow Up History"
        action={has('followups.add') ? () => { setForm({ type: 'WhatsApp', date: new Date().toISOString().slice(0, 10) }); setOpen(true) } : undefined}
        actionLabel="Log Follow Up" />
      <Toolbar><Button variant="ghost" size="sm" onClick={reload}>Refresh</Button></Toolbar>
      <DataTable
        columns={[
          { key: 'date', label: 'Date', render: (r: any) => fmtDateStr(r.date) },
          { key: 'member', label: 'Member', render: (r: any) => r.member ? `${r.member.firstName} ${r.member.lastName || ''}` : '—' },
          { key: 'type', label: 'Type' },
          { key: 'notes', label: 'Notes' },
          { key: 'outcome', label: 'Outcome' },
          { key: 'nextFollowUpDate', label: 'Next', render: (r: any) => fmtDateStr(r.nextFollowUpDate) },
        ]}
        rows={records}
      />
      <Modal open={open} onClose={() => setOpen(false)} title="Log Follow Up"
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={async () => {
            try { await apiPost('/api/followups', form); toast.success('Follow up logged'); setOpen(false); reload() }
            catch (e: any) { toast.error(e.message) }
          }}><Save className="h-4 w-4 mr-1" />Save</Button>
        </>}>
        <div className="grid grid-cols-2 gap-3">
          <FormRow label="Type">
            <Select value={form.type} onValueChange={v => setForm({ ...form, type: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="WhatsApp">WhatsApp</SelectItem>
                <SelectItem value="Phone">Phone</SelectItem>
                <SelectItem value="InPerson">In Person</SelectItem>
                <SelectItem value="Email">Email</SelectItem>
                <SelectItem value="Other">Other</SelectItem>
              </SelectContent>
            </Select>
          </FormRow>
          <FormRow label="Date"><Input type="date" value={form.date || ''} onChange={e => setForm({ ...form, date: e.target.value })} /></FormRow>
          <FormRow label="Member (optional)">
            <Input value={form.memberId || ''} onChange={e => setForm({ ...form, memberId: e.target.value })} placeholder="Member ID" />
          </FormRow>
          <FormRow label="Outcome">
            <Select value={form.outcome || ''} onValueChange={v => setForm({ ...form, outcome: v })}>
              <SelectTrigger><SelectValue placeholder="—" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="Promise">Promise to pay</SelectItem>
                <SelectItem value="NoAnswer">No answer</SelectItem>
                <SelectItem value="NotInterested">Not interested</SelectItem>
                <SelectItem value="Paid">Paid</SelectItem>
                <SelectItem value="Other">Other</SelectItem>
              </SelectContent>
            </Select>
          </FormRow>
          <div className="col-span-2"><FormRow label="Notes"><Textarea rows={2} value={form.notes || ''} onChange={e => setForm({ ...form, notes: e.target.value })} /></FormRow></div>
        </div>
      </Modal>
    </div>
  )
}

// =================================================================
// MEMBER STATUS (bulk update)
// =================================================================
export function MemberStatusModule() {
  const { has, selectedBranchIds } = useApp()
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [bulkStatus, setBulkStatus] = useState('Active')
  const branchesParam = selectedBranchIds.length ? `&branches=${selectedBranchIds.join(',')}` : ''
  const { data, reload } = useFetch<any>(`/api/members${branchesParam ? `?${branchesParam.slice(1)}` : '?'}`)
  const members = data?.members || []

  const toggle = (id: string) => {
    const n = new Set(selected); if (n.has(id)) n.delete(id); else n.add(id); setSelected(n)
  }
  const apply = async () => {
    if (selected.size === 0) { toast.error('Select at least one member'); return }
    for (const id of selected) {
      try { await apiPatch(`/api/members/${id}`, { action: 'status', status: bulkStatus }) } catch (e: any) { toast.error(e.message); return }
    }
    toast.success(`${selected.size} member(s) updated to ${bulkStatus}`)
    setSelected(new Set()); reload()
  }

  return (
    <div>
      <PageHeader title="Member Status" />
      <Toolbar>
        <Select value={bulkStatus} onValueChange={setBulkStatus}>
          <SelectTrigger className="w-36"><SelectValue /></SelectTrigger>
          <SelectContent>
            <SelectItem value="Active">Active</SelectItem>
            <SelectItem value="Inactive">Inactive</SelectItem>
            <SelectItem value="Cancelled">Cancelled</SelectItem>
            <SelectItem value="Suspended">Suspended</SelectItem>
          </SelectContent>
        </Select>
        {has('members.status') && selected.size > 0 && <Button size="sm" onClick={apply}>Apply to {selected.size} selected</Button>}
        <Button variant="ghost" size="sm" onClick={reload}>Refresh</Button>
      </Toolbar>
      <DataTable
        columns={[
          { key: 'select', label: '', render: (r: any) => <Checkbox checked={selected.has(r.id)} onCheckedChange={() => toggle(r.id)} onClick={(e: any) => e.stopPropagation()} /> },
          { key: 'memberId', label: 'ID', mono: true },
          { key: 'name', label: 'Name', render: (r: any) => `${r.firstName} ${r.lastName || ''}` },
          { key: 'phone', label: 'Phone' },
          { key: 'branch', label: 'Branch', render: (r: any) => r.branch?.name },
          { key: 'status', label: 'Status', render: (r: any) => <StatusBadge status={r.status} /> },
        ]}
        rows={members}
      />
    </div>
  )
}

// =================================================================
// EQUIPMENT
// =================================================================
export function EquipmentModule() {
  const { has, selectedBranchIds, branches } = useApp()
  const [search, setSearch] = useState('')
  const [condition, setCondition] = useState('all')
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<any>({})
  const branchesParam = selectedBranchIds.length ? `&branches=${selectedBranchIds.join(',')}` : ''
  const { data, reload } = useFetch<any>(`/api/equipment?condition=${condition !== 'all' ? condition : ''}${branchesParam}`)
  const equipment = (data?.equipment || []).filter((e: any) => !search || e.code?.toLowerCase().includes(search.toLowerCase()) || e.name?.toLowerCase().includes(search.toLowerCase()))

  return (
    <div>
      <PageHeader title="Equipment"
        action={has('equipment.add') ? () => { setForm({ condition: 'Working', category: 'Machine' }); setOpen(true) } : undefined}
        actionLabel="Add Equipment" />
      <Toolbar>
        <SearchInput value={search} onChange={setSearch} placeholder="Search equipment…" />
        <Select value={condition} onValueChange={setCondition}>
          <SelectTrigger className="w-36"><SelectValue placeholder="Condition" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All conditions</SelectItem>
            <SelectItem value="Working">Working</SelectItem>
            <SelectItem value="Broken">Broken</SelectItem>
            <SelectItem value="UnderMaintenance">Under Maintenance</SelectItem>
            <SelectItem value="Retired">Retired</SelectItem>
          </SelectContent>
        </Select>
        <Button variant="ghost" size="sm" onClick={reload}>Refresh</Button>
      </Toolbar>
      <DataTable
        columns={[
          { key: 'code', label: 'Code', mono: true },
          { key: 'name', label: 'Name' },
          { key: 'category', label: 'Category' },
          { key: 'quantity', label: 'Qty', align: 'right' },
          { key: 'purchasePrice', label: 'Price', align: 'right', mono: true, render: (r: any) => fmtMoney(r.purchasePrice) },
          { key: 'branch', label: 'Branch', render: (r: any) => r.branch?.name },
          { key: 'condition', label: 'Condition', render: (r: any) => <StatusBadge status={r.condition} /> },
          { key: 'status', label: 'Status', render: (r: any) => <StatusBadge status={r.status} /> },
        ]}
        rows={equipment}
      />
      <Modal open={open} onClose={() => setOpen(false)} title="Add Equipment"
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={async () => {
            try { await apiPost('/api/equipment', form); toast.success('Equipment added'); setOpen(false); reload() }
            catch (e: any) { toast.error(e.message) }
          }}><Save className="h-4 w-4 mr-1" />Save</Button>
        </>}>
        <div className="grid grid-cols-2 gap-3">
          <FormRow label="Name" required><Input value={form.name || ''} onChange={e => setForm({ ...form, name: e.target.value })} /></FormRow>
          <FormRow label="Category">
            <Select value={form.category || 'Machine'} onValueChange={v => setForm({ ...form, category: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="Machine">Machine</SelectItem>
                <SelectItem value="Dumbbell">Dumbbell</SelectItem>
                <SelectItem value="Bar">Bar</SelectItem>
                <SelectItem value="Weight">Weight</SelectItem>
                <SelectItem value="Accessory">Accessory</SelectItem>
                <SelectItem value="Consumable">Consumable</SelectItem>
              </SelectContent>
            </Select>
          </FormRow>
          <FormRow label="Branch" required>
            <Select value={form.branchId || ''} onValueChange={v => setForm({ ...form, branchId: v })}>
              <SelectTrigger><SelectValue placeholder="Select" /></SelectTrigger>
              <SelectContent>{branches.map((b: any) => <SelectItem key={b.id} value={b.id}>{b.name}</SelectItem>)}</SelectContent>
            </Select>
          </FormRow>
          <FormRow label="Quantity"><Input type="number" value={form.quantity || 1} onChange={e => setForm({ ...form, quantity: Number(e.target.value) })} /></FormRow>
          <FormRow label="Purchase Date"><Input type="date" value={form.purchaseDate || ''} onChange={e => setForm({ ...form, purchaseDate: e.target.value })} /></FormRow>
          <FormRow label="Purchase Price"><Input type="number" value={form.purchasePrice || 0} onChange={e => setForm({ ...form, purchasePrice: Number(e.target.value) })} /></FormRow>
          <FormRow label="Condition">
            <Select value={form.condition || 'Working'} onValueChange={v => setForm({ ...form, condition: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="Working">Working</SelectItem>
                <SelectItem value="Broken">Broken</SelectItem>
                <SelectItem value="UnderMaintenance">Under Maintenance</SelectItem>
                <SelectItem value="Retired">Retired</SelectItem>
              </SelectContent>
            </Select>
          </FormRow>
          <FormRow label="Bill Reference"><Input value={form.billReference || ''} onChange={e => setForm({ ...form, billReference: e.target.value })} /></FormRow>
          <div className="col-span-2"><FormRow label="Description"><Textarea rows={2} value={form.description || ''} onChange={e => setForm({ ...form, description: e.target.value })} /></FormRow></div>
        </div>
      </Modal>
    </div>
  )
}

// =================================================================
// INVENTORY
// =================================================================
export function InventoryModule() {
  const { has, selectedBranchIds, branches } = useApp()
  const [search, setSearch] = useState('')
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<any>({})
  const branchesParam = selectedBranchIds.length ? `&branches=${selectedBranchIds.join(',')}` : ''
  const { data, reload } = useFetch<any>(`/api/inventory${branchesParam ? `?${branchesParam.slice(1)}` : ''}`)
  const items = (data?.items || []).filter((i: any) => !search || i.code?.toLowerCase().includes(search.toLowerCase()) || i.name?.toLowerCase().includes(search.toLowerCase()))

  return (
    <div>
      <PageHeader title="Inventory"
        action={has('inventory.add') ? () => { setForm({}); setOpen(true) } : undefined}
        actionLabel="Add Item" />
      <Toolbar>
        <SearchInput value={search} onChange={setSearch} placeholder="Search inventory…" />
        <Button variant="ghost" size="sm" onClick={reload}>Refresh</Button>
      </Toolbar>
      <DataTable
        columns={[
          { key: 'code', label: 'Code', mono: true },
          { key: 'name', label: 'Name' },
          { key: 'category', label: 'Category' },
          { key: 'quantity', label: 'Qty', align: 'right' },
          { key: 'reorderLevel', label: 'Reorder', align: 'right' },
          { key: 'salePrice', label: 'Sale Price', align: 'right', mono: true, render: (r: any) => fmtMoney(r.salePrice) },
          { key: 'branch', label: 'Branch', render: (r: any) => r.branch?.name },
          { key: 'status', label: 'Status', render: (r: any) => <StatusBadge status={r.status} /> },
        ]}
        rows={items}
      />
      <Modal open={open} onClose={() => setOpen(false)} title="Add Inventory Item"
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={async () => {
            try { await apiPost('/api/inventory', form); toast.success('Item added'); setOpen(false); reload() }
            catch (e: any) { toast.error(e.message) }
          }}><Save className="h-4 w-4 mr-1" />Save</Button>
        </>}>
        <div className="grid grid-cols-2 gap-3">
          <FormRow label="Name" required><Input value={form.name || ''} onChange={e => setForm({ ...form, name: e.target.value })} /></FormRow>
          <FormRow label="Category"><Input value={form.category || ''} onChange={e => setForm({ ...form, category: e.target.value })} /></FormRow>
          <FormRow label="Branch" required>
            <Select value={form.branchId || ''} onValueChange={v => setForm({ ...form, branchId: v })}>
              <SelectTrigger><SelectValue placeholder="Select" /></SelectTrigger>
              <SelectContent>{branches.map((b: any) => <SelectItem key={b.id} value={b.id}>{b.name}</SelectItem>)}</SelectContent>
            </Select>
          </FormRow>
          <FormRow label="Unit"><Input value={form.unit || ''} onChange={e => setForm({ ...form, unit: e.target.value })} placeholder="pcs, box, kg…" /></FormRow>
          <FormRow label="Quantity"><Input type="number" value={form.quantity || 0} onChange={e => setForm({ ...form, quantity: Number(e.target.value) })} /></FormRow>
          <FormRow label="Reorder Level"><Input type="number" value={form.reorderLevel || 0} onChange={e => setForm({ ...form, reorderLevel: Number(e.target.value) })} /></FormRow>
          <FormRow label="Purchase Price"><Input type="number" value={form.purchasePrice || 0} onChange={e => setForm({ ...form, purchasePrice: Number(e.target.value) })} /></FormRow>
          <FormRow label="Sale Price"><Input type="number" value={form.salePrice || 0} onChange={e => setForm({ ...form, salePrice: Number(e.target.value) })} /></FormRow>
          <div className="col-span-2"><FormRow label="Description"><Textarea rows={2} value={form.description || ''} onChange={e => setForm({ ...form, description: e.target.value })} /></FormRow></div>
        </div>
      </Modal>
    </div>
  )
}

// =================================================================
// POS
// =================================================================
export function PosModule() {
  const { has, selectedBranchIds, branches, session } = useApp()
  const [cart, setCart] = useState<any[]>([])
  const [method, setMethod] = useState('Cash')
  const [paymentAccountId, setPaymentAccountId] = useState('')
  const branchesParam = selectedBranchIds.length ? `&branches=${selectedBranchIds.join(',')}` : ''
  const { data: invData } = useFetch<any>(`/api/inventory${branchesParam ? `?${branchesParam.slice(1)}` : ''}`)
  const { data: cashData } = useFetch<any>('/api/accounts?bookType=Cash')
  const { data: bankData } = useFetch<any>('/api/accounts?bookType=Bank')

  const items = invData?.items || []
  const accounts = method === 'Cash' ? (cashData?.accounts || []) : method === 'Bank' ? (bankData?.accounts || []) : [...(cashData?.accounts || []), ...(bankData?.accounts || [])]
  const total = cart.reduce((s, c) => s + c.unitPrice * c.quantity, 0)

  const addToCart = (item: any) => {
    setCart(prev => {
      const ex = prev.find(c => c.inventoryItemId === item.id)
      if (ex) return prev.map(c => c.inventoryItemId === item.id ? { ...c, quantity: c.quantity + 1 } : c)
      return [...prev, { inventoryItemId: item.id, name: item.name, unitPrice: item.salePrice || 0, quantity: 1, max: item.quantity }]
    })
  }
  const setQty = (id: string, q: number) => setCart(prev => prev.map(c => c.inventoryItemId === id ? { ...c, quantity: Math.max(1, Math.min(c.max, q)) } : c))
  const remove = (id: string) => setCart(prev => prev.filter(c => c.inventoryItemId !== id))

  const checkout = async () => {
    if (cart.length === 0) { toast.error('Cart is empty'); return }
    if (!paymentAccountId && accounts.length > 0) setPaymentAccountId(accounts[0].id)
    try {
      await apiPost('/api/pos', { branchId: session?.branchId, lines: cart.map(c => ({ inventoryItemId: c.inventoryItemId, quantity: c.quantity, unitPrice: c.unitPrice })), paymentMethod: method, paymentAccountId })
      toast.success(`Sale completed · ${fmtMoney(total)}`)
      setCart([])
    } catch (e: any) { toast.error(e.message) }
  }

  return (
    <div>
      <PageHeader title="POS / Counter Sales" />
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4">
        {/* Product grid */}
        <div className="lg:col-span-2">
          <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-2">
            {items.filter(i => i.quantity > 0).map((item: any) => (
              <button key={item.id} onClick={() => addToCart(item)}
                className="border rounded p-3 text-left hover:border-primary hover:bg-muted/30 transition">
                <div className="text-sm font-medium">{item.name}</div>
                <div className="text-xs text-muted-foreground">{item.category || 'Item'}</div>
                <div className="mt-1 font-mono text-sm">{fmtMoney(item.salePrice)}</div>
                <div className="text-[10px] text-muted-foreground">Stock: {item.quantity}</div>
              </button>
            ))}
            {items.length === 0 && <div className="col-span-full text-center text-muted-foreground py-8 text-sm">No inventory items</div>}
          </div>
        </div>

        {/* Cart */}
        <Card>
          <CardContent className="p-3">
            <div className="font-medium mb-2">Cart</div>
            {cart.length === 0 ? (
              <div className="text-center text-muted-foreground py-8 text-sm">Tap products to add</div>
            ) : (
              <div className="space-y-2">
                {cart.map(c => (
                  <div key={c.inventoryItemId} className="flex items-center gap-2 text-sm">
                    <div className="flex-1">{c.name}</div>
                    <Input type="number" value={c.quantity} onChange={e => setQty(c.inventoryItemId, Number(e.target.value))} className="w-16 h-8" />
                    <div className="font-mono text-xs w-16 text-right">{fmtMoney(c.unitPrice * c.quantity)}</div>
                    <Button size="sm" variant="ghost" onClick={() => remove(c.inventoryItemId)}><X className="h-3 w-3" /></Button>
                  </div>
                ))}
              </div>
            )}
            <div className="mt-3 pt-3 border-t space-y-2">
              <FormRow label="Payment Method">
                <Select value={method} onValueChange={v => { setMethod(v); setPaymentAccountId('') }}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Cash">Cash</SelectItem>
                    <SelectItem value="Bank">Bank</SelectItem>
                    <SelectItem value="Online">Online</SelectItem>
                  </SelectContent>
                </Select>
              </FormRow>
              <FormRow label="Account">
                <Select value={paymentAccountId} onValueChange={setPaymentAccountId}>
                  <SelectTrigger><SelectValue placeholder="Auto" /></SelectTrigger>
                  <SelectContent>{accounts.map((a: any) => <SelectItem key={a.id} value={a.id}>{a.code} — {a.name}</SelectItem>)}</SelectContent>
                </Select>
              </FormRow>
              <div className="flex items-center justify-between text-sm font-medium">
                <span>Total</span><span className="font-mono text-lg">{fmtMoney(total)}</span>
              </div>
              {has('pos.add') && <Button className="w-full" onClick={checkout} disabled={cart.length === 0}>Complete Sale</Button>}
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}

// =================================================================
// STAFF
// =================================================================
export function StaffModule() {
  const { has, selectedBranchIds, branches } = useApp()
  const [search, setSearch] = useState('')
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<any>({})
  const branchesParam = selectedBranchIds.length ? `&branches=${selectedBranchIds.join(',')}` : ''
  const { data, reload } = useFetch<any>(`/api/staff${branchesParam ? `?${branchesParam.slice(1)}` : ''}`)
  const { data: shiftsData } = useFetch<any>('/api/shifts')
  const staff = (data?.staff || []).filter((s: any) => !search || s.employeeId?.toLowerCase().includes(search.toLowerCase()) || s.firstName?.toLowerCase().includes(search.toLowerCase()))

  return (
    <div>
      <PageHeader title="Staff"
        action={has('staff.add') ? () => { setForm({ isTrainer: false, overtimeAllowed: false }); setOpen(true) } : undefined}
        actionLabel="Add Staff" />
      <Toolbar>
        <SearchInput value={search} onChange={setSearch} placeholder="Search by ID or name…" />
        <Button variant="ghost" size="sm" onClick={reload}>Refresh</Button>
      </Toolbar>
      <DataTable
        columns={[
          { key: 'employeeId', label: 'ID', mono: true },
          { key: 'name', label: 'Name', render: (r: any) => `${r.firstName} ${r.lastName || ''}` },
          { key: 'designation', label: 'Designation' },
          { key: 'department', label: 'Department' },
          { key: 'branch', label: 'Branch', render: (r: any) => r.branch?.name },
          { key: 'shift', label: 'Shift', render: (r: any) => r.shift?.name || '—' },
          { key: 'isTrainer', label: 'Trainer', render: (r: any) => r.isTrainer ? <Badge>Yes</Badge> : '—' },
          { key: 'basicSalary', label: 'Salary', align: 'right', mono: true, render: (r: any) => fmtMoney(r.basicSalary) },
          { key: 'isActive', label: 'Status', render: (r: any) => <StatusBadge status={r.isActive ? 'Active' : 'Inactive'} /> },
        ]}
        rows={staff}
      />
      <Modal open={open} onClose={() => setOpen(false)} title="Add Staff" size="lg"
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={async () => {
            try { await apiPost('/api/staff', form); toast.success('Staff added'); setOpen(false); reload() }
            catch (e: any) { toast.error(e.message) }
          }}><Save className="h-4 w-4 mr-1" />Save</Button>
        </>}>
        <Tabs defaultValue="basic">
          <TabsList className="grid grid-cols-4 mb-3">
            <TabsTrigger value="basic">Basic</TabsTrigger>
            <TabsTrigger value="contact">Contact</TabsTrigger>
            <TabsTrigger value="job">Job</TabsTrigger>
            <TabsTrigger value="salary">Salary</TabsTrigger>
          </TabsList>
          <TabsContent value="basic" className="grid grid-cols-2 gap-3">
            <FormRow label="First Name" required><Input value={form.firstName || ''} onChange={e => setForm({ ...form, firstName: e.target.value })} /></FormRow>
            <FormRow label="Last Name"><Input value={form.lastName || ''} onChange={e => setForm({ ...form, lastName: e.target.value })} /></FormRow>
            <FormRow label="Father/Guardian"><Input value={form.fatherGuardian || ''} onChange={e => setForm({ ...form, fatherGuardian: e.target.value })} /></FormRow>
            <FormRow label="CNIC"><Input value={form.cnic || ''} onChange={e => setForm({ ...form, cnic: e.target.value })} /></FormRow>
            <FormRow label="Email"><Input value={form.email || ''} onChange={e => setForm({ ...form, email: e.target.value })} /></FormRow>
            <FormRow label="Phone"><Input value={form.phone || ''} onChange={e => setForm({ ...form, phone: e.target.value })} /></FormRow>
          </TabsContent>
          <TabsContent value="contact" className="grid grid-cols-2 gap-3">
            <FormRow label="WhatsApp">
            <div className="flex gap-2 items-center">
              <Input value={form.whatsapp || ''} onChange={e => setForm({ ...form, whatsapp: e.target.value })} />
              <label className="flex items-center gap-1 text-xs whitespace-nowrap cursor-pointer">
                <input type="checkbox" checked={form.sameAsPhone || false} onChange={e => {
                  if (e.target.checked) setForm({ ...form, sameAsPhone: true, whatsapp: form.phone || '' })
                  else setForm({ ...form, sameAsPhone: false })
                }} />
                Same as Phone
              </label>
            </div>
          </FormRow>
            <FormRow label="Telephone"><Input value={form.telephone || ''} onChange={e => setForm({ ...form, telephone: e.target.value })} /></FormRow>
            <FormRow label="Emergency Contact"><Input value={form.emergencyContact || ''} onChange={e => setForm({ ...form, emergencyContact: e.target.value })} /></FormRow>
            <FormRow label="Emergency #"><Input value={form.emergencyContactNo || ''} onChange={e => setForm({ ...form, emergencyContactNo: e.target.value })} /></FormRow>
            <div className="col-span-2"><FormRow label="Address"><Textarea rows={2} value={form.address || ''} onChange={e => setForm({ ...form, address: e.target.value })} /></FormRow></div>
          </TabsContent>
          <TabsContent value="job" className="grid grid-cols-2 gap-3">
            <FormRow label="Joining Date"><Input type="date" value={form.joiningDate || ''} onChange={e => setForm({ ...form, joiningDate: e.target.value })} /></FormRow>
            <FormRow label="Branch" required>
              <Select value={form.branchId || ''} onValueChange={v => setForm({ ...form, branchId: v })}>
                <SelectTrigger><SelectValue placeholder="Select" /></SelectTrigger>
                <SelectContent>{branches.map((b: any) => <SelectItem key={b.id} value={b.id}>{b.name}</SelectItem>)}</SelectContent>
              </Select>
            </FormRow>
            <FormRow label="Department"><Input value={form.department || ''} onChange={e => setForm({ ...form, department: e.target.value })} /></FormRow>
            <FormRow label="Designation"><Input value={form.designation || ''} onChange={e => setForm({ ...form, designation: e.target.value })} /></FormRow>
            <FormRow label="Shift">
              <Select value={form.shiftId || ''} onValueChange={v => setForm({ ...form, shiftId: v })}>
                <SelectTrigger><SelectValue placeholder="—" /></SelectTrigger>
                <SelectContent>{(shiftsData?.shifts || []).map((s: any) => <SelectItem key={s.id} value={s.id}>{s.name}</SelectItem>)}</SelectContent>
              </Select>
            </FormRow>
            <FormRow label="Trainer"><Switch checked={form.isTrainer || false} onCheckedChange={v => setForm({ ...form, isTrainer: v })} /></FormRow>
          </TabsContent>
          <TabsContent value="salary" className="grid grid-cols-2 gap-3">
            <FormRow label="Basic Salary"><Input type="number" value={form.basicSalary || 0} onChange={e => setForm({ ...form, basicSalary: Number(e.target.value) })} /></FormRow>
            <FormRow label="Fuel Allowance"><Input type="number" value={form.fuelAllowance || 0} onChange={e => setForm({ ...form, fuelAllowance: Number(e.target.value) })} /></FormRow>
            <FormRow label="Rent Allowance"><Input type="number" value={form.rentAllowance || 0} onChange={e => setForm({ ...form, rentAllowance: Number(e.target.value) })} /></FormRow>
            <FormRow label="House Allowance"><Input type="number" value={form.houseAllowance || 0} onChange={e => setForm({ ...form, houseAllowance: Number(e.target.value) })} /></FormRow>
            <FormRow label="SESSI"><Input type="number" value={form.sessi || 0} onChange={e => setForm({ ...form, sessi: Number(e.target.value) })} /></FormRow>
            <FormRow label="EOBI"><Input type="number" value={form.eobi || 0} onChange={e => setForm({ ...form, eobi: Number(e.target.value) })} /></FormRow>
            <FormRow label="FBR/Tax #"><Input value={form.fbrTaxNumber || ''} onChange={e => setForm({ ...form, fbrTaxNumber: e.target.value })} /></FormRow>
            <FormRow label="Overtime Allowed"><Switch checked={form.overtimeAllowed || false} onCheckedChange={v => setForm({ ...form, overtimeAllowed: v })} /></FormRow>
            <FormRow label="Overtime Rate/Hr"><Input type="number" value={form.overtimeRate || 0} onChange={e => setForm({ ...form, overtimeRate: Number(e.target.value) })} /></FormRow>
          </TabsContent>
        </Tabs>
      </Modal>
    </div>
  )
}

// =================================================================
// SHIFTS
// =================================================================
export function ShiftsModule() {
  const { has, branches } = useApp()
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<any>({})
  const { data, reload } = useFetch<any>('/api/shifts')
  const shifts = data?.shifts || []
  return (
    <div>
      <PageHeader title="Shifts"
        action={has('shifts.add') ? () => { setForm({ workingDays: 'Mon,Tue,Wed,Thu,Fri' }); setOpen(true) } : undefined}
        actionLabel="Add Shift" />
      <Toolbar><Button variant="ghost" size="sm" onClick={reload}>Refresh</Button></Toolbar>
      <DataTable
        columns={[
          { key: 'name', label: 'Name' },
          { key: 'timeIn', label: 'Time In' },
          { key: 'timeOut', label: 'Time Out' },
          { key: 'workingDays', label: 'Days' },
          { key: 'branch', label: 'Branch', render: (r: any) => r.branch?.name || '—' },
          { key: 'isActive', label: 'Status', render: (r: any) => <StatusBadge status={r.isActive ? 'Active' : 'Inactive'} /> },
        ]}
        rows={shifts}
      />
      <Modal open={open} onClose={() => setOpen(false)} title="Add Shift"
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={async () => {
            try { await apiPost('/api/shifts', form); toast.success('Shift added'); setOpen(false); reload() }
            catch (e: any) { toast.error(e.message) }
          }}><Save className="h-4 w-4 mr-1" />Save</Button>
        </>}>
        <div className="grid grid-cols-2 gap-3">
          <FormRow label="Name" required><Input value={form.name || ''} onChange={e => setForm({ ...form, name: e.target.value })} /></FormRow>
          <FormRow label="Branch">
            <Select value={form.branchId || ''} onValueChange={v => setForm({ ...form, branchId: v })}>
              <SelectTrigger><SelectValue placeholder="Any" /></SelectTrigger>
              <SelectContent>{branches.map((b: any) => <SelectItem key={b.id} value={b.id}>{b.name}</SelectItem>)}</SelectContent>
            </Select>
          </FormRow>
          <FormRow label="Time In" required><Input type="time" value={form.timeIn || ''} onChange={e => setForm({ ...form, timeIn: e.target.value })} /></FormRow>
          <FormRow label="Time Out" required><Input type="time" value={form.timeOut || ''} onChange={e => setForm({ ...form, timeOut: e.target.value })} /></FormRow>
          <div className="col-span-2"><FormRow label="Working Days (CSV)"><Input value={form.workingDays || ''} onChange={e => setForm({ ...form, workingDays: e.target.value })} placeholder="Mon,Tue,Wed,Thu,Fri" /></FormRow></div>
        </div>
      </Modal>
    </div>
  )
}

// =================================================================
// CALENDAR
// =================================================================
export function CalendarModule() {
  const { has } = useApp()
  const [year, setYear] = useState(new Date().getFullYear())
  const { data, reload } = useFetch<any>(`/api/calendar?year=${year}`)
  const days = data?.records || []
  const dayMap = new Map(days.map((d: any) => [new Date(d.date).toISOString().slice(0, 10), d]))

  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
  const generateYear = async () => {
    try { await apiPost('/api/calendar', { year }); toast.success(`Generated ${year}`); reload() }
    catch (e: any) { toast.error(e.message) }
  }
  const setDay = async (dateStr: string, dayType: string) => {
    try { await apiPost('/api/calendar', { date: dateStr, dayType }); reload() }
    catch (e: any) { toast.error(e.message) }
  }
  const dayTypeColor = (t: string) => {
    if (t === 'Sunday') return 'text-muted-foreground'
    if (t === 'PublicHoliday') return 'text-amber-600'
    if (t === 'GymClosed') return 'text-red-600'
    if (t === 'PaidHoliday') return 'text-green-600'
    return ''
  }

  return (
    <div>
      <PageHeader title="Calendar" />
      <Toolbar>
        <Input type="number" value={year} onChange={e => setYear(Number(e.target.value))} className="w-24" />
        <Button variant="outline" size="sm" onClick={generateYear}>Generate Year</Button>
        <Button variant="ghost" size="sm" onClick={reload}>Refresh</Button>
      </Toolbar>
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
        {months.map((m, mi) => {
          const firstDay = new Date(year, mi, 1)
          const lastDay = new Date(year, mi + 1, 0).getDate()
          const startDow = firstDay.getDay()
          return (
            <Card key={mi}>
              <CardContent className="p-3">
                <div className="font-medium mb-2">{m} {year}</div>
                <div className="grid grid-cols-7 gap-1 text-xs">
                  {['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((d, i) => <div key={i} className="text-center text-muted-foreground">{d}</div>)}
                  {Array.from({ length: startDow }).map((_, i) => <div key={`e${i}`} />)}
                  {Array.from({ length: lastDay }).map((_, i) => {
                    const d = i + 1
                    const date = new Date(year, mi, d)
                    const dateStr = date.toISOString().slice(0, 10)
                    const day = dayMap.get(dateStr)
                    return (
                      <button key={d}
                        title={day?.dayType || 'Working'}
                        onClick={() => {
                          const cycle = ['Working', 'Sunday', 'PublicHoliday', 'GymClosed', 'PaidHoliday']
                          const next = cycle[(cycle.indexOf(day?.dayType || 'Working') + 1) % cycle.length]
                          setDay(dateStr, next)
                        }}
                        className={`text-center py-1 rounded hover:bg-muted ${dayTypeColor(day?.dayType || (date.getDay() === 0 ? 'Sunday' : 'Working'))}`}>
                        {d}
                      </button>
                    )
                  })}
                </div>
              </CardContent>
            </Card>
          )
        })}
      </div>
    </div>
  )
}

// =================================================================
// LEAVES
// =================================================================
export function LeavesModule() {
  const { has } = useApp()
  const [status, setStatus] = useState('all')
  const [open, setOpen] = useState(false)
  const [editing, setEditing] = useState<any>(null)
  const [deleteTarget, setDeleteTarget] = useState<any>(null)
  const [form, setForm] = useState<any>({})
  const { data, reload } = useFetch<any>(`/api/leaves?status=${status !== 'all' ? status : ''}`)
  const { data: staffData } = useFetch<any>('/api/staff')
  const leaves = data?.leaves || []
  const openAdd = () => { setEditing(null); setForm({}); setOpen(true) }
  const openEdit = (r: any) => { setEditing(r); setForm({ ...r, fromDate: r.fromDate?.slice(0,10), toDate: r.toDate?.slice(0,10) }); setOpen(true) }
  const doDelete = async () => {
    if (!deleteTarget) return
    try { await apiDelete(`/api/leaves?id=${deleteTarget.id}`); toast.success('Leave deleted'); setDeleteTarget(null); reload() }
    catch (e: any) { toast.error(e.message); setDeleteTarget(null) }
  }
  return (
    <div>
      <PageHeader title="Leaves" action={has('leaves.add') ? openAdd : undefined} actionLabel="Apply Leave" />
      <Toolbar>
        <Select value={status} onValueChange={setStatus}>
          <SelectTrigger className="w-36"><SelectValue placeholder="Status" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All</SelectItem>
            <SelectItem value="Pending">Pending</SelectItem>
            <SelectItem value="Approved">Approved</SelectItem>
            <SelectItem value="Rejected">Rejected</SelectItem>
          </SelectContent>
        </Select>
        <Button variant="ghost" size="sm" onClick={reload}>Refresh</Button>
      </Toolbar>
      <DataTable
        columns={[
          { key: 'actions', label: 'Actions', sticky: true, render: (r: any) => (
            <div className="flex gap-0.5">
              {has('leaves.edit') && r.status === 'Pending' && <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); openEdit(r) }} title="Edit"><Edit className="h-3.5 w-3.5" /></Button>}
              {has('leaves.delete') && <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); setDeleteTarget(r) }} title="Delete"><Trash2 className="h-3.5 w-3.5 text-red-600" /></Button>}
              {r.status === 'Pending' && has('leaves.approve') && (
                <>
                  <Button size="sm" variant="outline" onClick={async (e) => { e.stopPropagation(); await apiPatch('/api/leaves', { id: r.id, status: 'Approved' }); toast.success('Approved'); reload() }}>Approve</Button>
                  <Button size="sm" variant="ghost" onClick={async (e) => { e.stopPropagation(); await apiPatch('/api/leaves', { id: r.id, status: 'Rejected' }); toast.success('Rejected'); reload() }}>Reject</Button>
                </>
              )}
            </div>
          ) },
          { key: 'staff', label: 'Staff', render: (r: any) => `${r.staff?.firstName} ${r.staff?.lastName || ''}` },
          { key: 'leaveType', label: 'Type' },
          { key: 'fromDate', label: 'From', render: (r: any) => fmtDateStr(r.fromDate) },
          { key: 'toDate', label: 'To', render: (r: any) => fmtDateStr(r.toDate) },
          { key: 'days', label: 'Days', align: 'right' },
          { key: 'reason', label: 'Reason' },
          { key: 'status', label: 'Status', render: (r: any) => <StatusBadge status={r.status} /> },
        ]}
        rows={leaves}
      />
      <Modal open={open} onClose={() => setOpen(false)} title={editing ? 'Edit Leave' : 'Apply Leave'}
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={async () => {
            try {
              if (editing) { await apiPatch('/api/leaves', { id: editing.id, ...form, status: 'Pending' }); toast.success('Leave updated') }
              else { await apiPost('/api/leaves', form); toast.success('Leave applied') }
              setOpen(false); reload()
            } catch (e: any) { toast.error(e.message) }
          }}><Save className="h-4 w-4 mr-1" />Save</Button>
        </>}>
        <div className="grid grid-cols-2 gap-3">
          <FormRow label="Staff" required>
            <Select value={form.staffId || ''} onValueChange={v => setForm({ ...form, staffId: v })}>
              <SelectTrigger><SelectValue placeholder="Select" /></SelectTrigger>
              <SelectContent>{(staffData?.staff || []).map((s: any) => <SelectItem key={s.id} value={s.id}>{s.employeeId} — {s.firstName} {s.lastName || ''}</SelectItem>)}</SelectContent>
            </Select>
          </FormRow>
          <FormRow label="Type">
            <Select value={form.leaveType || 'Casual'} onValueChange={v => setForm({ ...form, leaveType: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="Casual">Casual</SelectItem>
                <SelectItem value="Sick">Sick</SelectItem>
                <SelectItem value="Paid">Paid</SelectItem>
                <SelectItem value="Unpaid">Unpaid</SelectItem>
              </SelectContent>
            </Select>
          </FormRow>
          <FormRow label="From" required><Input type="date" value={form.fromDate || ''} onChange={e => setForm({ ...form, fromDate: e.target.value })} /></FormRow>
          <FormRow label="To" required><Input type="date" value={form.toDate || ''} onChange={e => setForm({ ...form, toDate: e.target.value })} /></FormRow>
          <div className="col-span-2"><FormRow label="Reason"><Textarea rows={2} value={form.reason || ''} onChange={e => setForm({ ...form, reason: e.target.value })} /></FormRow></div>
        </div>
      </Modal>
      <ConfirmModal open={!!deleteTarget} onClose={() => setDeleteTarget(null)} onConfirm={doDelete} title="Delete Leave" message={deleteTarget ? `Delete leave record?` : ''} />
    </div>
  )
}

// =================================================================
// OVERTIME
// =================================================================
export function OvertimeModule() {
  const { has } = useApp()
  const [status, setStatus] = useState('all')
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<any>({ date: new Date().toISOString().slice(0, 10) })
  const { data, reload } = useFetch<any>(`/api/overtime?status=${status !== 'all' ? status : ''}`)
  const { data: staffData } = useFetch<any>('/api/staff')
  const records = data?.records || []
  return (
    <div>
      <PageHeader title="Overtime" action={has('overtime.add') ? () => { setForm({ date: new Date().toISOString().slice(0, 10) }); setOpen(true) } : undefined} actionLabel="Log Overtime" />
      <Toolbar>
        <Select value={status} onValueChange={setStatus}>
          <SelectTrigger className="w-36"><SelectValue placeholder="Status" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All</SelectItem>
            <SelectItem value="Pending">Pending</SelectItem>
            <SelectItem value="Approved">Approved</SelectItem>
            <SelectItem value="Rejected">Rejected</SelectItem>
          </SelectContent>
        </Select>
        <Button variant="ghost" size="sm" onClick={reload}>Refresh</Button>
      </Toolbar>
      <DataTable
        columns={[
          { key: 'staff', label: 'Staff', render: (r: any) => `${r.staff?.firstName} ${r.staff?.lastName || ''}` },
          { key: 'date', label: 'Date', render: (r: any) => fmtDateStr(r.date) },
          { key: 'hours', label: 'Hours', align: 'right' },
          { key: 'rate', label: 'Rate', align: 'right', mono: true, render: (r: any) => fmtMoney(r.rate) },
          { key: 'amount', label: 'Amount', align: 'right', mono: true, render: (r: any) => fmtMoney(r.amount) },
          { key: 'notes', label: 'Notes' },
          { key: 'status', label: 'Status', render: (r: any) => <StatusBadge status={r.status} /> },
          { key: 'actions', label: '', align: 'right', render: (r: any) => r.status === 'Pending' && has('overtime.approve') && (
            <div className="flex gap-1">
              <Button size="sm" variant="outline" onClick={async (e) => { e.stopPropagation(); await apiPatch('/api/overtime', { id: r.id, status: 'Approved' }); toast.success('Approved'); reload() }}>Approve</Button>
              <Button size="sm" variant="ghost" onClick={async (e) => { e.stopPropagation(); await apiPatch('/api/overtime', { id: r.id, status: 'Rejected' }); toast.success('Rejected'); reload() }}>Reject</Button>
            </div>
          ) },
        ]}
        rows={records}
      />
      <Modal open={open} onClose={() => setOpen(false)} title="Log Overtime"
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={async () => {
            try { await apiPost('/api/overtime', form); toast.success('Overtime logged'); setOpen(false); reload() }
            catch (e: any) { toast.error(e.message) }
          }}><Save className="h-4 w-4 mr-1" />Save</Button>
        </>}>
        <div className="grid grid-cols-2 gap-3">
          <FormRow label="Staff" required>
            <Select value={form.staffId || ''} onValueChange={v => setForm({ ...form, staffId: v })}>
              <SelectTrigger><SelectValue placeholder="Select" /></SelectTrigger>
              <SelectContent>{(staffData?.staff || []).map((s: any) => <SelectItem key={s.id} value={s.id}>{s.employeeId} — {s.firstName} {s.lastName || ''}</SelectItem>)}</SelectContent>
            </Select>
          </FormRow>
          <FormRow label="Date" required><Input type="date" value={form.date || ''} onChange={e => setForm({ ...form, date: e.target.value })} /></FormRow>
          <FormRow label="Hours"><Input type="number" value={form.hours || 0} onChange={e => setForm({ ...form, hours: Number(e.target.value) })} /></FormRow>
          <FormRow label="Rate"><Input type="number" value={form.rate || 0} onChange={e => setForm({ ...form, rate: Number(e.target.value) })} /></FormRow>
          <div className="col-span-2"><FormRow label="Notes"><Textarea rows={2} value={form.notes || ''} onChange={e => setForm({ ...form, notes: e.target.value })} /></FormRow></div>
        </div>
      </Modal>
    </div>
  )
}

// =================================================================
// PAYROLL
// =================================================================
export function PayrollModule() {
  const { has } = useApp()
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<any>({ month: new Date().getMonth() + 1, year: new Date().getFullYear() })
  const { data, reload } = useFetch<any>('/api/payroll')
  const { data: staffData } = useFetch<any>('/api/staff')
  const records = data?.records || []
  return (
    <div>
      <PageHeader title="Payroll" action={has('payroll.add') ? () => setOpen(true) : undefined} actionLabel="Generate Payroll" />
      <Toolbar><Button variant="ghost" size="sm" onClick={reload}>Refresh</Button></Toolbar>
      <DataTable
        columns={[
          { key: 'payrollNo', label: 'Payroll #', mono: true },
          { key: 'staff', label: 'Staff', render: (r: any) => `${r.staff?.firstName} ${r.staff?.lastName || ''}` },
          { key: 'month', label: 'Period', render: (r: any) => `${String(r.month).padStart(2, '0')}/${r.year}` },
          { key: 'basicSalary', label: 'Basic', align: 'right', mono: true, render: (r: any) => fmtMoney(r.basicSalary) },
          { key: 'totalAllowances', label: 'Allowances', align: 'right', mono: true, render: (r: any) => fmtMoney(r.totalAllowances) },
          { key: 'overtimeAmount', label: 'Overtime', align: 'right', mono: true, render: (r: any) => fmtMoney(r.overtimeAmount) },
          { key: 'totalDeductions', label: 'Deductions', align: 'right', mono: true, render: (r: any) => fmtMoney(r.totalDeductions) },
          { key: 'netPay', label: 'Net Pay', align: 'right', mono: true, render: (r: any) => fmtMoney(r.netPay) },
          { key: 'status', label: 'Status', render: (r: any) => <StatusBadge status={r.status} /> },
          { key: 'actions', label: '', align: 'right', render: (r: any) => r.status === 'Draft' && has('payroll.edit') && (
            <Button size="sm" variant="outline" onClick={async (e) => { e.stopPropagation(); await apiPatch('/api/payroll', { id: r.id, action: 'approve' }); toast.success('Approved'); reload() }}>Approve</Button>
          ) },
        ]}
        rows={records}
      />
      <Modal open={open} onClose={() => setOpen(false)} title="Generate Payroll"
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={async () => {
            try { await apiPost('/api/payroll', form); toast.success('Payroll generated'); setOpen(false); reload() }
            catch (e: any) { toast.error(e.message) }
          }}><Save className="h-4 w-4 mr-1" />Generate</Button>
        </>}>
        <div className="grid grid-cols-2 gap-3">
          <FormRow label="Staff" required>
            <Select value={form.staffId || ''} onValueChange={v => setForm({ ...form, staffId: v })}>
              <SelectTrigger><SelectValue placeholder="Select" /></SelectTrigger>
              <SelectContent>{(staffData?.staff || []).map((s: any) => <SelectItem key={s.id} value={s.id}>{s.employeeId} — {s.firstName} {s.lastName || ''}</SelectItem>)}</SelectContent>
            </Select>
          </FormRow>
          <FormRow label="Month" required>
            <Select value={String(form.month)} onValueChange={v => setForm({ ...form, month: Number(v) })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                {['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'].map((m, i) =>
                  <SelectItem key={i + 1} value={String(i + 1)}>{m}</SelectItem>)}
              </SelectContent>
            </Select>
          </FormRow>
          <FormRow label="Year" required><Input type="number" value={form.year || new Date().getFullYear()} onChange={e => setForm({ ...form, year: Number(e.target.value) })} /></FormRow>
        </div>
        <div className="mt-3 text-xs text-muted-foreground">
          Payroll is auto-calculated from basic salary + allowances + approved overtime minus unpaid leaves and statutory deductions (SESSI, EOBI).
        </div>
      </Modal>
    </div>
  )
}

// =================================================================
// COMPANY
// =================================================================
export function CompanyModule() {
  const { has } = useApp()
  const { data, reload } = useFetch<any>('/api/company')
  const [form, setForm] = useState<any>({})
  const company = data?.company
  useEffect(() => { if (company) setForm(company) }, [company])
  return (
    <div>
      <PageHeader title="Company" action={has('company.edit') ? () => {
        apiPatch('/api/company', form).then(() => { toast.success('Company updated'); reload() }).catch((e: any) => toast.error(e.message))
      } : undefined} actionLabel="Save Changes" />
      <Card className="max-w-2xl">
        <CardContent className="p-4">
          <div className="grid grid-cols-2 gap-3">
            <FormRow label="Company ID"><Input value={company?.companyId || ''} disabled className="bg-muted/40" /></FormRow>
            <FormRow label="Accounting Type"><Input value={company?.accountingType || ''} disabled className="bg-muted/40" /></FormRow>
            <FormRow label="Name"><Input value={form.name || ''} onChange={e => setForm({ ...form, name: e.target.value })} /></FormRow>
            <FormRow label="Phone"><Input value={form.phone || ''} onChange={e => setForm({ ...form, phone: e.target.value })} /></FormRow>
            <FormRow label="Email"><Input value={form.email || ''} onChange={e => setForm({ ...form, email: e.target.value })} /></FormRow>
            <FormRow label="Website"><Input value={form.website || ''} onChange={e => setForm({ ...form, website: e.target.value })} /></FormRow>
            <FormRow label="STRN"><Input value={form.strn || ''} onChange={e => setForm({ ...form, strn: e.target.value })} /></FormRow>
            <FormRow label="NTN"><Input value={form.ntn || ''} onChange={e => setForm({ ...form, ntn: e.target.value })} /></FormRow>
            <div className="col-span-2"><FormRow label="Address"><Textarea rows={2} value={form.address || ''} onChange={e => setForm({ ...form, address: e.target.value })} /></FormRow></div>
          </div>
          <div className="mt-3 text-xs text-muted-foreground">
            Company ID and accounting type are set at initial setup and cannot be changed.
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

// =================================================================
// USERS
// =================================================================
export function UsersModule() {
  const { has } = useApp()
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<any>({})
  const { data, reload } = useFetch<any>('/api/users')
  const { data: rolesData } = useFetch<any>('/api/roles')
  const { data: branchesData } = useFetch<any>('/api/branches')
  const users = data?.users || []
  const roles = rolesData?.roles || []
  const branches = branchesData?.branches || []

  return (
    <div>
      <PageHeader title="Users"
        action={has('users.add') ? () => { setForm({ isActive: true, accessibleBranchIds: '*' }); setOpen(true) } : undefined}
        actionLabel="Add User" />
      <Toolbar><Button variant="ghost" size="sm" onClick={reload}>Refresh</Button></Toolbar>
      <DataTable
        columns={[
          { key: 'username', label: 'Username', mono: true },
          { key: 'fullName', label: 'Name' },
          { key: 'email', label: 'Email' },
          { key: 'role', label: 'Role', render: (r: any) => r.role?.name },
          { key: 'branch', label: 'Branch', render: (r: any) => r.branch?.name || '—' },
          { key: 'isActive', label: 'Status', render: (r: any) => <StatusBadge status={r.isActive ? 'Active' : 'Inactive'} /> },
        ]}
        rows={users}
      />
      <Modal open={open} onClose={() => setOpen(false)} title="Add User"
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={async () => {
            try { await apiPost('/api/users', form); toast.success('User created'); setOpen(false); reload() }
            catch (e: any) { toast.error(e.message) }
          }}><Save className="h-4 w-4 mr-1" />Save</Button>
        </>}>
        <div className="grid grid-cols-2 gap-3">
          <FormRow label="Username" required><Input value={form.username || ''} onChange={e => setForm({ ...form, username: e.target.value })} /></FormRow>
          <FormRow label="Full Name" required><Input value={form.fullName || ''} onChange={e => setForm({ ...form, fullName: e.target.value })} /></FormRow>
          <FormRow label="Email"><Input value={form.email || ''} onChange={e => setForm({ ...form, email: e.target.value })} /></FormRow>
          <FormRow label="Phone"><Input value={form.phone || ''} onChange={e => setForm({ ...form, phone: e.target.value })} /></FormRow>
          <FormRow label="Password" required><Input type="password" value={form.password || ''} onChange={e => setForm({ ...form, password: e.target.value })} /></FormRow>
          <FormRow label="Role" required>
            <Select value={form.roleId || ''} onValueChange={v => setForm({ ...form, roleId: v })}>
              <SelectTrigger><SelectValue placeholder="Select" /></SelectTrigger>
              <SelectContent>{roles.map((r: any) => <SelectItem key={r.id} value={r.id}>{r.name}</SelectItem>)}</SelectContent>
            </Select>
          </FormRow>
          <FormRow label="Primary Branch">
            <Select value={form.branchId || ''} onValueChange={v => setForm({ ...form, branchId: v })}>
              <SelectTrigger><SelectValue placeholder="—" /></SelectTrigger>
              <SelectContent>{branches.map((b: any) => <SelectItem key={b.id} value={b.id}>{b.name}</SelectItem>)}</SelectContent>
            </Select>
          </FormRow>
          <FormRow label="Accessible Branches">
            <Select value={form.accessibleBranchIds || '*'} onValueChange={v => setForm({ ...form, accessibleBranchIds: v })}>
              <SelectTrigger><SelectValue /></SelectTrigger>
              <SelectContent>
                <SelectItem value="*">All branches</SelectItem>
                {branches.map((b: any) => <SelectItem key={b.id} value={b.id}>{b.name}</SelectItem>)}
              </SelectContent>
            </Select>
          </FormRow>
        </div>
      </Modal>
    </div>
  )
}

// =================================================================
// ROLES
// =================================================================
export function RolesModule() {
  const { has, session } = useApp()
  const [selectedRole, setSelectedRole] = useState<string>('')
  const { data, reload } = useFetch<any>('/api/roles')
  const roles = data?.roles || []
  const permissions = data?.permissions || []
  const current = roles.find((r: any) => r.id === selectedRole) || roles[0]
  const currentPerms = new Set(current?.permissions?.map((p: any) => p.permission.code) || [])

  const groupedPerms = permissions.reduce((acc: any, p: any) => {
    if (!acc[p.module]) acc[p.module] = []
    acc[p.module].push(p)
    return acc
  }, {})

  const togglePerm = async (code: string) => {
    if (!current) return
    const next = currentPerms.has(code) ? Array.from(currentPerms).filter(c => c !== code) : [...Array.from(currentPerms), code]
    try {
      await apiPatch(`/api/roles/${current.id}`, { action: 'permissions', permissionCodes: next })
      toast.success('Permissions updated')
      reload()
    } catch (e: any) { toast.error(e.message) }
  }

  return (
    <div>
      <PageHeader title="Roles & Permissions" />
      <Toolbar>
        <Select value={selectedRole || current?.id || ''} onValueChange={setSelectedRole}>
          <SelectTrigger className="w-64"><SelectValue placeholder="Select role" /></SelectTrigger>
          <SelectContent>{roles.map((r: any) => <SelectItem key={r.id} value={r.id}>{r.name}{r.isSystem ? ' (system)' : ''}</SelectItem>)}</SelectContent>
        </Select>
      </Toolbar>
      {current && (
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-3">
          {Object.entries(groupedPerms).map(([mod, perms]: any) => (
            <Card key={mod}>
              <CardContent className="p-3">
                <div className="font-medium mb-2 capitalize">{mod}</div>
                <div className="space-y-1">
                  {(perms as any[]).map((p: any) => (
                    <label key={p.code} className="flex items-center gap-2 text-sm cursor-pointer">
                      <Checkbox
                        checked={currentPerms.has(p.code)}
                        onCheckedChange={() => togglePerm(p.code)}
                        disabled={current.isSystem && !session?.isSuperAdmin}
                      />
                      <span className="font-mono text-xs">{p.action}</span>
                      {p.description && <span className="text-xs text-muted-foreground">— {p.description}</span>}
                    </label>
                  ))}
                </div>
              </CardContent>
            </Card>
          ))}
        </div>
      )}
    </div>
  )
}

// =================================================================
// AUDIT
// =================================================================
export function AuditModule() {
  const [module, setModule] = useState('all')
  const [action, setAction] = useState('all')
  const { data, reload } = useFetch<any>(`/api/audit?module=${module !== 'all' ? module : ''}&action=${action !== 'all' ? action : ''}`)
  const logs = data?.logs || []
  return (
    <div>
      <PageHeader title="Audit Log" />
      <Toolbar>
        <Select value={module} onValueChange={setModule}>
          <SelectTrigger className="w-40"><SelectValue placeholder="Module" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All modules</SelectItem>
            {['auth', 'members', 'fees', 'finance', 'vouchers', 'cheques', 'tax', 'prospects', 'staff', 'payroll', 'branches', 'users', 'roles', 'company', 'coa', 'equipment', 'accountMappings'].map(m => <SelectItem key={m} value={m}>{m}</SelectItem>)}
          </SelectContent>
        </Select>
        <Select value={action} onValueChange={setAction}>
          <SelectTrigger className="w-32"><SelectValue placeholder="Action" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All</SelectItem>
            {['CREATE', 'UPDATE', 'DELETE', 'POST', 'REVERSE', 'STATUS', 'APPROVE', 'REJECT', 'LOGIN', 'LOGOUT', 'LOGIN_FAILED', 'CONVERT'].map(a => <SelectItem key={a} value={a}>{a}</SelectItem>)}
          </SelectContent>
        </Select>
        <Button variant="ghost" size="sm" onClick={reload}>Refresh</Button>
      </Toolbar>
      <DataTable
        columns={[
          { key: 'createdAt', label: 'When', render: (r: any) => fmtDateTime(r.createdAt) },
          { key: 'user', label: 'User', render: (r: any) => r.user?.fullName || '—' },
          { key: 'action', label: 'Action' },
          { key: 'module', label: 'Module' },
          { key: 'ipAddress', label: 'IP' },
          { key: 'details', label: 'Details', render: (r: any) => r.details ? <code className="text-xs">{r.details.length > 60 ? r.details.slice(0, 60) + '…' : r.details}</code> : '—' },
        ]}
        rows={logs}
      />
    </div>
  )
}

// =================================================================
// ACCOUNT MAPPINGS
// =================================================================
export function AccountMappingsModule() {
  const { has, branches, session } = useApp()
  const [branchId, setBranchId] = useState<string>('')
  const { data, reload } = useFetch<any>(`/api/account-mappings${branchId ? `?branchId=${branchId}` : ''}`)
  const { data: accountsData } = useFetch<any>('/api/accounts')
  const mappings = data?.mappings || []
  const accounts = accountsData?.accounts || []

  const KEYS = [
    { key: 'cashAccount', label: 'Cash Account' },
    { key: 'bankAccount', label: 'Bank Account' },
    { key: 'feeIncome', label: 'Membership Fee Income' },
    { key: 'feeReceivable', label: 'Fee Receivable' },
    { key: 'posIncome', label: 'POS Sales Income' },
    { key: 'posCash', label: 'POS Cash' },
    { key: 'posBank', label: 'POS Bank' },
    { key: 'taxAccount', label: 'Sales Tax Payable' },
    { key: 'feeDiscount', label: 'Fee Discount' },
  ]

  const save = async (key: string, accountId: string) => {
    try {
      await apiPost('/api/account-mappings', { key, accountId, branchId: branchId || null })
      toast.success('Mapping saved'); reload()
    } catch (e: any) { toast.error(e.message) }
  }

  return (
    <div>
      <PageHeader title="Account Mappings" />
      <Toolbar>
        <FormRow label="Branch (blank = global default)">
          <Select value={branchId} onValueChange={setBranchId}>
            <SelectTrigger className="w-64"><SelectValue placeholder="Global default" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="">Global default</SelectItem>
              {branches.map((b: any) => <SelectItem key={b.id} value={b.id}>{b.name}</SelectItem>)}
            </SelectContent>
          </Select>
        </FormRow>
        <Button variant="ghost" size="sm" onClick={reload}>Refresh</Button>
      </Toolbar>
      <Card>
        <CardContent className="p-3">
          <div className="space-y-2">
            {KEYS.map(({ key, label }) => {
              const m = mappings.find((mp: any) => mp.key === key && ((mp.branchId || null) === (branchId || null)))
              return (
                <div key={key} className="grid grid-cols-1 sm:grid-cols-3 gap-2 items-center py-2 border-b last:border-0">
                  <div>
                    <div className="font-medium text-sm">{label}</div>
                    <div className="text-xs text-muted-foreground font-mono">{key}</div>
                  </div>
                  <Select value={m?.accountId || ''} onValueChange={(v) => save(key, v)}>
                    <SelectTrigger><SelectValue placeholder="Select account" /></SelectTrigger>
                    <SelectContent>{accounts.map((a: any) => <SelectItem key={a.id} value={a.id}>{a.code} — {a.name}</SelectItem>)}</SelectContent>
                  </Select>
                  <div className="text-xs text-muted-foreground">{m?.account ? `${m.account.code} — ${m.account.name}` : 'Not configured'}</div>
                </div>
              )
            })}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

// =================================================================
// FINANCE REPORTS
// =================================================================
export function FinanceReportsModule() {
  const [reportKey, setReportKey] = useState('')
  const [filters, setFilters] = useState<any>({ from: '', to: '', asOf: '' })
  const [reportData, setReportData] = useState<any>(null)
  const [loading, setLoading] = useState(false)

  const REPORTS = [
    { key: 'trial-balance', name: 'Trial Balance', filters: ['from', 'to'] },
    { key: 'general-ledger', name: 'General Ledger', filters: ['from', 'to'] },
    { key: 'account-ledger', name: 'Account Ledger', filters: ['from', 'to', 'accountId'] },
    { key: 'income-statement', name: 'Income Statement', filters: ['from', 'to'] },
    { key: 'balance-sheet', name: 'Balance Sheet', filters: ['asOf'] },
    { key: 'cash-book', name: 'Cash Book', filters: ['from', 'to'] },
    { key: 'bank-book', name: 'Bank Book', filters: ['from', 'to'] },
    { key: 'voucher-register', name: 'Voucher Register', filters: ['from', 'to'] },
    { key: 'tax-report', name: 'Tax Report', filters: ['from', 'to'] },
  ]

  const run = async () => {
    setLoading(true)
    try {
      const params = new URLSearchParams({ report: reportKey })
      Object.entries(filters).forEach(([k, v]) => { if (v) params.set(k, String(v)) })
      const res = await fetch(`/api/finance-reports?${params}`)
      const json = await res.json()
      if (!res.ok) throw new Error(json.error)
      setReportData(json.report)
    } catch (e: any) { toast.error(e.message); setReportData(null) }
    finally { setLoading(false) }
  }

  const { data: accountsData } = useFetch<any>('/api/accounts')

  return (
    <div>
      <PageHeader title="Finance Reports" />
      <Card>
        <CardContent className="p-4">
          <div className="grid grid-cols-1 sm:grid-cols-4 gap-3">
            <FormRow label="Report" required>
              <Select value={reportKey} onValueChange={v => { setReportKey(v); setReportData(null) }}>
                <SelectTrigger><SelectValue placeholder="Select report" /></SelectTrigger>
                <SelectContent>{REPORTS.map(r => <SelectItem key={r.key} value={r.key}>{r.name}</SelectItem>)}</SelectContent>
              </Select>
            </FormRow>
            {reportKey && REPORTS.find(r => r.key === reportKey)?.filters.includes('from') && (
              <FormRow label="From"><Input type="date" value={filters.from} onChange={e => setFilters({ ...filters, from: e.target.value })} /></FormRow>
            )}
            {reportKey && REPORTS.find(r => r.key === reportKey)?.filters.includes('to') && (
              <FormRow label="To"><Input type="date" value={filters.to} onChange={e => setFilters({ ...filters, to: e.target.value })} /></FormRow>
            )}
            {reportKey && REPORTS.find(r => r.key === reportKey)?.filters.includes('asOf') && (
              <FormRow label="As of"><Input type="date" value={filters.asOf} onChange={e => setFilters({ ...filters, asOf: e.target.value })} /></FormRow>
            )}
            {reportKey && REPORTS.find(r => r.key === reportKey)?.filters.includes('accountId') && (
              <FormRow label="Account">
                <Select value={filters.accountId || ''} onValueChange={v => setFilters({ ...filters, accountId: v })}>
                  <SelectTrigger><SelectValue placeholder="All" /></SelectTrigger>
                  <SelectContent>{(accountsData?.accounts || []).map((a: any) => <SelectItem key={a.id} value={a.id}>{a.code} — {a.name}</SelectItem>)}</SelectContent>
                </Select>
              </FormRow>
            )}
            <div className="flex items-end">
              <Button onClick={run} disabled={!reportKey || loading}>{loading ? 'Generating…' : 'Get Report'}</Button>
            </div>
          </div>
        </CardContent>
      </Card>

      {reportData && <ReportRenderer report={reportData} />}
    </div>
  )
}

function ReportRenderer({ report }: any) {
  if (report.title === 'Trial Balance') {
    return (
      <Card className="mt-4"><CardContent className="p-0">
        <div className="px-4 py-2 border-b font-medium">{report.title} — {fmtDateStr(report.from)} to {fmtDateStr(report.to)}</div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-muted/40 border-b"><tr><th className="text-left px-3 py-2">Code</th><th className="text-left px-3 py-2">Account</th><th className="text-right px-3 py-2">Debit</th><th className="text-right px-3 py-2">Credit</th></tr></thead>
            <tbody>
              {report.rows.map((r: any, i: number) => (
                <tr key={i} className="border-b last:border-0"><td className="px-3 py-2 font-mono text-xs">{r.code}</td><td className="px-3 py-2">{r.name}</td><td className="px-3 py-2 text-right font-mono">{fmtMoney(r.debit)}</td><td className="px-3 py-2 text-right font-mono">{fmtMoney(r.credit)}</td></tr>
              ))}
            </tbody>
            <tfoot className="bg-muted/30 font-medium border-t"><tr><td colSpan={2} className="px-3 py-2 text-right">Total</td><td className="px-3 py-2 text-right font-mono">{fmtMoney(report.totalDebit)}</td><td className="px-3 py-2 text-right font-mono">{fmtMoney(report.totalCredit)}</td></tr></tfoot>
          </table>
        </div>
        <div className={`px-4 py-2 text-sm ${report.balanced ? 'text-green-600' : 'text-red-600'}`}>{report.balanced ? '✓ Balanced' : '✗ Not balanced'}</div>
      </CardContent></Card>
    )
  }
  if (report.title === 'Income Statement') {
    return (
      <Card className="mt-4"><CardContent className="p-0">
        <div className="px-4 py-2 border-b font-medium">{report.title} — {fmtDateStr(report.from)} to {fmtDateStr(report.to)}</div>
        <div className="p-4 space-y-4">
          <div><div className="font-medium mb-1">Revenue</div>
            <table className="w-full text-sm"><tbody>
              {report.revenues.map((r: any, i: number) => <tr key={i} className="border-b"><td className="px-3 py-1.5 font-mono text-xs">{r.code}</td><td className="px-3 py-1.5">{r.name}</td><td className="px-3 py-1.5 text-right font-mono">{fmtMoney(r.amount)}</td></tr>)}
            </tbody><tfoot className="font-medium"><tr><td colSpan={2} className="px-3 py-2 text-right">Total Revenue</td><td className="px-3 py-2 text-right font-mono">{fmtMoney(report.totalRevenue)}</td></tr></tfoot></table>
          </div>
          <div><div className="font-medium mb-1">Expenses</div>
            <table className="w-full text-sm"><tbody>
              {report.expenses.map((r: any, i: number) => <tr key={i} className="border-b"><td className="px-3 py-1.5 font-mono text-xs">{r.code}</td><td className="px-3 py-1.5">{r.name}</td><td className="px-3 py-1.5 text-right font-mono">{fmtMoney(r.amount)}</td></tr>)}
            </tbody><tfoot className="font-medium"><tr><td colSpan={2} className="px-3 py-2 text-right">Total Expense</td><td className="px-3 py-2 text-right font-mono">{fmtMoney(report.totalExpense)}</td></tr></tfoot></table>
          </div>
          <div className={`text-right font-medium ${report.netProfit >= 0 ? 'text-green-600' : 'text-red-600'}`}>Net {report.netProfit >= 0 ? 'Profit' : 'Loss'}: {fmtMoney(report.netProfit)}</div>
        </div>
      </CardContent></Card>
    )
  }
  if (report.title === 'Balance Sheet') {
    return (
      <Card className="mt-4"><CardContent className="p-0">
        <div className="px-4 py-2 border-b font-medium">{report.title} as at {fmtDateStr(report.asOf)}</div>
        <div className="p-4 grid grid-cols-1 sm:grid-cols-3 gap-4">
          {['assets', 'liabilities', 'equity'].map((k) => (
            <div key={k}>
              <div className="font-medium mb-1 capitalize">{k}</div>
              <table className="w-full text-sm"><tbody>
                {report.rows[k].map((r: any, i: number) => <tr key={i} className="border-b"><td className="px-2 py-1.5 font-mono text-xs">{r.code}</td><td className="px-2 py-1.5">{r.name}</td><td className="px-2 py-1.5 text-right font-mono">{fmtMoney(r.amount)}</td></tr>)}
              </tbody></table>
              <div className="text-right font-medium text-xs pt-1">Total: {fmtMoney(k === 'assets' ? report.totalAssets : k === 'liabilities' ? report.totalLiabilities : report.totalEquity)}</div>
            </div>
          ))}
        </div>
        <div className={`px-4 py-2 text-sm ${report.balanced ? 'text-green-600' : 'text-red-600'}`}>Assets = Liabilities + Equity: {report.balanced ? '✓ Balanced' : '✗ Not balanced'}</div>
      </CardContent></Card>
    )
  }
  if (report.title === 'Voucher Register') {
    return (
      <Card className="mt-4"><CardContent className="p-0">
        <div className="px-4 py-2 border-b font-medium">{report.title} — {fmtDateStr(report.from)} to {fmtDateStr(report.to)}</div>
        <DataTable columns={[
          { key: 'voucherNo', label: 'Voucher #', mono: true },
          { key: 'voucherType', label: 'Type' },
          { key: 'voucherDate', label: 'Date', render: (r: any) => fmtDateStr(r.voucherDate) },
          { key: 'branch', label: 'Branch', render: (r: any) => r.branch?.name },
          { key: 'description', label: 'Description' },
          { key: 'totalDebit', label: 'Debit', align: 'right', mono: true, render: (r: any) => fmtMoney(r.totalDebit) },
          { key: 'status', label: 'Status', render: (r: any) => <StatusBadge status={r.status} /> },
        ]} rows={report.vouchers} empty="No vouchers in period" />
      </CardContent></Card>
    )
  }
  if (report.accounts) {
    return (
      <div className="mt-4 space-y-4">
        {report.accounts.map((a: any, i: number) => (
          <Card key={i}><CardContent className="p-0">
            <div className="px-4 py-2 border-b font-medium">{a.account.code} — {a.account.name} · Opening: {fmtMoney(a.openingBalance)} · Closing: {fmtMoney(a.closingBalance)}</div>
            <DataTable columns={[
              { key: 'date', label: 'Date', render: (r: any) => fmtDateStr(r.date) },
              { key: 'voucherNo', label: 'Voucher', mono: true },
              { key: 'type', label: 'Type' },
              { key: 'description', label: 'Description' },
              { key: 'debit', label: 'Debit', align: 'right', mono: true, render: (r: any) => fmtMoney(r.debit) },
              { key: 'credit', label: 'Credit', align: 'right', mono: true, render: (r: any) => fmtMoney(r.credit) },
              { key: 'balance', label: 'Balance', align: 'right', mono: true, render: (r: any) => fmtMoney(r.balance) },
            ]} rows={a.rows} empty="No transactions" />
          </CardContent></Card>
        ))}
      </div>
    )
  }
  return <div className="mt-4 text-muted-foreground text-sm">Report generated. Format not yet implemented for {report.title}.</div>
}

// =================================================================
// FINANCE DEFAULTS (stub for now)
// =================================================================
export function FinanceDefaultsModule() {
  return (
    <div>
      <PageHeader title="Finance Defaults" />
      <Card><CardContent className="p-4">
        <div className="text-sm text-muted-foreground">Configure default cash account, bank account, tax head, and active financial year per branch. Mappings drive automatic voucher posting from fees and POS.</div>
        <div className="mt-3"><Button size="sm" variant="outline" onClick={() => toast.info('Use Account Mappings page to configure fee/POS accounts.')}>Go to Account Mappings</Button></div>
      </CardContent></Card>
    </div>
  )
}

// =================================================================
// PERIODS
// =================================================================
export function PeriodsModule() {
  return (
    <div>
      <PageHeader title="Accounting Periods" />
      <Card><CardContent className="p-4">
        <div className="text-sm text-muted-foreground">The seed created FY-2025 with 12 monthly periods (Jan–Dec). Period status (Open/Closed/Locked) can be edited here in a future iteration. Posted vouchers respect period status.</div>
      </CardContent></Card>
    </div>
  )
}

// =================================================================
// EXERCISES
// =================================================================
export function ExercisesModule() {
  const { has } = useApp()
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<any>({})
  const { data, reload } = useFetch<any>('/api/exercises')
  const exercises = data?.exercises || []
  return (
    <div>
      <PageHeader title="Exercises"
        action={has('workouts.add') ? () => { setForm({}); setOpen(true) } : undefined}
        actionLabel="Add Exercise" />
      <Toolbar><Button variant="ghost" size="sm" onClick={reload}>Refresh</Button></Toolbar>
      <DataTable
        columns={[
          { key: 'code', label: 'Code', mono: true },
          { key: 'name', label: 'Name' },
          { key: 'category', label: 'Category' },
          { key: 'muscleGroup', label: 'Muscle Group' },
          { key: 'sets', label: 'Sets', align: 'right' },
          { key: 'reps', label: 'Reps' },
          { key: 'status', label: 'Status', render: (r: any) => <StatusBadge status={r.status} /> },
        ]}
        rows={exercises}
      />
      <Modal open={open} onClose={() => setOpen(false)} title="Add Exercise"
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={async () => {
            try { await apiPost('/api/exercises', form); toast.success('Exercise added'); setOpen(false); reload() }
            catch (e: any) { toast.error(e.message) }
          }}><Save className="h-4 w-4 mr-1" />Save</Button>
        </>}>
        <div className="grid grid-cols-2 gap-3">
          <FormRow label="Name" required><Input value={form.name || ''} onChange={e => setForm({ ...form, name: e.target.value })} /></FormRow>
          <FormRow label="Category"><Input value={form.category || ''} onChange={e => setForm({ ...form, category: e.target.value })} placeholder="Chest, Back, Legs…" /></FormRow>
          <FormRow label="Muscle Group"><Input value={form.muscleGroup || ''} onChange={e => setForm({ ...form, muscleGroup: e.target.value })} /></FormRow>
          <FormRow label="Equipment"><Input value={form.equipment || ''} onChange={e => setForm({ ...form, equipment: e.target.value })} /></FormRow>
          <FormRow label="Sets"><Input type="number" value={form.sets || ''} onChange={e => setForm({ ...form, sets: e.target.value })} /></FormRow>
          <FormRow label="Reps"><Input value={form.reps || ''} onChange={e => setForm({ ...form, reps: e.target.value })} placeholder="8-12" /></FormRow>
          <FormRow label="Duration"><Input value={form.duration || ''} onChange={e => setForm({ ...form, duration: e.target.value })} placeholder="30 sec" /></FormRow>
          <FormRow label="Rest"><Input value={form.rest || ''} onChange={e => setForm({ ...form, rest: e.target.value })} placeholder="60 sec" /></FormRow>
          <div className="col-span-2"><FormRow label="Instructions"><Textarea rows={2} value={form.instructions || ''} onChange={e => setForm({ ...form, instructions: e.target.value })} /></FormRow></div>
        </div>
      </Modal>
    </div>
  )
}

// =================================================================
// WORKOUTS / DIET / PROGRESS stubs (kept simple for now)
// =================================================================
export function WorkoutsModule() {
  const { has } = useApp()
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<any>({ name: '', description: '', days: [{ dayName: 'Monday', exercises: [] }] })
  const { data, reload } = useFetch<any>('/api/workouts')
  const plans = data?.plans || []
  return (
    <div>
      <PageHeader title="Workout Plans"
        action={has('workouts.add') ? () => setOpen(true) : undefined}
        actionLabel="Add Plan" />
      <Toolbar><Button variant="ghost" size="sm" onClick={reload}>Refresh</Button></Toolbar>
      <DataTable
        columns={[
          { key: 'name', label: 'Name' },
          { key: 'description', label: 'Description' },
          { key: 'days', label: 'Days', align: 'right', render: (r: any) => r.days?.length || 0 },
          { key: 'isActive', label: 'Status', render: (r: any) => <StatusBadge status={r.isActive ? 'Active' : 'Inactive'} /> },
        ]}
        rows={plans}
      />
      <Modal open={open} onClose={() => setOpen(false)} title="Add Workout Plan"
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={async () => {
            try { await apiPost('/api/workouts', form); toast.success('Plan created'); setOpen(false); reload() }
            catch (e: any) { toast.error(e.message) }
          }}><Save className="h-4 w-4 mr-1" />Save</Button>
        </>}>
        <FormRow label="Name" required><Input value={form.name || ''} onChange={e => setForm({ ...form, name: e.target.value })} /></FormRow>
        <div className="mt-3"><FormRow label="Description"><Textarea rows={2} value={form.description || ''} onChange={e => setForm({ ...form, description: e.target.value })} /></FormRow></div>
        <div className="mt-3 text-xs text-muted-foreground">Multi-day plan with exercises per day. Detailed day/exercise editor available in next iteration — current submission creates the plan name.</div>
      </Modal>
    </div>
  )
}

export function DietModule() {
  const { has } = useApp()
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<any>({ name: '', description: '', meals: [] })
  const { data, reload } = useFetch<any>('/api/diet')
  const plans = data?.plans || []
  return (
    <div>
      <PageHeader title="Diet Plans"
        action={has('diet.add') ? () => setOpen(true) : undefined}
        actionLabel="Add Plan" />
      <Toolbar><Button variant="ghost" size="sm" onClick={reload}>Refresh</Button></Toolbar>
      <DataTable
        columns={[
          { key: 'name', label: 'Name' },
          { key: 'description', label: 'Description' },
          { key: 'meals', label: 'Meals', align: 'right', render: (r: any) => r.meals?.length || 0 },
          { key: 'isActive', label: 'Status', render: (r: any) => <StatusBadge status={r.isActive ? 'Active' : 'Inactive'} /> },
        ]}
        rows={plans}
      />
      <Modal open={open} onClose={() => setOpen(false)} title="Add Diet Plan"
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={async () => {
            try { await apiPost('/api/diet', form); toast.success('Plan created'); setOpen(false); reload() }
            catch (e: any) { toast.error(e.message) }
          }}><Save className="h-4 w-4 mr-1" />Save</Button>
        </>}>
        <FormRow label="Name" required><Input value={form.name || ''} onChange={e => setForm({ ...form, name: e.target.value })} /></FormRow>
        <div className="mt-3"><FormRow label="Description"><Textarea rows={2} value={form.description || ''} onChange={e => setForm({ ...form, description: e.target.value })} /></FormRow></div>
      </Modal>
    </div>
  )
}

export function ProgressModule() {
  const { has } = useApp()
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<any>({ date: new Date().toISOString().slice(0, 10) })
  const { data: membersData } = useFetch<any>('/api/members')
  const { data, reload } = useFetch<any>('/api/progress')
  const records = data?.records || []
  return (
    <div>
      <PageHeader title="Progress Tracking"
        action={has('progress.add') ? () => setOpen(true) : undefined}
        actionLabel="Log Progress" />
      <Toolbar><Button variant="ghost" size="sm" onClick={reload}>Refresh</Button></Toolbar>
      <DataTable
        columns={[
          { key: 'date', label: 'Date', render: (r: any) => fmtDateStr(r.date) },
          { key: 'memberId', label: 'Member ID', mono: true },
          { key: 'weight', label: 'Weight', align: 'right' },
          { key: 'chest', label: 'Chest', align: 'right' },
          { key: 'waist', label: 'Waist', align: 'right' },
          { key: 'hips', label: 'Hips', align: 'right' },
          { key: 'biceps', label: 'Biceps', align: 'right' },
          { key: 'notes', label: 'Notes' },
        ]}
        rows={records}
      />
      <Modal open={open} onClose={() => setOpen(false)} title="Log Progress"
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={async () => {
            try { await apiPost('/api/progress', form); toast.success('Progress logged'); setOpen(false); reload() }
            catch (e: any) { toast.error(e.message) }
          }}><Save className="h-4 w-4 mr-1" />Save</Button>
        </>}>
        <div className="grid grid-cols-2 gap-3">
          <FormRow label="Member" required>
            <Select value={form.memberId || ''} onValueChange={v => setForm({ ...form, memberId: v })}>
              <SelectTrigger><SelectValue placeholder="Select" /></SelectTrigger>
              <SelectContent>{(membersData?.members || []).map((m: any) => <SelectItem key={m.id} value={m.id}>{m.memberId} — {m.firstName} {m.lastName || ''}</SelectItem>)}</SelectContent>
            </Select>
          </FormRow>
          <FormRow label="Date"><Input type="date" value={form.date || ''} onChange={e => setForm({ ...form, date: e.target.value })} /></FormRow>
          <FormRow label="Weight (kg)"><Input type="number" value={form.weight || ''} onChange={e => setForm({ ...form, weight: e.target.value })} /></FormRow>
          <FormRow label="Chest"><Input type="number" value={form.chest || ''} onChange={e => setForm({ ...form, chest: e.target.value })} /></FormRow>
          <FormRow label="Waist"><Input type="number" value={form.waist || ''} onChange={e => setForm({ ...form, waist: e.target.value })} /></FormRow>
          <FormRow label="Hips"><Input type="number" value={form.hips || ''} onChange={e => setForm({ ...form, hips: e.target.value })} /></FormRow>
          <FormRow label="Biceps"><Input type="number" value={form.biceps || ''} onChange={e => setForm({ ...form, biceps: e.target.value })} /></FormRow>
          <FormRow label="Thighs"><Input type="number" value={form.thighs || ''} onChange={e => setForm({ ...form, thighs: e.target.value })} /></FormRow>
          <div className="col-span-2"><FormRow label="Notes"><Textarea rows={2} value={form.notes || ''} onChange={e => setForm({ ...form, notes: e.target.value })} /></FormRow></div>
        </div>
      </Modal>
    </div>
  )
}
