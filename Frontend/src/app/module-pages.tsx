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
  const [bookType, setBookType] = useState('all')
  const [status, setStatus] = useState('all')
  const [expanded, setExpanded] = useState<Set<string>>(new Set())
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<any>({})
  const [editingAccount, setEditingAccount] = useState<any>(null)
  const [deleteTarget, setDeleteTarget] = useState<any>(null)
  const { data, reload } = useFetch<any>(`/api/accounts?accountType=${type !== 'all' ? type : ''}&bookType=${bookType !== 'all' ? bookType : ''}`)

  const accounts = data?.accounts || []
  const roots = accounts.filter(a => !a.parentId)
  const matches = (a: any) => {
    if (!search) return true
    const q = search.toLowerCase()
    if (a.name.toLowerCase().includes(q) || a.code.includes(q)) return true
    // also match if any descendant matches
    const hasMatchingDescendant = (id: string): boolean => {
      return accounts.some((c: any) => c.parentId === id && (c.name.toLowerCase().includes(q) || c.code.includes(q) || hasMatchingDescendant(c.id)))
    }
    return hasMatchingDescendant(a.id)
  }
  const isVisible = (a: any) => {
    if (status === 'all') return matches(a)
    if (status === 'active') return a.isActive && matches(a)
    if (status === 'inactive') return !a.isActive && matches(a)
    return matches(a)
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

  const openAdd = (parentId?: string, accountType?: string) => {
    setEditingAccount(null)
    setForm(parentId ? { parentId, accountType: accountType || 'Asset' } : { accountType: 'Asset' })
    setOpen(true)
  }
  const openEdit = (a: any) => {
    setEditingAccount(a)
    setForm({ ...a })
    setOpen(true)
  }
  const confirmDelete = async () => {
    if (!deleteTarget) return
    try {
      const res = await fetch(`/api/accounts/${deleteTarget.id}`, { method: 'DELETE' })
      const json = await res.json()
      if (!res.ok) throw new Error(json.error || 'Failed')
      if (json.softDeleted) toast.success('Account deactivated (has posted transactions)')
      else toast.success('Account deleted')
      setDeleteTarget(null)
      reload()
    } catch (e: any) { toast.error(e.message) }
  }

  const renderNode = (a: any, depth = 0): ReactNode => {
    const children = accounts.filter((c: any) => c.parentId === a.id)
    const isExpanded = expanded.has(a.id)
    if (!isVisible(a)) return null
    return (
      <div key={a.id}>
        <div
          className={`flex items-center gap-2 px-2 py-1.5 hover:bg-muted/40 ${!a.isActive ? 'opacity-50' : ''}`}
          style={{ paddingLeft: `${depth * 20 + 8}px` }}
        >
          {/* Actions on LEFT */}
          <div className="flex items-center gap-0.5 mr-1">
            {has('finance.coa') && (
              <button onClick={(e) => { e.stopPropagation(); openEdit(a) }} title="Edit" className="p-1 rounded hover:bg-muted text-foreground/70">
                <Edit className="h-3 w-3" />
              </button>
            )}
            {has('finance.coa') && (
              <button onClick={(e) => { e.stopPropagation(); openAdd(a.id, a.accountType) }} title="Add child" className="p-1 rounded hover:bg-muted text-primary">
                <Plus className="h-3 w-3" />
              </button>
            )}
            {has('finance.coa') && (
              <button onClick={(e) => { e.stopPropagation(); setDeleteTarget(a) }} title="Delete / Deactivate" className="p-1 rounded hover:bg-muted text-red-600">
                <Trash2 className="h-3 w-3" />
              </button>
            )}
          </div>
          {/* expand/collapse toggle */}
          <button onClick={() => children.length ? toggle(a.id) : null} className="flex items-center gap-2 flex-1 text-left">
            {children.length ? (
              isExpanded ? <ChevronDown className="h-3 w-3 shrink-0" /> : <ChevronRight className="h-3 w-3 shrink-0" />
            ) : <div className="w-3" />}
            <span className="font-mono text-xs text-muted-foreground w-20">{a.code}</span>
            <span className="flex-1 text-sm">{a.name}</span>
          </button>
          <Badge variant="outline" className="text-xs">{a.accountType}</Badge>
          {a.bookType && <Badge variant="secondary" className="text-xs">{a.bookType}</Badge>}
          {a.isControl && <Badge className="text-xs">Control</Badge>}
          {a.accountTag && <Badge variant="secondary" className="text-xs">{a.accountTag}</Badge>}
          {!a.isActive && <Badge variant="destructive" className="text-xs">Inactive</Badge>}
        </div>
        {isExpanded && children.map((c: any) => renderNode(c, depth + 1))}
      </div>
    )
  }

  return (
    <div>
      <PageHeader title="Chart of Accounts"
        action={has('finance.coa') ? () => openAdd() : undefined}
        actionLabel="Add Account" />
      <Toolbar>
        <SearchInput value={search} onChange={setSearch} placeholder="Search by name or code…" />
        <Select value={type} onValueChange={setType}>
          <SelectTrigger className="w-36"><SelectValue placeholder="Type" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All types</SelectItem>
            <SelectItem value="Asset">Asset</SelectItem>
            <SelectItem value="Liability">Liability</SelectItem>
            <SelectItem value="Equity">Capital / Equity</SelectItem>
            <SelectItem value="Revenue">Revenue</SelectItem>
            <SelectItem value="Expense">Expense</SelectItem>
          </SelectContent>
        </Select>
        <Select value={bookType} onValueChange={setBookType}>
          <SelectTrigger className="w-36"><SelectValue placeholder="Book Type" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All book types</SelectItem>
            <SelectItem value="Cash">Cash</SelectItem>
            <SelectItem value="Bank">Bank</SelectItem>
            <SelectItem value="General">General</SelectItem>
          </SelectContent>
        </Select>
        <Select value={status} onValueChange={setStatus}>
          <SelectTrigger className="w-32"><SelectValue placeholder="Status" /></SelectTrigger>
          <SelectContent>
            <SelectItem value="all">All status</SelectItem>
            <SelectItem value="active">Active only</SelectItem>
            <SelectItem value="inactive">Inactive only</SelectItem>
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

      <AccountFormModal
        open={open}
        onClose={() => setOpen(false)}
        form={form}
        setForm={setForm}
        editingAccount={editingAccount}
        onSaved={() => { setOpen(false); reload() }}
        accounts={accounts}
      />
      <ConfirmModal
        open={!!deleteTarget}
        onClose={() => setDeleteTarget(null)}
        onConfirm={confirmDelete}
        title="Delete Account"
        message={deleteTarget ? `Delete or deactivate account "${deleteTarget.code} — ${deleteTarget.name}"? If the account has posted transactions it will be deactivated (soft delete) instead of removed.` : ''}
      />
    </div>
  )
}

function AccountFormModal({ open, onClose, form, setForm, onSaved, accounts, editingAccount }: any) {
  const parent = form.parentId ? accounts.find((a: any) => a.id === form.parentId) : null
  const isEdit = !!editingAccount
  const save = async () => {
    try {
      if (isEdit) {
        await apiPatch(`/api/accounts/${editingAccount.id}`, form)
        toast.success('Account updated')
      } else {
        await apiPost('/api/accounts', form)
        toast.success('Account created')
      }
      onSaved()
    } catch (e: any) { toast.error(e.message) }
  }
  return (
    <Modal open={open} onClose={onClose} title={isEdit ? `Edit Account ${editingAccount?.code || ''}` : 'Add Account'}
      footer={<>
        <Button variant="outline" onClick={onClose}>Cancel</Button>
        <Button onClick={save}><Save className="h-4 w-4 mr-1" />Save</Button>
      </>}>
      <div className="grid grid-cols-2 gap-3">
        <FormRow label="Account Name" required><Input value={form.name || ''} onChange={e => setForm({ ...form, name: e.target.value })} /></FormRow>
        <FormRow label="Parent Account">
          <Select value={form.parentId || '__root__'} onValueChange={v => setForm({ ...form, parentId: v === '__root__' ? null : v })}>
            <SelectTrigger><SelectValue placeholder="Root (no parent)" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="__root__">Root (no parent)</SelectItem>
              {accounts.filter((a: any) => !a.isDetail && a.id !== editingAccount?.id).map((a: any) => (
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
          <Select value={form.bookType || '__none__'} onValueChange={v => setForm({ ...form, bookType: v === '__none__' ? null : v })}>
            <SelectTrigger><SelectValue placeholder="General" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="__none__">General</SelectItem>
              <SelectItem value="Cash">Cash</SelectItem>
              <SelectItem value="Bank">Bank</SelectItem>
            </SelectContent>
          </Select>
        </FormRow>
        <FormRow label="Account Tag">
          <Select value={form.accountTag || '__none__'} onValueChange={v => setForm({ ...form, accountTag: v === '__none__' ? null : v })}>
            <SelectTrigger><SelectValue placeholder="None" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="__none__">None</SelectItem>
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
        <FormRow label={isEdit ? "Code (re-generated if parent changes)" : "Code (auto-generated)"}><Input value={form.code || 'auto'} disabled className="bg-muted/40" /></FormRow>
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
  const [editing, setEditing] = useState<any>(null)
  const [viewOpen, setViewOpen] = useState(false)
  const [viewing, setViewing] = useState<any>(null)
  const [reverseTarget, setReverseTarget] = useState<any>(null)
  const [deleteTarget, setDeleteTarget] = useState<any>(null)
  const [printTarget, setPrintTarget] = useState<any>(null)
  const branchesParam = selectedBranchIds.length ? `&branches=${selectedBranchIds.join(',')}` : ''
  const { data, reload } = useFetch<any>(`/api/vouchers?voucherType=${type !== 'all' ? type : ''}&status=${status !== 'all' ? status : ''}${branchesParam}`)

  const vouchers = (data?.vouchers || []).filter((v: any) =>
    !search || v.voucherNo.toLowerCase().includes(search.toLowerCase()) || v.description?.toLowerCase().includes(search.toLowerCase()))

  const doPost = async (r: any) => {
    try {
      await apiPatch(`/api/vouchers/${r.id}`, { action: 'post' })
      toast.success('Voucher posted'); reload()
    } catch (e: any) { toast.error(e.message) }
  }
  const doDelete = async () => {
    if (!deleteTarget) return
    try {
      await apiDelete(`/api/vouchers/${deleteTarget.id}`)
      toast.success('Voucher deleted'); setDeleteTarget(null); reload()
    } catch (e: any) { toast.error(e.message); setDeleteTarget(null) }
  }
  const doPrint = (r: any) => {
    setPrintTarget(r)
  }

  return (
    <div>
      <PageHeader title={presetTitle || 'Vouchers'}
        action={has('vouchers.add') ? () => { setEditing(null); setOpen(true) } : undefined}
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
              <SelectItem value="OTB">OTB — Opening TB</SelectItem>
              <SelectItem value="POS-SALE">POS Sale</SelectItem>
              <SelectItem value="FEE">Fee Payment</SelectItem>
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
              {r.status === 'Draft' && has('vouchers.edit') && (
                <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); setEditing(r); setOpen(true) }} title="Edit"><Edit className="h-3.5 w-3.5" /></Button>
              )}
              <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); doPrint(r) }} title="Print"><Printer className="h-3.5 w-3.5" /></Button>
              {r.status === 'Draft' && has('vouchers.post') && (
                <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); doPost(r) }} title="Post"><CheckCircle2 className="h-3.5 w-3.5 text-green-600" /></Button>
              )}
              {r.status === 'Draft' && has('vouchers.delete') && (
                <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); setDeleteTarget(r) }} title="Delete"><Trash2 className="h-3.5 w-3.5 text-red-600" /></Button>
              )}
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

      <VoucherFormModal open={open} onClose={() => setOpen(false)} defaultType={presetType || (type !== 'all' ? type : 'CRV')} editing={editing} onSaved={() => { setOpen(false); reload() }} />
      <VoucherViewModal open={viewOpen} voucher={viewing} onClose={() => setViewOpen(false)} />
      <ReverseModal open={!!reverseTarget} voucher={reverseTarget} onClose={() => setReverseTarget(null)} onDone={() => { setReverseTarget(null); reload() }} />
      <ConfirmModal open={!!deleteTarget} onClose={() => setDeleteTarget(null)} onConfirm={doDelete} title="Delete Voucher" message={deleteTarget ? `Delete draft voucher ${deleteTarget.voucherNo}? Posted vouchers cannot be deleted — reverse instead.` : ''} />
      <VoucherPrintModal open={!!printTarget} voucher={printTarget} onClose={() => setPrintTarget(null)} />
    </div>
  )
}

function VoucherFormModal({ open, onClose, defaultType, onSaved, editing }: any) {
  const { session, branches } = useApp()
  const { data: accountsData } = useFetch<any>('/api/accounts')
  const { data: taxHeadsData } = useFetch<any>('/api/tax-heads')
  const accounts = accountsData?.accounts || []
  const detailAccounts = accounts.filter((a: any) => a.isDetail && a.isActive)
  const taxHeads = taxHeadsData?.taxHeads || []
  // Book Accounts: filtered by voucher type
  //   CRV/CPV → Cash accounts; BRV/BPV → Bank accounts; JV → none
  const isCashType = defaultType === 'CRV' || defaultType === 'CPV'
  const isBankType = defaultType === 'BRV' || defaultType === 'BPV'
  const isJV = defaultType === 'JV' || defaultType === 'OTB'
  const bookAccounts = accounts.filter((a: any) =>
    a.isActive && (isCashType ? a.bookType === 'Cash' : isBankType ? a.bookType === 'Bank' : false)
  )
  // For CRV/BRV: detail lines are CREDITED (book debited)
  // For CPV/BPV: detail lines are DEBITED (book credited)
  // For JV: user enters both Dr and Cr manually
  const detailIsCredit = defaultType === 'CRV' || defaultType === 'BRV'
  const [form, setForm] = useState<any>({
    voucherDate: new Date().toISOString().slice(0, 10),
    reference: '',
    bookAccountId: '',
    branchId: session?.branchId || branches[0]?.id || '',
    description: '',
    lines: [emptyLine()],
  })

  function emptyLine() {
    return {
      accountId: '',
      lineDescription: '',
      title: '',
      reference: '',
      amount: 0,
      debit: 0,
      credit: 0,
      taxAccountId: '',
      taxRate: 0,
      taxAmount: 0,
      chequeNo: '',
      chequeAmount: 0,
      chequeBankName: '',
      chequeStatus: '',
      status: 'Active',
    }
  }

  // Load form when modal opens or editing changes
  useEffect(() => {
    if (!open) return
    if (editing) {
      // editing existing draft — prefill from voucher + lines
      const detailLines = (editing.lines || []).filter((l: any) => l.accountId !== editing.bookAccountId).map((l: any) => ({
        accountId: l.accountId,
        lineDescription: l.lineDescription || '',
        title: l.title || '',
        reference: l.reference || '',
        amount: l.amount || (l.debit || l.credit) || 0,
        debit: l.debit || 0,
        credit: l.credit || 0,
        taxAccountId: l.taxAccountId || '',
        taxRate: l.taxRate || 0,
        taxAmount: l.taxAmount || 0,
        chequeNo: l.chequeNo || '',
        chequeAmount: l.chequeAmount || 0,
        chequeBankName: l.chequeBankName || '',
        chequeStatus: l.chequeStatus || '',
        status: l.status || 'Active',
      }))
      setForm({
        voucherDate: editing.voucherDate?.slice(0, 10) || new Date().toISOString().slice(0, 10),
        reference: editing.reference || '',
        bookAccountId: editing.bookAccountId || '',
        branchId: editing.branchId || '',
        description: editing.description || '',
        lines: detailLines.length ? detailLines : [emptyLine()],
      })
    } else {
      setForm({
        voucherDate: new Date().toISOString().slice(0, 10),
        reference: '',
        bookAccountId: '',
        branchId: session?.branchId || branches[0]?.id || '',
        description: '',
        lines: [emptyLine()],
      })
    }
  }, [open, editing])

  // Compute totals.
  // For CRV/BRV: book is debited total of detail amounts; detail lines are credited.
  // For CPV/BPV: book is credited total of detail amounts; detail lines are debited.
  // For JV: detail totals = sum of debit + sum of credit; must equal.
  const totalDetailAmount = form.lines.reduce((s: number, l: any) => s + (Number(l.amount) || 0), 0)
  const totalDebitJV = form.lines.reduce((s: number, l: any) => s + (Number(l.debit) || 0), 0)
  const totalCreditJV = form.lines.reduce((s: number, l: any) => s + (Number(l.credit) || 0), 0)
  const balancedJV = Math.abs(totalDebitJV - totalCreditJV) < 0.01
  const bookAccountSideLabel = isJV ? '' : (detailIsCredit ? 'Book Account Debit' : 'Book Account Credit')
  const balanced = isJV ? balancedJV : (form.bookAccountId && form.lines.length > 0 && form.lines.every((l: any) => l.accountId) && totalDetailAmount > 0)

  const setLine = (i: number, patch: any) => {
    setForm((f: any) => ({ ...f, lines: f.lines.map((l: any, idx: number) => idx === i ? { ...l, ...patch } : l) }))
  }
  const addLine = () => setForm((f: any) => ({ ...f, lines: [...f.lines, emptyLine()] }))
  const removeLine = (i: number) => setForm((f: any) => ({ ...f, lines: f.lines.filter((_: any, idx: number) => idx !== i) }))

  // Auto-calc tax amount when amount or taxRate changes (for non-JV)
  const onLineAmountChange = (i: number, amt: number) => {
    const l = form.lines[i]
    const taxRate = Number(l.taxRate) || 0
    const taxAmount = Math.round(amt * taxRate) / 100
    setLine(i, { amount: amt, debit: 0, credit: 0, taxAmount: l.taxAccountId ? taxAmount : 0 })
  }
  const onLineTaxAccountChange = (i: number, taxAccountId: string) => {
    const l = form.lines[i]
    // find tax head to get its rate
    const th = taxHeads.find((t: any) => t.id === taxAccountId)
    const taxRate = th?.rate || 0
    const amt = Number(l.amount) || 0
    const taxAmount = taxAccountId && amt ? Math.round(amt * taxRate) / 100 : 0
    setLine(i, { taxAccountId, taxRate, taxAmount })
  }
  const onLineTaxRateChange = (i: number, taxRate: number) => {
    const l = form.lines[i]
    const amt = Number(l.amount) || 0
    const taxAmount = l.taxAccountId && amt ? Math.round(amt * taxRate) / 100 : 0
    setLine(i, { taxRate, taxAmount })
  }

  const save = async () => {
    if (!form.voucherDate || !form.branchId) {
      toast.error('Date and branch are required'); return
    }
    if (!isJV && !form.bookAccountId) {
      toast.error('Book Account is required for cash/bank vouchers'); return
    }
    if (form.lines.length === 0 || !form.lines[0].accountId) {
      toast.error('At least one detail line is required'); return
    }
    if (isJV && !balancedJV) {
      toast.error(`JV not balanced: Debit ${totalDebitJV} vs Credit ${totalCreditJV}`); return
    }
    if (!isJV && totalDetailAmount <= 0) {
      toast.error('Total amount must be greater than zero'); return
    }
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
          title: l.title,
          reference: l.reference,
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
      if (editing) payload.existingVoucherId = editing.id
      await apiPost('/api/vouchers', payload)
      toast.success(editing ? 'Voucher updated' : 'Voucher posted')
      onSaved()
    } catch (e: any) { toast.error(e.message) }
  }

  const saveDraft = async () => {
    if (!form.voucherDate || !form.branchId) {
      toast.error('Date and branch are required'); return
    }
    try {
      const payload: any = {
        voucherType: defaultType,
        voucherDate: form.voucherDate,
        branchId: form.branchId,
        bookAccountId: isJV ? null : form.bookAccountId,
        description: form.description,
        reference: form.reference,
        status: 'Draft',
        lines: form.lines.map((l: any) => ({
          accountId: l.accountId,
          amount: Number(l.amount) || 0,
          debit: isJV ? (Number(l.debit) || 0) : 0,
          credit: isJV ? (Number(l.credit) || 0) : 0,
          lineDescription: l.lineDescription,
          title: l.title,
          reference: l.reference,
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
      if (editing) payload.existingVoucherId = editing.id
      await apiPost('/api/vouchers', payload)
      toast.success('Draft saved')
      onSaved()
    } catch (e: any) { toast.error(e.message) }
  }

  const title = editing
    ? `Edit ${voucherTypeLabel(defaultType)} ${editing.voucherNo}`
    : `New ${voucherTypeLabel(defaultType)}`

  return (
    <Modal open={open} onClose={onClose} title={title} size="xl"
      footer={<>
        <Button variant="outline" onClick={onClose}>Cancel</Button>
        {!editing && <Button variant="outline" onClick={saveDraft}><Save className="h-4 w-4 mr-1" />Save as Draft</Button>}
        <Button onClick={save} disabled={!balanced}>
          <Save className="h-4 w-4 mr-1" />
          {isJV
            ? (balancedJV ? 'Post Voucher' : `Out of balance: ${Math.abs(totalDebitJV - totalCreditJV).toFixed(2)}`)
            : (balanced ? 'Post Voucher' : 'Fill all required fields')}
        </Button>
      </>}>
      {/* HEADER: Date | Reference (small) | Book Account | Branch */}
      <div className="grid grid-cols-2 sm:grid-cols-12 gap-3 items-end">
        <div className="sm:col-span-3">
          <FormRow label="Date" required><Input type="date" value={form.voucherDate} onChange={e => setForm({ ...form, voucherDate: e.target.value })} /></FormRow>
        </div>
        <div className="sm:col-span-3">
          <FormRow label="Reference #"><Input value={form.reference || ''} onChange={e => setForm({ ...form, reference: e.target.value })} placeholder="Optional" /></FormRow>
        </div>
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
        <div className="sm:col-span-12">
          <FormRow label="Description"><Input value={form.description || ''} onChange={e => setForm({ ...form, description: e.target.value })} placeholder="Voucher description" /></FormRow>
        </div>
      </div>

      <div className="mt-4 border rounded">
        <div className="px-3 py-2 bg-muted/40 border-b font-medium text-sm flex items-center justify-between">
          <span>Detail Lines {isJV ? '(manual Debit / Credit)' : `(${detailIsCredit ? 'Credit side' : 'Debit side'} — Book Account auto-${detailIsCredit ? 'Debited' : 'Credited'})`}</span>
          <span className={`text-xs ${isJV ? (balancedJV ? 'text-green-600' : 'text-red-600') : 'text-muted-foreground'}`}>
            {isJV
              ? `Dr: ${fmtMoney(totalDebitJV)} · Cr: ${fmtMoney(totalCreditJV)} · ${balancedJV ? 'Balanced' : 'Not balanced'}`
              : `Book ${detailIsCredit ? 'Dr' : 'Cr'}: ${fmtMoney(totalDetailAmount)}`
            }
          </span>
        </div>
        <div className="overflow-x-auto max-h-[420px] overflow-y-auto">
          <table className="w-full text-xs">
            <thead className="bg-muted/30 border-b sticky top-0">
              <tr>
                <th className="px-2 py-1.5 text-left">Account</th>
                <th className="px-2 py-1.5 text-left">Description</th>
                {isJV ? (
                  <>
                    <th className="px-2 py-1.5 text-right">Debit</th>
                    <th className="px-2 py-1.5 text-right">Credit</th>
                  </>
                ) : (
                  <th className="px-2 py-1.5 text-right">Amount</th>
                )}
                <th className="px-2 py-1.5 text-left">Tax Account</th>
                <th className="px-2 py-1.5 text-right">Tax %</th>
                <th className="px-2 py-1.5 text-right">Tax Amount</th>
                <th className="px-2 py-1.5 text-left">Cheque No</th>
                <th className="px-2 py-1.5 text-right">Cheque Amount</th>
                <th className="px-2 py-1.5 text-left">Bank Name</th>
                <th className="px-2 py-1.5 text-left">Cheque Status</th>
                <th className="px-2 py-1.5 text-left">Status</th>
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
                  <td className="px-2 py-1.5 min-w-[140px]">
                    <Input value={l.lineDescription || ''} onChange={e => setLine(i, { lineDescription: e.target.value })} className="h-7" placeholder="Line description" />
                  </td>
                  {isJV ? (
                    <>
                      <td className="px-2 py-1.5 w-24">
                        <Input type="number" value={l.debit || 0} onChange={e => setLine(i, { debit: Number(e.target.value), credit: 0, amount: Number(e.target.value) })} className="h-7 text-right" />
                      </td>
                      <td className="px-2 py-1.5 w-24">
                        <Input type="number" value={l.credit || 0} onChange={e => setLine(i, { credit: Number(e.target.value), debit: 0, amount: Number(e.target.value) })} className="h-7 text-right" />
                      </td>
                    </>
                  ) : (
                    <td className="px-2 py-1.5 w-28">
                      <Input type="number" value={l.amount || 0} onChange={e => onLineAmountChange(i, Number(e.target.value))} className="h-7 text-right" />
                    </td>
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
                  <td className="px-2 py-1.5 w-20">
                    <Input type="number" step="0.01" value={l.taxRate || 0} onChange={e => onLineTaxRateChange(i, Number(e.target.value))} className="h-7 text-right" />
                  </td>
                  <td className="px-2 py-1.5 w-24">
                    <Input type="number" value={l.taxAmount || 0} onChange={e => setLine(i, { taxAmount: Number(e.target.value) })} className="h-7 text-right" />
                  </td>
                  <td className="px-2 py-1.5 min-w-[120px]">
                    <Input value={l.chequeNo || ''} onChange={e => setLine(i, { chequeNo: e.target.value })} className="h-7" placeholder="Cheque #" />
                  </td>
                  <td className="px-2 py-1.5 w-28">
                    <Input type="number" value={l.chequeAmount || 0} onChange={e => setLine(i, { chequeAmount: Number(e.target.value) })} className="h-7 text-right" />
                  </td>
                  <td className="px-2 py-1.5 min-w-[120px]">
                    <Input value={l.chequeBankName || ''} onChange={e => setLine(i, { chequeBankName: e.target.value })} className="h-7" placeholder="Bank name" />
                  </td>
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
                  <td className="px-2 py-1.5 min-w-[100px]">
                    <Select value={l.status || 'Active'} onValueChange={v => setLine(i, { status: v })}>
                      <SelectTrigger className="h-7"><SelectValue /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="Active">Active</SelectItem>
                        <SelectItem value="Hold">Hold</SelectItem>
                      </SelectContent>
                    </Select>
                  </td>
                  <td className="px-2 py-1.5">
                    <Button size="sm" variant="ghost" onClick={() => removeLine(i)} disabled={form.lines.length === 1}><Trash2 className="h-3 w-3" /></Button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="p-2 border-t">
          <Button size="sm" variant="outline" onClick={addLine}><Plus className="h-3 w-3 mr-1" />Add Line</Button>
        </div>
      </div>

      <div className="mt-2 text-xs text-muted-foreground">
        {defaultType === 'CRV' && 'CRV: Book Account (cash) is auto-DEBITED. Detail lines are credited (income received).'}
        {defaultType === 'CPV' && 'CPV: Book Account (cash) is auto-CREDITED. Detail lines are debited (expense paid).'}
        {defaultType === 'BRV' && 'BRV: Book Account (bank) is auto-DEBITED. Detail lines are credited (income received).'}
        {defaultType === 'BPV' && 'BPV: Book Account (bank) is auto-CREDITED. Detail lines are debited (expense paid).'}
        {defaultType === 'JV' && 'JV: Manual Debit and Credit entry. Total Debit must equal Total Credit.'}
        {defaultType === 'OTB' && 'OTB: Opening balances — manual Debit and Credit entry.'}
      </div>
    </Modal>
  )
}

function voucherTypeLabel(vt: string): string {
  const m: Record<string, string> = {
    CRV: 'Cash Receipt Voucher', CPV: 'Cash Payment Voucher',
    BRV: 'Bank Receipt Voucher', BPV: 'Bank Payment Voucher',
    JV: 'Journal Voucher', OTB: 'Opening Trial Balance',
  }
  return m[vt] || vt
}

function VoucherPrintModal({ open, voucher, onClose }: any) {
  if (!voucher) return null
  return (
    <Modal open={open} onClose={onClose} title={`Print ${voucher.voucherNo}`} size="lg"
      footer={<>
        <Button variant="outline" onClick={onClose}>Close</Button>
        <Button onClick={() => window.print()}><Printer className="h-4 w-4 mr-1" />Print</Button>
      </>}>
      <div className="text-sm">
        <div className="text-center mb-4">
          <div className="text-lg font-semibold">{voucherTypeLabel(voucher.voucherType)}</div>
          <div className="text-xs text-muted-foreground">Voucher # {voucher.voucherNo}</div>
        </div>
        <div className="grid grid-cols-2 gap-3 mb-4">
          <div><span className="text-xs text-muted-foreground">Date:</span> {fmtDateStr(voucher.voucherDate)}</div>
          <div><span className="text-xs text-muted-foreground">Branch:</span> {voucher.branch?.name || '—'}</div>
          <div><span className="text-xs text-muted-foreground">Book Account:</span> {voucher.bookAccount?.name || '—'}</div>
          <div><span className="text-xs text-muted-foreground">Reference:</span> {voucher.reference || '—'}</div>
          <div className="col-span-2"><span className="text-xs text-muted-foreground">Description:</span> {voucher.description || '—'}</div>
        </div>
        <table className="w-full border">
          <thead className="bg-muted/40 border-b">
            <tr>
              <th className="px-3 py-2 text-left text-xs">Account</th>
              <th className="px-3 py-2 text-left text-xs">Description</th>
              <th className="px-3 py-2 text-right text-xs">Debit</th>
              <th className="px-3 py-2 text-right text-xs">Credit</th>
            </tr>
          </thead>
          <tbody>
            {(voucher.lines || []).map((l: any) => (
              <tr key={l.id} className="border-b last:border-0">
                <td className="px-3 py-2 text-xs">{l.account?.code} — {l.account?.name}</td>
                <td className="px-3 py-2 text-xs">{l.lineDescription || '—'}</td>
                <td className="px-3 py-2 text-right font-mono text-xs">{fmtMoney(l.debit)}</td>
                <td className="px-3 py-2 text-right font-mono text-xs">{fmtMoney(l.credit)}</td>
              </tr>
            ))}
          </tbody>
          <tfoot className="border-t bg-muted/30 font-medium">
            <tr>
              <td colSpan={2} className="px-3 py-2 text-right text-xs">Total</td>
              <td className="px-3 py-2 text-right font-mono text-xs">{fmtMoney(voucher.totalDebit)}</td>
              <td className="px-3 py-2 text-right font-mono text-xs">{fmtMoney(voucher.totalCredit)}</td>
            </tr>
          </tfoot>
        </table>
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
  const [editing, setEditing] = useState<any>(null)
  const [form, setForm] = useState<any>({})
  const [deleteTarget, setDeleteTarget] = useState<any>(null)
  const { data, reload } = useFetch<any>('/api/tax-heads')
  const taxHeads = data?.taxHeads || []
  const openAdd = () => { setEditing(null); setForm({ taxType: 'Sales', isActive: true }); setOpen(true) }
  const openEdit = (t: any) => { setEditing(t); setForm({ ...t }); setOpen(true) }
  const save = async () => {
    try {
      if (editing) {
        await apiPatch(`/api/tax-heads/${editing.id}`, form)
        toast.success('Tax head updated')
      } else {
        await apiPost('/api/tax-heads', form)
        toast.success('Tax head created')
      }
      setOpen(false); reload()
    } catch (e: any) { toast.error(e.message) }
  }
  const doDelete = async () => {
    if (!deleteTarget) return
    try {
      const res = await fetch(`/api/tax-heads/${deleteTarget.id}`, { method: 'DELETE' })
      const json = await res.json()
      if (!res.ok) throw new Error(json.error || 'Failed')
      if (json.softDeleted) toast.success('Tax head deactivated (in use)')
      else toast.success('Tax head deleted')
      setDeleteTarget(null); reload()
    } catch (e: any) { toast.error(e.message); setDeleteTarget(null) }
  }
  return (
    <div>
      <PageHeader title="Tax Heads"
        action={has('tax.add') ? openAdd : undefined}
        actionLabel="Add Tax Head" />
      <Toolbar><Button variant="ghost" size="sm" onClick={reload}>Refresh</Button></Toolbar>
      <DataTable
        columns={[
          { key: 'actions', label: 'Actions', sticky: true, render: (r: any) => (
            <div className="flex gap-0.5">
              {has('tax.edit') && <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); openEdit(r) }} title="Edit / Update"><Edit className="h-3.5 w-3.5" /></Button>}
              {has('tax.delete') && <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); setDeleteTarget(r) }} title="Delete / Deactivate"><Trash2 className="h-3.5 w-3.5 text-red-600" /></Button>}
            </div>
          ) },
          { key: 'code', label: 'Code', mono: true },
          { key: 'shortName', label: 'Short Name' },
          { key: 'name', label: 'Name' },
          { key: 'taxType', label: 'Type' },
          { key: 'rate', label: 'Rate', align: 'right', render: (r: any) => `${r.rate}%` },
          { key: 'isActive', label: 'Status', render: (r: any) => <StatusBadge status={r.isActive ? 'Active' : 'Inactive'} /> },
        ]}
        rows={taxHeads}
      />
      <Modal open={open} onClose={() => setOpen(false)} title={editing ? `Edit Tax Head ${editing.code || ''}` : 'Add Tax Head'}
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={save}><Save className="h-4 w-4 mr-1" />{editing ? 'Update' : 'Save'}</Button>
        </>}>
        <div className="grid grid-cols-2 gap-3">
          <FormRow label="Code (auto-generated)"><Input disabled value={form.code || 'auto'} className="bg-muted/40" /></FormRow>
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
          <FormRow label="Rate %"><Input type="number" step="0.01" value={form.rate || 0} onChange={e => setForm({ ...form, rate: Number(e.target.value) })} /></FormRow>
          <FormRow label="Active"><Switch checked={form.isActive !== false} onCheckedChange={v => setForm({ ...form, isActive: v })} /></FormRow>
        </div>
        <div className="mt-3 text-xs text-muted-foreground">Code is auto-generated as a 3-digit sequence per branch (001, 002, 003…). Tax heads with "Active" status appear in the voucher Tax Account dropdown.</div>
      </Modal>
      <ConfirmModal open={!!deleteTarget} onClose={() => setDeleteTarget(null)} onConfirm={doDelete} title="Delete Tax Head" message={deleteTarget ? `Delete or deactivate tax head "${deleteTarget.code} — ${deleteTarget.shortName}"? If it is already used in posted vouchers, it will be deactivated instead of deleted.` : ''} />
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
  const branchesParam = selectedBranchIds.length ? `&branches=${selectedBranchIds.join(',')}` : ''
  const { data, reload } = useFetch<any>(`/api/members?status=${status !== 'all' ? status : ''}${branchesParam}`)
  const { data: plansData } = useFetch<any>('/api/memberships')
  const { data: trainersData } = useFetch<any>('/api/staff?isTrainer=true')
  const plans = plansData?.plans || []
  const trainers = trainersData?.staff || []
  const members = (data?.members || []).filter((m: any) =>
    !search || m.memberId.toLowerCase().includes(search.toLowerCase()) || (m.firstName + ' ' + (m.lastName || '')).toLowerCase().includes(search.toLowerCase()) || m.phone?.includes(search))

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
            <div className="flex gap-1">
              <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); setViewing(r) }}><Eye className="h-3.5 w-3.5" /></Button>
              {has('members.edit') && <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); setEditing(r); setOpen(true) }}><Edit className="h-3.5 w-3.5" /></Button>}
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
      <MemberFormModal open={open} onClose={() => setOpen(false)} editing={editing} plans={plans} trainers={trainers} onSaved={() => { setOpen(false); reload() }} />
      <MemberViewModal open={!!viewing} member={viewing} onClose={() => setViewing(null)} onEdit={() => { setEditing(viewing); setViewing(null); setOpen(true) }} />
    </div>
  )
}

function MemberFormModal({ open, onClose, editing, plans, trainers, onSaved }: any) {
  const { session, branches } = useApp()
  const [form, setForm] = useState<any>({})
  const [uploading, setUploading] = useState(false)

  useEffect(() => {
    if (open) {
      setForm(editing ? { ...editing, joiningDate: editing.joiningDate?.slice(0, 10), billingStartDate: editing.billingStartDate?.slice(0, 10), dob: editing.dob?.slice(0, 10) } : {
        joiningDate: new Date().toISOString().slice(0, 10),
        billingStartDate: new Date().toISOString().slice(0, 10),
        branchId: session?.branchId || branches[0]?.id,
        feeRelaxationDays: 0,
        status: 'Active',
        gender: '',
      })
    }
  }, [open, editing])

  const uploadPhoto = async (file: File) => {
    setUploading(true)
    try {
      const fd = new FormData()
      fd.append('file', file)
      const res = await fetch('/api/uploads', { method: 'POST', body: fd })
      const json = await res.json()
      if (!res.ok) throw new Error(json.error || 'Upload failed')
      setForm((f: any) => ({ ...f, photo: json.url }))
      toast.success('Photo uploaded')
    } catch (e: any) { toast.error(e.message) }
    finally { setUploading(false) }
  }

  const onFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const f = e.target.files?.[0]
    if (f) uploadPhoto(f)
  }
  const removePhoto = () => setForm((f: any) => ({ ...f, photo: null }))

  const save = async () => {
    // Frontend validation for required fields
    if (!form.firstName?.trim()) { toast.error('First Name is required'); return }
    if (!form.lastName?.trim()) { toast.error('Last Name is required'); return }
    if (!form.phone?.trim()) { toast.error('Contact Number is required'); return }
    if (!form.membershipPlanId) { toast.error('Membership is required'); return }
    if (!form.assignedTrainerId) { toast.error('Trainer is required'); return }
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
    <Modal open={open} onClose={onClose} title={editing ? `Edit Member ${editing.memberId || ''}` : 'New Member'} size="lg"
      footer={<>
        <Button variant="outline" onClick={onClose}>Cancel</Button>
        <Button onClick={save}><Save className="h-4 w-4 mr-1" />Save</Button>
      </>}>
      <div className="space-y-5 max-h-[70vh] overflow-y-auto pr-1">
        {/* Personal Information */}
        <div>
          <div className="text-xs font-semibold uppercase text-muted-foreground mb-2 pb-1 border-b">Personal Information</div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <FormRow label="First Name" required><Input value={form.firstName || ''} onChange={e => setForm({ ...form, firstName: e.target.value })} /></FormRow>
            <FormRow label="Last Name" required><Input value={form.lastName || ''} onChange={e => setForm({ ...form, lastName: e.target.value })} /></FormRow>
            <FormRow label="Gender">
              <Select value={form.gender || '__none__'} onValueChange={v => setForm({ ...form, gender: v === '__none__' ? '' : v })}>
                <SelectTrigger><SelectValue placeholder="—" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="__none__">—</SelectItem>
                  <SelectItem value="Male">Male</SelectItem>
                  <SelectItem value="Female">Female</SelectItem>
                  <SelectItem value="Other">Other</SelectItem>
                </SelectContent>
              </Select>
            </FormRow>
            <FormRow label="Date of Birth"><Input type="date" value={form.dob || ''} onChange={e => setForm({ ...form, dob: e.target.value })} /></FormRow>
            <FormRow label="CNIC"><Input value={form.cnic || ''} onChange={e => setForm({ ...form, cnic: e.target.value })} /></FormRow>
            <FormRow label="Branch" required>
              <Select value={form.branchId || '__none__'} onValueChange={v => setForm({ ...form, branchId: v === '__none__' ? '' : v })}>
                <SelectTrigger><SelectValue placeholder="Select branch" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="__none__">—</SelectItem>
                  {branches.map((b: any) => <SelectItem key={b.id} value={b.id}>{b.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </FormRow>
          </div>
        </div>

        {/* Contact Information */}
        <div>
          <div className="text-xs font-semibold uppercase text-muted-foreground mb-2 pb-1 border-b">Contact Information</div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <FormRow label="Contact Number" required><Input value={form.phone || ''} onChange={e => setForm({ ...form, phone: e.target.value })} placeholder="0300XXXXXXX" /></FormRow>
            <FormRow label="WhatsApp"><Input value={form.whatsapp || ''} onChange={e => setForm({ ...form, whatsapp: e.target.value })} /></FormRow>
            <FormRow label="Email"><Input value={form.email || ''} onChange={e => setForm({ ...form, email: e.target.value })} /></FormRow>
            <FormRow label="Emergency Contact"><Input value={form.emergencyContact || ''} onChange={e => setForm({ ...form, emergencyContact: e.target.value })} /></FormRow>
            <FormRow label="Emergency #"><Input value={form.emergencyContactNo || ''} onChange={e => setForm({ ...form, emergencyContactNo: e.target.value })} /></FormRow>
            <div className="col-span-1 sm:col-span-2"><FormRow label="Address"><Textarea rows={2} value={form.address || ''} onChange={e => setForm({ ...form, address: e.target.value })} /></FormRow></div>
          </div>
        </div>

        {/* Membership Information */}
        <div>
          <div className="text-xs font-semibold uppercase text-muted-foreground mb-2 pb-1 border-b">Membership Information</div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <FormRow label="Joining Date" required><Input type="date" value={form.joiningDate || ''} onChange={e => setForm({ ...form, joiningDate: e.target.value })} /></FormRow>
            <FormRow label="Billing Start Date"><Input type="date" value={form.billingStartDate || ''} onChange={e => setForm({ ...form, billingStartDate: e.target.value })} /></FormRow>
            <FormRow label="Fee Relaxation Days (0–27)">
              <Input type="number" min={0} max={27} value={form.feeRelaxationDays || 0} onChange={e => setForm({ ...form, feeRelaxationDays: Math.max(0, Math.min(27, Number(e.target.value))) })} />
            </FormRow>
            <FormRow label="Membership" required>
              <Select value={form.membershipPlanId || '__none__'} onValueChange={v => setForm({ ...form, membershipPlanId: v === '__none__' ? '' : v })}>
                <SelectTrigger><SelectValue placeholder="—" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="__none__">—</SelectItem>
                  {plans.map((p: any) => <SelectItem key={p.id} value={p.id}>{p.name} — {fmtMoney(p.amount)}</SelectItem>)}
                </SelectContent>
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
          </div>
        </div>

        {/* Trainer Information */}
        <div>
          <div className="text-xs font-semibold uppercase text-muted-foreground mb-2 pb-1 border-b">Trainer Information</div>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <FormRow label="Assigned Trainer" required>
              <Select value={form.assignedTrainerId || '__none__'} onValueChange={v => setForm({ ...form, assignedTrainerId: v === '__none__' ? '' : v })}>
                <SelectTrigger><SelectValue placeholder="—" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="__none__">—</SelectItem>
                  {trainers.map((t: any) => <SelectItem key={t.id} value={t.id}>{t.employeeId} — {t.firstName} {t.lastName || ''}</SelectItem>)}
                </SelectContent>
              </Select>
            </FormRow>
          </div>
        </div>

        {/* Other Member Information */}
        <div>
          <div className="text-xs font-semibold uppercase text-muted-foreground mb-2 pb-1 border-b">Other Member Information</div>
          <FormRow label="Notes"><Textarea rows={2} value={form.notes || ''} onChange={e => setForm({ ...form, notes: e.target.value })} /></FormRow>
        </div>

        {/* Photo */}
        <div>
          <div className="text-xs font-semibold uppercase text-muted-foreground mb-2 pb-1 border-b">Photo</div>
          <div className="flex items-center gap-4">
            <div className="h-24 w-24 rounded border bg-muted/40 overflow-hidden flex items-center justify-center">
              {form.photo ? (
                <img src={form.photo} alt="Member" className="h-full w-full object-cover" />
              ) : (
                <span className="text-xs text-muted-foreground">No photo</span>
              )}
            </div>
            <div className="flex flex-col gap-2">
              <label className="cursor-pointer">
                <input type="file" accept="image/jpeg,image/png,image/webp,image/gif" onChange={onFileChange} className="hidden" />
                <span className="inline-flex items-center gap-1 px-3 py-1.5 rounded border bg-background text-sm hover:bg-muted">
                  {uploading ? 'Uploading…' : 'Upload Photo'}
                </span>
              </label>
              {form.photo && (
                <Button variant="outline" size="sm" onClick={removePhoto}>Remove Photo</Button>
              )}
              <div className="text-xs text-muted-foreground">JPG / PNG / WebP / GIF, max 5MB</div>
            </div>
          </div>
        </div>
      </div>
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

  const doCheckOut = async (r: any) => {
    try {
      await apiPatch('/api/attendance', { id: r.id, checkOut: new Date().toISOString() })
      toast.success('Checked out')
      reload()
    } catch (e: any) { toast.error(e.message) }
  }

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
          { key: 'actions', label: 'Actions', sticky: true, render: (r: any) => (
            has('attendance.edit') && !r.checkOut ? (
              <Button size="sm" variant="outline" onClick={(e) => { e.stopPropagation(); doCheckOut(r) }}>Check Out</Button>
            ) : null
          ) },
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
  const { data: banksData } = useFetch<any>('/api/master-files?type=Banks')
  const { data: cardTypesData } = useFetch<any>('/api/master-files?type=CardTypes')
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
          { key: 'actions', label: 'Actions', sticky: true, render: (r: any) => (
            r.status !== 'Paid' && has('fees.post') ? (
              <Button size="sm" onClick={(e) => { e.stopPropagation(); setPayTarget(r); setPayOpen(true) }}>Collect</Button>
            ) : null
          ) },
          { key: 'feeNo', label: 'Fee #', mono: true },
          { key: 'member', label: 'Member', render: (r: any) => `${r.member?.firstName} ${r.member?.lastName || ''}` },
          { key: 'billingPeriodStart', label: 'Period', render: (r: any) => `${fmtDateStr(r.billingPeriodStart)} — ${fmtDateStr(r.billingPeriodEnd)}` },
          { key: 'amount', label: 'Amount', align: 'right', mono: true, render: (r: any) => fmtMoney(r.amount) },
          { key: 'paidAmount', label: 'Paid', align: 'right', mono: true, render: (r: any) => fmtMoney(r.paidAmount) },
          { key: 'balance', label: 'Balance', align: 'right', mono: true, render: (r: any) => fmtMoney(r.balance) },
          { key: 'dueDate', label: 'Due', render: (r: any) => fmtDateStr(r.dueDate) },
          { key: 'status', label: 'Status', render: (r: any) => <StatusBadge status={r.status} /> },
        ]}
        rows={fees}
      />
      <FeeCreateModal open={open} onClose={() => setOpen(false)} members={membersData?.members || []} onSaved={() => { setOpen(false); reload() }} />
      <FeePayModal
        open={payOpen} fee={payTarget}
        cashAccounts={accountsData?.accounts || []}
        bankAccounts={bankAccountsData?.accounts || []}
        banks={(banksData?.records || []).filter((b: any) => b.isActive)}
        cardTypes={(cardTypesData?.records || []).filter((c: any) => c.isActive)}
        onClose={() => setPayOpen(false)} onPaid={() => { setPayOpen(false); reload() }}
      />
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

function FeePayModal({ open, fee, cashAccounts, bankAccounts, banks, cardTypes, onClose, onPaid }: any) {
  const { session } = useApp()
  const [form, setForm] = useState<any>({ amount: 0, method: 'Cash', accountId: '', cardTypeId: '', bankMasterId: '', reference: '', paymentDate: new Date().toISOString().slice(0, 10) })
  useEffect(() => {
    if (fee) setForm({ amount: fee.balance || 0, method: 'Cash', accountId: '', cardTypeId: '', bankMasterId: '', reference: '', paymentDate: new Date().toISOString().slice(0, 10) })
  }, [fee])

  // Determine which accounts to show based on payment method
  // Cash → cash accounts; Card / Bank Transfer / Online → bank accounts
  const accounts = form.method === 'Cash' ? cashAccounts : bankAccounts
  // Validation: Card requires cardTypeId; Bank Transfer requires bankMasterId
  const needsCardType = form.method === 'Card'
  const needsBank = form.method === 'Bank Transfer'
  const canSubmit = form.amount > 0 && form.accountId && (!needsCardType || form.cardTypeId) && (!needsBank || form.bankMasterId)

  const submit = async () => {
    if (needsCardType && !form.cardTypeId) { toast.error('Card Type is required for Card payment'); return }
    if (needsBank && !form.bankMasterId) { toast.error('Bank is required for Bank Transfer payment'); return }
    if (!form.accountId) { toast.error('Account is required'); return }
    try {
      await apiPost('/api/fees/pay', { feeId: fee.id, ...form })
      toast.success('Payment recorded and voucher posted')
      onPaid()
    } catch (e: any) { toast.error(e.message) }
  }

  return (
    <Modal open={open} onClose={onClose} title={`Collect Payment — ${fee?.feeNo || ''}`}
      footer={<>
        <Button variant="outline" onClick={onClose}>Cancel</Button>
        <Button onClick={submit} disabled={!canSubmit}><Banknote className="h-4 w-4 mr-1" />Collect & Post</Button>
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
          <Select value={form.method} onValueChange={v => setForm({ ...form, method: v, accountId: '', cardTypeId: '', bankMasterId: '' })}>
            <SelectTrigger><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="Cash">Cash</SelectItem>
              <SelectItem value="Card">Card</SelectItem>
              <SelectItem value="Bank Transfer">Bank Transfer</SelectItem>
              <SelectItem value="Online">Online</SelectItem>
            </SelectContent>
          </Select>
        </FormRow>
        <FormRow label="Amount" required><Input type="number" value={form.amount || 0} onChange={e => setForm({ ...form, amount: Number(e.target.value) })} /></FormRow>
        <FormRow label={form.method === 'Cash' ? 'Cash Account' : 'Bank Account'} required>
          <Select value={form.accountId} onValueChange={v => setForm({ ...form, accountId: v })}>
            <SelectTrigger><SelectValue placeholder="Select account" /></SelectTrigger>
            <SelectContent>{accounts.map((a: any) => <SelectItem key={a.id} value={a.id}>{a.code} — {a.name}</SelectItem>)}</SelectContent>
          </Select>
        </FormRow>
        <FormRow label="Payment Date"><Input type="date" value={form.paymentDate} onChange={e => setForm({ ...form, paymentDate: e.target.value })} /></FormRow>
        {/* Dynamic Card Type — only for Card */}
        {form.method === 'Card' && (
          <FormRow label="Card Type" required>
            <Select value={form.cardTypeId} onValueChange={v => setForm({ ...form, cardTypeId: v })}>
              <SelectTrigger><SelectValue placeholder="Select card type" /></SelectTrigger>
              <SelectContent>
                {cardTypes.length === 0 ? <SelectItem value="__none__">No card types — add in Master Files</SelectItem> :
                  cardTypes.map((c: any) => <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>)}
              </SelectContent>
            </Select>
          </FormRow>
        )}
        {/* Dynamic Bank — only for Bank Transfer */}
        {form.method === 'Bank Transfer' && (
          <FormRow label="Bank" required>
            <Select value={form.bankMasterId} onValueChange={v => setForm({ ...form, bankMasterId: v })}>
              <SelectTrigger><SelectValue placeholder="Select bank" /></SelectTrigger>
              <SelectContent>
                {banks.length === 0 ? <SelectItem value="__none__">No banks — add in Master Files</SelectItem> :
                  banks.map((b: any) => <SelectItem key={b.id} value={b.id}>{b.name}</SelectItem>)}
              </SelectContent>
            </Select>
          </FormRow>
        )}
        <div className="col-span-2"><FormRow label="Reference"><Input value={form.reference} onChange={e => setForm({ ...form, reference: e.target.value })} placeholder="Optional receipt/cheque no." /></FormRow></div>
      </div>
      <div className="mt-3 text-xs text-muted-foreground">
        Collecting will automatically post a {form.method === 'Cash' ? 'Cash Receipt Voucher (CRV)' : 'Bank Receipt Voucher (BRV)'} to the books. No manual voucher needed.
        {form.method === 'Card' && ' Card Type is required.'}
        {form.method === 'Bank Transfer' && ' Bank is required.'}
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
  const [form, setForm] = useState<any>({})
  const branchesParam = selectedBranchIds.length ? `&branches=${selectedBranchIds.join(',')}` : ''
  const { data, reload } = useFetch<any>(`/api/prospects?status=${status !== 'all' ? status : ''}${branchesParam}`)
  const prospects = (data?.prospects || []).filter((p: any) =>
    !search || p.name?.toLowerCase().includes(search.toLowerCase()) || p.phone?.includes(search))

  return (
    <div>
      <PageHeader title="Prospects / Inquiries"
        action={has('prospects.add') ? () => { setForm({ source: 'WalkIn', status: 'New' }); setOpen(true) } : undefined}
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
          { key: 'prospectId', label: 'ID', mono: true },
          { key: 'name', label: 'Name' },
          { key: 'phone', label: 'Phone' },
          { key: 'source', label: 'Source' },
          { key: 'interestedMembership', label: 'Interested In' },
          { key: 'inquiryDate', label: 'Inquiry', render: (r: any) => fmtDateStr(r.inquiryDate) },
          { key: 'followUpDate', label: 'Follow Up', render: (r: any) => fmtDateStr(r.followUpDate) },
          { key: 'status', label: 'Status', render: (r: any) => <StatusBadge status={r.status} /> },
          { key: 'actions', label: '', align: 'right', render: (r: any) =>
            r.status !== 'Converted' && has('prospects.convert') && (
              <Button size="sm" variant="outline" onClick={async (e) => {
                e.stopPropagation()
                // open member form pre-filled — quick action: just mark as converted for demo
                if (confirm(`Mark ${r.name} as converted? This will open the member form pre-populated.`)) {
                  try { await apiPatch(`/api/prospects/${r.id}`, { action: 'convert', convertedMemberId: null }); toast.success('Marked as converted'); reload() }
                  catch (e: any) { toast.error(e.message) }
                }
              }}>Convert</Button>
            )
          },
        ]}
        rows={prospects}
      />
      <Modal open={open} onClose={() => setOpen(false)} title="Add Prospect"
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={async () => {
            try { await apiPost('/api/prospects', form); toast.success('Prospect added'); setOpen(false); reload() }
            catch (e: any) { toast.error(e.message) }
          }}><Save className="h-4 w-4 mr-1" />Save</Button>
        </>}>
        <div className="grid grid-cols-2 gap-3">
          <FormRow label="Name" required><Input value={form.name || ''} onChange={e => setForm({ ...form, name: e.target.value })} /></FormRow>
          <FormRow label="Phone"><Input value={form.phone || ''} onChange={e => setForm({ ...form, phone: e.target.value })} /></FormRow>
          <FormRow label="WhatsApp"><Input value={form.whatsapp || ''} onChange={e => setForm({ ...form, whatsapp: e.target.value })} /></FormRow>
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
          { key: 'actions', label: 'Actions', sticky: true, render: (r: any) =>
            r.status === 'Active' && has('freeze.edit') ? (
              <Button size="sm" variant="outline" onClick={async (e) => {
                e.stopPropagation()
                try { await apiPatch('/api/freezes', { id: r.id, action: 'lift' }); toast.success('Freeze lifted'); reload() }
                catch (e: any) { toast.error(e.message) }
              }}>Lift</Button>
            ) : null
          },
          { key: 'member', label: 'Member', render: (r: any) => `${r.member?.firstName} ${r.member?.lastName || ''}` },
          { key: 'freezeFrom', label: 'From', render: (r: any) => fmtDateStr(r.freezeFrom) },
          { key: 'freezeTo', label: 'To', render: (r: any) => fmtDateStr(r.freezeTo) },
          { key: 'days', label: 'Days', align: 'right' },
          { key: 'reason', label: 'Reason' },
          { key: 'status', label: 'Status', render: (r: any) => <StatusBadge status={r.status} /> },
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
            <FormRow label="WhatsApp"><Input value={form.whatsapp || ''} onChange={e => setForm({ ...form, whatsapp: e.target.value })} /></FormRow>
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
export function LeavesModule({ presetStatus }: { presetStatus?: string } = {}) {
  const { has } = useApp()
  const [status, setStatus] = useState(presetStatus || 'all')
  const [open, setOpen] = useState(false)
  const [form, setForm] = useState<any>({})
  const { data, reload } = useFetch<any>(`/api/leaves?status=${status !== 'all' ? status : ''}`)
  const { data: staffData } = useFetch<any>('/api/staff')
  const leaves = data?.leaves || []
  return (
    <div>
      <PageHeader title={presetStatus === 'Pending' ? 'Leave Approval' : 'Leaves'} action={has('leaves.add') && !presetStatus ? () => { setForm({}); setOpen(true) } : undefined} actionLabel="Apply Leave" />
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
          { key: 'actions', label: 'Actions', sticky: true, render: (r: any) => r.status === 'Pending' && has('leaves.approve') && (
            <div className="flex gap-1">
              <Button size="sm" variant="outline" onClick={async (e) => { e.stopPropagation(); await apiPatch('/api/leaves', { id: r.id, status: 'Approved' }); toast.success('Approved'); reload() }}>Approve</Button>
              <Button size="sm" variant="ghost" onClick={async (e) => { e.stopPropagation(); await apiPatch('/api/leaves', { id: r.id, status: 'Rejected' }); toast.success('Rejected'); reload() }}>Reject</Button>
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
      <Modal open={open} onClose={() => setOpen(false)} title="Apply Leave"
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={async () => {
            try { await apiPost('/api/leaves', form); toast.success('Leave applied'); setOpen(false); reload() }
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
export function RolesModule({ presetTab }: { presetTab?: 'permissions' | 'roles' } = {}) {
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
      <PageHeader title={presetTab === 'permissions' ? 'Permissions' : 'Roles & Permissions'} />
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
        <div className="flex items-center gap-2">
          <Label className="text-xs">Branch (blank = global default)</Label>
          <Select value={branchId || '__global__'} onValueChange={(v) => setBranchId(v === '__global__' ? '' : v)}>
            <SelectTrigger className="w-64"><SelectValue placeholder="Global default" /></SelectTrigger>
            <SelectContent>
              <SelectItem value="__global__">Global default</SelectItem>
              {branches.map((b: any) => <SelectItem key={b.id} value={b.id}>{b.name}</SelectItem>)}
            </SelectContent>
          </Select>
        </div>
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
export function FinanceReportsModule({ presetReport }: { presetReport?: 'aging' | 'finance' } = {}) {
  const [reportKey, setReportKey] = useState('')
  const [filters, setFilters] = useState<any>({ from: '', to: '', asOf: '' })
  const [reportData, setReportData] = useState<any>(null)
  const [loading, setLoading] = useState(false)
  // Aging reports (Customer aging / Vendor aging) — separate from the main Finance Reports list
  const AGING_REPORTS = [
    { key: 'customer-aging', name: 'Customer Aging', filters: ['asOf'] },
    { key: 'vendor-aging', name: 'Vendor Aging', filters: ['asOf'] },
  ]
  const FINANCE_REPORTS = [
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
  const REPORTS = presetReport === 'aging' ? AGING_REPORTS : FINANCE_REPORTS
  const pageTitle = presetReport === 'aging' ? 'Aging Reports' : 'Finance Reports'

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
      <PageHeader title={pageTitle} />
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
  const { data: categoriesData } = useFetch<any>('/api/master-files?type=ExerciseCategories')
  const exercises = data?.exercises || []
  const categories = (categoriesData?.records || []).filter((c: any) => c.isActive)
  // Look up category name from master file by id (if stored as id) — but Exercise.category stores the name text per existing schema
  const categoryName = (cat: string) => {
    if (!cat) return '—'
    const found = categories.find((c: any) => c.id === cat || c.name === cat)
    return found?.name || cat
  }
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
          { key: 'category', label: 'Category', render: (r: any) => categoryName(r.category) },
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
          <FormRow label="Category" required>
            <Select value={form.categoryId || '__none__'} onValueChange={v => {
              const cat = categories.find((c: any) => c.id === v)
              setForm({ ...form, categoryId: v === '__none__' ? '' : v, category: cat?.name || '' })
            }}>
              <SelectTrigger><SelectValue placeholder="Select category" /></SelectTrigger>
              <SelectContent>
                <SelectItem value="__none__">—</SelectItem>
                {categories.length === 0 && <SelectItem value="__none__" disabled>No categories — add in Master Files</SelectItem>}
                {categories.map((c: any) => <SelectItem key={c.id} value={c.id}>{c.name}</SelectItem>)}
              </SelectContent>
            </Select>
          </FormRow>
          <FormRow label="Muscle Group"><Input value={form.muscleGroup || ''} onChange={e => setForm({ ...form, muscleGroup: e.target.value })} /></FormRow>
          <FormRow label="Equipment"><Input value={form.equipment || ''} onChange={e => setForm({ ...form, equipment: e.target.value })} /></FormRow>
          <FormRow label="Sets"><Input type="number" value={form.sets || ''} onChange={e => setForm({ ...form, sets: e.target.value })} /></FormRow>
          <FormRow label="Reps"><Input value={form.reps || ''} onChange={e => setForm({ ...form, reps: e.target.value })} placeholder="8-12" /></FormRow>
          <FormRow label="Duration"><Input value={form.duration || ''} onChange={e => setForm({ ...form, duration: e.target.value })} placeholder="30 sec" /></FormRow>
          <FormRow label="Rest"><Input value={form.rest || ''} onChange={e => setForm({ ...form, rest: e.target.value })} placeholder="60 sec" /></FormRow>
          <div className="col-span-2"><FormRow label="Instructions"><Textarea rows={2} value={form.instructions || ''} onChange={e => setForm({ ...form, instructions: e.target.value })} /></FormRow></div>
        </div>
        <div className="mt-3 text-xs text-muted-foreground">Categories are managed via Master Files → Exercise Categories.</div>
      </Modal>
    </div>
  )
}

// =================================================================
// WORKOUTS — multi-day, multi-exercise editor
// =================================================================
const DOW = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']

export function WorkoutsModule() {
  const { has } = useApp()
  const [open, setOpen] = useState(false)
  const [editing, setEditing] = useState<any>(null)
  const [deleteTarget, setDeleteTarget] = useState<any>(null)
  const [form, setForm] = useState<any>({ name: '', description: '', days: [] })
  const { data, reload } = useFetch<any>('/api/workouts')
  const { data: exercisesData } = useFetch<any>('/api/exercises')
  const plans = data?.plans || []
  const exercises = (exercisesData?.exercises || []).filter((e: any) => e.status === 'Active')

  const openAdd = () => {
    setEditing(null)
    setForm({ name: '', description: '', days: [] })
    setOpen(true)
  }
  const openEdit = (p: any) => {
    setEditing(p)
    setForm({
      name: p.name,
      description: p.description || '',
      days: (p.days || []).map((d: any) => ({
        dayName: d.dayName,
        notes: d.notes || '',
        exercises: (d.exercises || []).map((e: any) => ({
          exerciseId: e.exerciseId,
          exerciseName: e.exercise?.name || '',
          sets: e.sets,
          reps: e.reps,
        })),
      })),
    })
    setOpen(true)
  }

  const addDay = () => setForm((f: any) => ({ ...f, days: [...f.days, { dayName: 'Monday', notes: '', exercises: [] }] }))
  const removeDay = (i: number) => setForm((f: any) => ({ ...f, days: f.days.filter((_: any, idx: number) => idx !== i) }))
  const setDay = (i: number, patch: any) => setForm((f: any) => ({ ...f, days: f.days.map((d: any, idx: number) => idx === i ? { ...d, ...patch } : d) }))
  const addExercise = (di: number, exerciseId: string) => {
    if (!exerciseId) return
    const ex = exercises.find((e: any) => e.id === exerciseId)
    setForm((f: any) => ({
      ...f,
      days: f.days.map((d: any, idx: number) => {
        if (idx !== di) return d
        // prevent duplicates
        if (d.exercises.some((e: any) => e.exerciseId === exerciseId)) {
          toast.error('This exercise is already added to this day')
          return d
        }
        return { ...d, exercises: [...d.exercises, { exerciseId, exerciseName: ex?.name || '', sets: '', reps: '' }] }
      }),
    }))
  }
  const removeExercise = (di: number, ei: number) => setForm((f: any) => ({
    ...f,
    days: f.days.map((d: any, idx: number) => idx === di ? { ...d, exercises: d.exercises.filter((_: any, j: number) => j !== ei) } : d),
  }))

  const save = async () => {
    if (!form.name?.trim()) { toast.error('Plan name is required'); return }
    if (form.days.length === 0) { toast.error('At least one day is required'); return }
    for (const d of form.days) {
      if (!d.exercises || d.exercises.length === 0) {
        toast.error(`Day "${d.dayName}" must have at least one exercise`)
        return
      }
    }
    try {
      const payload = {
        name: form.name,
        description: form.description,
        days: form.days.map((d: any) => ({
          dayName: d.dayName,
          notes: d.notes,
          exercises: d.exercises.map((e: any) => ({ exerciseId: e.exerciseId, sets: e.sets, reps: e.reps })),
        })),
      }
      if (editing) {
        await apiPatch(`/api/workouts/${editing.id}`, payload)
        toast.success('Workout plan updated')
      } else {
        await apiPost('/api/workouts', payload)
        toast.success('Workout plan created')
      }
      setOpen(false); reload()
    } catch (e: any) { toast.error(e.message) }
  }

  const doDelete = async () => {
    if (!deleteTarget) return
    try {
      await apiDelete(`/api/workouts/${deleteTarget.id}`)
      toast.success('Plan deleted'); setDeleteTarget(null); reload()
    } catch (e: any) { toast.error(e.message); setDeleteTarget(null) }
  }

  return (
    <div>
      <PageHeader title="Workout Plans"
        action={has('workouts.add') ? openAdd : undefined}
        actionLabel="Add Plan" />
      <Toolbar><Button variant="ghost" size="sm" onClick={reload}>Refresh</Button></Toolbar>
      <DataTable
        columns={[
          { key: 'actions', label: 'Actions', sticky: true, render: (r: any) => (
            <div className="flex gap-0.5">
              {has('workouts.edit') && <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); openEdit(r) }} title="Edit"><Edit className="h-3.5 w-3.5" /></Button>}
              {has('workouts.delete') && <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); setDeleteTarget(r) }} title="Delete"><Trash2 className="h-3.5 w-3.5 text-red-600" /></Button>}
            </div>
          ) },
          { key: 'name', label: 'Name' },
          { key: 'description', label: 'Description' },
          { key: 'days', label: 'Days', align: 'right', render: (r: any) => r.days?.length || 0 },
          { key: 'daySummary', label: 'Day Summary', render: (r: any) => (r.days || []).map((d: any) => `${d.dayName} (${d.exercises?.length || 0})`).join(', ') || '—' },
          { key: 'isActive', label: 'Status', render: (r: any) => <StatusBadge status={r.isActive ? 'Active' : 'Inactive'} /> },
        ]}
        rows={plans}
      />
      <Modal open={open} onClose={() => setOpen(false)} title={editing ? `Edit Plan: ${editing.name}` : 'Add Workout Plan'} size="xl"
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={save}><Save className="h-4 w-4 mr-1" />{editing ? 'Update' : 'Save'}</Button>
        </>}>
        <div className="grid grid-cols-2 gap-3 mb-4">
          <FormRow label="Plan Name" required><Input value={form.name || ''} onChange={e => setForm({ ...form, name: e.target.value })} /></FormRow>
          <FormRow label="Description"><Input value={form.description || ''} onChange={e => setForm({ ...form, description: e.target.value })} /></FormRow>
        </div>
        <div className="space-y-3 max-h-[55vh] overflow-y-auto">
          {form.days.map((d: any, di: number) => (
            <div key={di} className="border rounded p-3 bg-muted/20">
              <div className="flex items-center gap-2 mb-2">
                <Select value={d.dayName} onValueChange={v => setDay(di, { dayName: v })}>
                  <SelectTrigger className="w-40"><SelectValue /></SelectTrigger>
                  <SelectContent>{DOW.map(day => <SelectItem key={day} value={day}>{day}</SelectItem>)}</SelectContent>
                </Select>
                <Input value={d.notes || ''} onChange={e => setDay(di, { notes: e.target.value })} placeholder="Day title (e.g. Chest Day, Leg Day)" className="flex-1" />
                <Button size="sm" variant="ghost" onClick={() => removeDay(di)}><Trash2 className="h-4 w-4 text-red-600" /></Button>
              </div>
              <div className="text-xs text-muted-foreground mb-2">Exercises ({d.exercises.length}):</div>
              <div className="space-y-1 mb-2">
                {d.exercises.map((e: any, ei: number) => (
                  <div key={ei} className="flex items-center gap-2 text-sm bg-background border rounded px-2 py-1">
                    <span className="flex-1">{e.exerciseName}</span>
                    <Input type="number" value={e.sets || ''} onChange={ev => setDay(di, { exercises: d.exercises.map((ex: any, j: number) => j === ei ? { ...ex, sets: ev.target.value } : ex) })} placeholder="Sets" className="w-16 h-7" />
                    <Input value={e.reps || ''} onChange={ev => setDay(di, { exercises: d.exercises.map((ex: any, j: number) => j === ei ? { ...ex, reps: ev.target.value } : ex) })} placeholder="Reps" className="w-20 h-7" />
                    <Button size="sm" variant="ghost" onClick={() => removeExercise(di, ei)}><X className="h-3 w-3" /></Button>
                  </div>
                ))}
                {d.exercises.length === 0 && <div className="text-xs text-muted-foreground italic">No exercises yet. Add at least one.</div>}
              </div>
              <div className="flex gap-2">
                <Select value="" onValueChange={v => addExercise(di, v)}>
                  <SelectTrigger className="w-60 h-8"><SelectValue placeholder="+ Add exercise to this day" /></SelectTrigger>
                  <SelectContent>
                    {exercises.length === 0 ? <SelectItem value="__none__" disabled>No exercises — add in Exercises master</SelectItem> :
                      exercises.map((e: any) => <SelectItem key={e.id} value={e.id}>{e.code} — {e.name}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            </div>
          ))}
          {form.days.length === 0 && <div className="text-center text-muted-foreground py-4 text-sm">No days configured. Click "Add Day" to start.</div>}
        </div>
        <div className="mt-3">
          <Button size="sm" variant="outline" onClick={addDay}><Plus className="h-3 w-3 mr-1" />Add Day</Button>
        </div>
      </Modal>
      <ConfirmModal open={!!deleteTarget} onClose={() => setDeleteTarget(null)} onConfirm={doDelete} title="Delete Workout Plan" message={deleteTarget ? `Delete workout plan "${deleteTarget.name}"? This cannot be undone.` : ''} />
    </div>
  )
}

// =================================================================
// DIET PLAN — weekly grid (7 days × 8 meal columns, 60 char limit)
// =================================================================
const DIET_DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday']
const DIET_MEALS = ['Breakfast', 'Brunch', 'Lunch', 'Snack', 'Dinner', 'Late Night', 'Pre Workout', 'Post Workout']
const DIET_MAX_LEN = 60

export function DietModule() {
  const { has } = useApp()
  const [open, setOpen] = useState(false)
  const [editing, setEditing] = useState<any>(null)
  const [deleteTarget, setDeleteTarget] = useState<any>(null)
  const [form, setForm] = useState<any>({ name: '', description: '', meals: {} })
  const { data, reload } = useFetch<any>('/api/diet')
  const plans = data?.plans || []

  const emptyGrid = () => {
    const g: Record<string, Record<string, string>> = {}
    for (const day of DIET_DAYS) {
      g[day] = {}
      for (const meal of DIET_MEALS) g[day][meal] = ''
    }
    return g
  }

  const openAdd = () => {
    setEditing(null)
    setForm({ name: '', description: '', meals: emptyGrid() })
    setOpen(true)
  }
  const openEdit = (p: any) => {
    setEditing(p)
    const g = emptyGrid()
    for (const m of (p.meals || [])) {
      if (g[m.dayOfWeek]) g[m.dayOfWeek][m.timing] = m.foods || ''
    }
    setForm({ name: p.name, description: p.description || '', meals: g })
    setOpen(true)
  }

  const setCell = (day: string, meal: string, val: string) => {
    if (val.length > DIET_MAX_LEN) {
      toast.error(`Maximum ${DIET_MAX_LEN} characters per cell`)
      val = val.slice(0, DIET_MAX_LEN)
    }
    setForm((f: any) => ({ ...f, meals: { ...f.meals, [day]: { ...f.meals[day], [meal]: val } } }))
  }

  const save = async () => {
    if (!form.name?.trim()) { toast.error('Plan name is required'); return }
    // Convert grid to flat meal array (only non-empty cells)
    const meals: any[] = []
    for (const day of DIET_DAYS) {
      for (const meal of DIET_MEALS) {
        const val = (form.meals[day]?.[meal] || '').trim()
        if (val) {
          if (val.length > DIET_MAX_LEN) { toast.error(`${day} / ${meal} exceeds ${DIET_MAX_LEN} characters`); return }
          meals.push({ dayOfWeek: day, timing: meal, foods: val })
        }
      }
    }
    try {
      const payload = { name: form.name, description: form.description, meals }
      if (editing) {
        await apiPatch(`/api/diet/${editing.id}`, payload)
        toast.success('Diet plan updated')
      } else {
        await apiPost('/api/diet', payload)
        toast.success('Diet plan created')
      }
      setOpen(false); reload()
    } catch (e: any) { toast.error(e.message) }
  }

  const doDelete = async () => {
    if (!deleteTarget) return
    try {
      await apiDelete(`/api/diet/${deleteTarget.id}`)
      toast.success('Diet plan deleted'); setDeleteTarget(null); reload()
    } catch (e: any) { toast.error(e.message); setDeleteTarget(null) }
  }

  return (
    <div>
      <PageHeader title="Diet Plans"
        action={has('diet.add') ? openAdd : undefined}
        actionLabel="Add Plan" />
      <Toolbar><Button variant="ghost" size="sm" onClick={reload}>Refresh</Button></Toolbar>
      <DataTable
        columns={[
          { key: 'actions', label: 'Actions', sticky: true, render: (r: any) => (
            <div className="flex gap-0.5">
              {has('diet.edit') && <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); openEdit(r) }} title="Edit"><Edit className="h-3.5 w-3.5" /></Button>}
              {has('diet.delete') && <Button size="sm" variant="ghost" onClick={(e) => { e.stopPropagation(); setDeleteTarget(r) }} title="Delete"><Trash2 className="h-3.5 w-3.5 text-red-600" /></Button>}
            </div>
          ) },
          { key: 'name', label: 'Name' },
          { key: 'description', label: 'Description' },
          { key: 'meals', label: 'Filled Cells', align: 'right', render: (r: any) => (r.meals || []).filter((m: any) => m.foods).length },
          { key: 'isActive', label: 'Status', render: (r: any) => <StatusBadge status={r.isActive ? 'Active' : 'Inactive'} /> },
        ]}
        rows={plans}
      />
      <Modal open={open} onClose={() => setOpen(false)} title={editing ? `Edit Diet Plan: ${editing.name}` : 'Add Diet Plan'} size="xl"
        footer={<>
          <Button variant="outline" onClick={() => setOpen(false)}>Cancel</Button>
          <Button onClick={save}><Save className="h-4 w-4 mr-1" />{editing ? 'Update' : 'Save'}</Button>
        </>}>
        <div className="grid grid-cols-2 gap-3 mb-4">
          <FormRow label="Plan Name" required><Input value={form.name || ''} onChange={e => setForm({ ...form, name: e.target.value })} /></FormRow>
          <FormRow label="Description"><Input value={form.description || ''} onChange={e => setForm({ ...form, description: e.target.value })} /></FormRow>
        </div>
        <div className="text-xs text-muted-foreground mb-2">Weekly diet grid — each cell max {DIET_MAX_LEN} characters. Empty cells are allowed.</div>
        <div className="overflow-x-auto max-h-[55vh] overflow-y-auto border rounded">
          <table className="w-full text-xs">
            <thead className="bg-muted/50 border-b sticky top-0">
              <tr>
                <th className="px-2 py-2 text-left font-medium text-nowrap">Day</th>
                {DIET_MEALS.map(m => <th key={m} className="px-2 py-2 text-left font-medium text-nowrap min-w-[120px]">{m}</th>)}
              </tr>
            </thead>
            <tbody>
              {DIET_DAYS.map(day => (
                <tr key={day} className="border-b last:border-0">
                  <td className="px-2 py-1.5 font-medium text-nowrap bg-muted/20">{day}</td>
                  {DIET_MEALS.map(meal => (
                    <td key={meal} className="px-1 py-1">
                      <textarea
                        value={form.meals?.[day]?.[meal] || ''}
                        onChange={e => setCell(day, meal, e.target.value)}
                        maxLength={DIET_MAX_LEN}
                        rows={2}
                        className="w-full text-xs border rounded px-1 py-0.5 resize-none"
                        placeholder="—"
                      />
                      <div className="text-[10px] text-muted-foreground text-right">{(form.meals?.[day]?.[meal] || '').length}/{DIET_MAX_LEN}</div>
                    </td>
                  ))}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </Modal>
      <ConfirmModal open={!!deleteTarget} onClose={() => setDeleteTarget(null)} onConfirm={doDelete} title="Delete Diet Plan" message={deleteTarget ? `Delete diet plan "${deleteTarget.name}"? This cannot be undone.` : ''} />
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
