import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export type BranchNode = {
  id: string
  code: string
  name: string
  parentId: string | null
  nodeType: string
  address: string | null
  city: string | null
  phone: string | null
  email: string | null
  strn: string | null
  ntn: string | null
  logo: string | null
  isActive: boolean
  children: BranchNode[]
}

/** Build the hierarchical branch tree from the flat parentId list. */
export function buildBranchTree(flat: Omit<BranchNode, 'children'>[]): BranchNode[] {
  const byId = new Map<string, BranchNode>()
  for (const b of flat) byId.set(b.id, { ...b, children: [] })
  const roots: BranchNode[] = []
  for (const node of byId.values()) {
    const parent = node.parentId ? byId.get(node.parentId) : undefined
    if (parent) parent.children.push(node)
    else roots.push(node)
  }
  const sortRec = (nodes: BranchNode[]) => {
    nodes.sort((a, b) => a.code.localeCompare(b.code))
    nodes.forEach(n => sortRec(n.children))
  }
  sortRec(roots)
  return roots
}

export async function GET() {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const allowed = session.accessibleBranchIds === '*' ? null : session.accessibleBranchIds.split(',')
  const branches = await db.branch.findMany({
    where: {
      isDeleted: false,
      ...(allowed ? { id: { in: allowed } } : {}),
    },
    orderBy: { code: 'asc' },
  })
  // `branches` stays a flat list for existing consumers; `tree` is the hierarchy for the Branch File
  const tree = buildBranchTree(branches.map(b => ({
    id: b.id, code: b.code, name: b.name, parentId: b.parentId, nodeType: b.nodeType,
    address: b.address, city: b.city, phone: b.phone, email: b.email, strn: b.strn, ntn: b.ntn,
    logo: b.logo, isActive: b.isActive,
  })))
  return NextResponse.json({ branches, tree })
}

/**
 * Hierarchical branch code generator (like Chart of Accounts):
 *   root level   -> 2-digit code  '01', '02', ...
 *   child level  -> parent code + 3-digit sequence  '01001', '01002', ...
 * Sibling sequences are derived from the numeric suffixes already in use,
 * so legacy flat codes (BR-001, ...) do not break the generator.
 */
async function nextBranchCode(parentId: string | null, parentCode: string | null): Promise<string> {
  if (!parentId) {
    const roots = await db.branch.findMany({ where: { isDeleted: false, parentId: null }, select: { code: true } })
    let max = 0
    for (const r of roots) {
      const m = /^(\d{1,2})$/.exec(r.code)
      if (m) max = Math.max(max, parseInt(m[1], 10))
    }
    return String(max + 1).padStart(2, '0')
  }
  const children = await db.branch.findMany({ where: { isDeleted: false, parentId }, select: { code: true } })
  let max = 0
  for (const c of children) {
    if (parentCode && c.code.startsWith(parentCode)) {
      const suffix = c.code.slice(parentCode.length)
      if (/^\d{1,3}$/.test(suffix)) max = Math.max(max, parseInt(suffix, 10))
    }
  }
  return `${parentCode}${String(max + 1).padStart(3, '0')}`
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('branches.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  if (!data.name || !String(data.name).trim()) return NextResponse.json({ error: 'Branch name required' }, { status: 400 })

  const nodeType = data.nodeType === 'Control' ? 'Control' : 'Detail'
  let parentId: string | null = null
  let parentCode: string | null = null
  if (data.parentId) {
    const parent = await db.branch.findFirst({ where: { id: data.parentId, isDeleted: false } })
    if (!parent) return NextResponse.json({ error: 'Parent branch not found' }, { status: 400 })
    parentId = parent.id
    parentCode = parent.code
  }

  // Hierarchical auto code: '01' (root), '01001' (child of '01'), ...
  const code = await nextBranchCode(parentId, parentCode)

  // Control-level nodes are pure hierarchy containers — they cannot hold
  // branch detail data (address, tax numbers, logo, ...). Only detail-level
  // (branch) records can.
  const isControl = nodeType === 'Control'
  try {
    // Branch ID = Branch Code (like charts.id = account code). Pre-existing
    // rows keep their original ids; every new branch uses its code as id.
    const branch = await db.branch.create({
      data: {
        id: code,
        code,
        name: String(data.name).trim(),
        parentId,
        nodeType,
        address: isControl ? null : (data.address ?? null),
        city: isControl ? null : (data.city ?? null),
        phone: isControl ? null : (data.phone ?? null),
        email: isControl ? null : (data.email ?? null),
        strn: isControl ? null : (data.strn ?? null),
        ntn: isControl ? null : (data.ntn ?? null),
        trn: isControl ? null : (data.trn ?? null),
        fbr: isControl ? null : (data.fbr ?? null),
        logo: isControl ? null : (data.logo ?? null),
      },
    })
    await db.auditLog.create({
      data: { userId: session.id, action: 'CREATE', module: 'branches', details: JSON.stringify({ id: branch.id, code, parentId, nodeType }) },
    })
    return NextResponse.json({ branch })
  } catch (e: any) {
    if (e?.code === 'P2002') return NextResponse.json({ error: `Branch code "${code}" already exists` }, { status: 400 })
    throw e
  }
}
