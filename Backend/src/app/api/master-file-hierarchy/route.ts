import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

/**
 * Master File hierarchy API — serves the three IDENTICAL master/detail pairs:
 *   type=gym     -> gymmaster      / gymmasterdetail       (Gym module)
 *   type=finance -> financemaster  / financemasterdetail   (Finance module)
 *   type=payroll -> payrollmaster  / payrollmasterdetail   (HR & Payroll module)
 *
 * master.id  = 3-digit category code ('001' Exercises, '002' Equipment, ...)
 * detail.id  = master code + 3-digit sequence ('0010001' Bench Press)
 */

type Kind = 'gym' | 'finance' | 'payroll'

const KINDS: Record<Kind, { master: string; detail: string; label: string }> = {
  gym: { master: 'gymMaster', detail: 'gymMasterDetail', label: 'Gym Master' },
  finance: { master: 'financeMaster', detail: 'financeMasterDetail', label: 'Finance Master' },
  payroll: { master: 'payrollMaster', detail: 'payrollMasterDetail', label: 'Payroll Master' },
}

function models(kind: Kind) {
  const cfg = KINDS[kind]
  return {
    master: (db as any)[cfg.master],
    detail: (db as any)[cfg.detail],
    label: cfg.label,
  }
}

function parseKind(url: URL): Kind | null {
  const t = (url.searchParams.get('type') || '').toLowerCase()
  return t === 'gym' || t === 'finance' || t === 'payroll' ? (t as Kind) : null
}

function kindFromBody(body: any): Kind | null {
  const t = String(body?.type || '').toLowerCase()
  return t === 'gym' || t === 'finance' || t === 'payroll' ? (t as Kind) : null
}

// GET ?type=gym                     -> all masters with their details
// GET ?type=gym&masterId=001        -> one master + its details
export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const kind = parseKind(url)
  if (!kind) return NextResponse.json({ error: 'type must be gym, finance, or payroll' }, { status: 400 })
  const { master, detail } = models(kind)

  const masterId = url.searchParams.get('masterId')
  const masters = await master.findMany({
    where: masterId ? { id: masterId } : {},
    orderBy: { id: 'asc' },
  })
  const details = await detail.findMany({
    where: masterId ? { masterId } : {},
    include: { branch: { select: { id: true, name: true, code: true } } },
    orderBy: { id: 'asc' },
  })
  const byMaster = new Map<string, any[]>()
  for (const d of details) {
    if (!byMaster.has(d.masterId)) byMaster.set(d.masterId, [])
    byMaster.get(d.masterId)!.push(d)
  }
  return NextResponse.json({
    masters: masters.map((m: any) => ({ ...m, details: byMaster.get(m.id) || [] })),
    details,
  })
}

// POST — create a category (master) or an item (detail)
//   { type, name, description?, branchId?, isActive? }              -> master (code auto '004')
//   { type, masterId, name, description?, branchId?, isActive? }    -> detail (code auto '0040001')
export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('masters.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const body = await req.json()
  const kind = kindFromBody(body)
  if (!kind) return NextResponse.json({ error: 'type must be gym, finance, or payroll' }, { status: 400 })
  const { master, detail, label } = models(kind)
  const name = String(body.name || '').trim()
  if (!name) return NextResponse.json({ error: 'Name is required' }, { status: 400 })
  const data: any = {
    name,
    description: body.description || null,
    branchId: body.branchId || null,
    isActive: body.isActive !== false,
  }

  // --- detail item under a category ---
  if (body.masterId) {
    const parent = await master.findUnique({ where: { id: body.masterId } })
    if (!parent) return NextResponse.json({ error: `${label} category not found` }, { status: 404 })
    const siblings = await detail.findMany({ where: { masterId: body.masterId }, select: { id: true } })
    let max = 0
    for (const s of siblings) {
      if (s.id.startsWith(parent.id)) {
        const suffix = s.id.slice(parent.id.length)
        if (/^\d{1,3}$/.test(suffix)) max = Math.max(max, parseInt(suffix, 10))
      }
    }
    const id = `${parent.id}${String(max + 1).padStart(3, '0')}`
    try {
      const record = await detail.create({ data: { id, masterId: parent.id, ...data } })
      await db.auditLog.create({
        data: { userId: session.id, action: 'CREATE', module: 'masters', details: JSON.stringify({ kind, id: record.id, name }) },
      })
      return NextResponse.json({ record })
    } catch (e: any) {
      if (e?.code === 'P2002') return NextResponse.json({ error: `Item code ${id} already exists` }, { status: 400 })
      throw e
    }
  }

  // --- master category ---
  const existing = await master.findMany({ select: { id: true } })
  let max = 0
  for (const m of existing) {
    if (/^\d{1,3}$/.test(m.id)) max = Math.max(max, parseInt(m.id, 10))
  }
  const id = String(max + 1).padStart(3, '0')
  try {
    const record = await master.create({ data: { id, ...data } })
    await db.auditLog.create({
      data: { userId: session.id, action: 'CREATE', module: 'masters', details: JSON.stringify({ kind, id: record.id, name }) },
    })
    return NextResponse.json({ record })
  } catch (e: any) {
    if (e?.code === 'P2002') return NextResponse.json({ error: `Category code ${id} already exists` }, { status: 400 })
    throw e
  }
}

// PATCH — { type, id, moveMasterId? (move item to another category), name?, description?, branchId?, isActive? }
export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('masters.edit')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const body = await req.json()
  const kind = kindFromBody(body)
  if (!kind) return NextResponse.json({ error: 'type must be gym, finance, or payroll' }, { status: 400 })
  if (!body.id) return NextResponse.json({ error: 'id required' }, { status: 400 })
  const { master, detail, label } = models(kind)

  const patch: any = {}
  if (body.name !== undefined) {
    if (!String(body.name).trim()) return NextResponse.json({ error: 'Name cannot be empty' }, { status: 400 })
    patch.name = String(body.name).trim()
  }
  if (body.description !== undefined) patch.description = body.description || null
  if (body.branchId !== undefined) patch.branchId = body.branchId || null
  if (body.isActive !== undefined) patch.isActive = !!body.isActive

  // ids/codes are immutable; a detail item may be moved to another category
  // only via moveMasterId (its code is then regenerated under the new parent)
  if (body.moveMasterId) {
    const target = await master.findUnique({ where: { id: body.moveMasterId } })
    if (!target) return NextResponse.json({ error: `${label} category not found` }, { status: 404 })
    const siblings = await detail.findMany({ where: { masterId: body.moveMasterId }, select: { id: true } })
    let max = 0
    for (const s of siblings) {
      if (s.id.startsWith(target.id)) {
        const suffix = s.id.slice(target.id.length)
        if (/^\d{1,3}$/.test(suffix)) max = Math.max(max, parseInt(suffix, 10))
      }
    }
    const newId = `${target.id}${String(max + 1).padStart(3, '0')}`
    const existing = await detail.findUnique({ where: { id: body.id } })
    if (!existing) return NextResponse.json({ error: 'Item not found' }, { status: 404 })
    try {
      const record = await detail.update({ where: { id: body.id }, data: { ...patch, masterId: target.id, id: newId } })
      return NextResponse.json({ record })
    } catch (e: any) {
      if (e?.code === 'P2002') return NextResponse.json({ error: `Item code ${newId} already exists` }, { status: 400 })
      throw e
    }
  }

  // try detail first (detail codes are longer), then master
  const asDetail = await detail.findUnique({ where: { id: body.id } })
  if (asDetail) {
    const record = await detail.update({ where: { id: body.id }, data: patch })
    return NextResponse.json({ record })
  }
  const asMaster = await master.findUnique({ where: { id: body.id } })
  if (asMaster) {
    const record = await master.update({ where: { id: body.id }, data: patch })
    return NextResponse.json({ record })
  }
  return NextResponse.json({ error: 'Record not found' }, { status: 404 })
}

// DELETE ?type=gym&id=… — deletes a detail item; a category only when it has no items
export async function DELETE(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('masters.delete')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const url = new URL(req.url)
  const kind = parseKind(url)
  if (!kind) return NextResponse.json({ error: 'type must be gym, finance, or payroll' }, { status: 400 })
  const id = url.searchParams.get('id')
  if (!id) return NextResponse.json({ error: 'id required' }, { status: 400 })
  const { master, detail, label } = models(kind)

  const asDetail = await detail.findUnique({ where: { id } })
  if (asDetail) {
    if (kind === 'gym') {
      const used = await db.workoutDayExercise.count({ where: { exerciseId: id } })
      if (used > 0) {
        return NextResponse.json({ error: `Cannot delete — this exercise is used in ${used} workout day(s)` }, { status: 400 })
      }
    }
    await detail.delete({ where: { id } })
    await db.auditLog.create({ data: { userId: session.id, action: 'DELETE', module: 'masters', details: JSON.stringify({ kind, id }) } })
    return NextResponse.json({ success: true })
  }

  const asMaster = await master.findUnique({ where: { id }, include: { details: true } })
  if (asMaster) {
    if (asMaster.details.length > 0) {
      return NextResponse.json({ error: `Cannot delete — ${asMaster.details.length} item(s) under this ${label} category. Delete or move them first.` }, { status: 400 })
    }
    await master.delete({ where: { id } })
    await db.auditLog.create({ data: { userId: session.id, action: 'DELETE', module: 'masters', details: JSON.stringify({ kind, id }) } })
    return NextResponse.json({ success: true })
  }
  return NextResponse.json({ error: 'Record not found' }, { status: 404 })
}
