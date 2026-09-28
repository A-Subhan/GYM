import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'
import { makeBranchId } from '@/lib/ids'

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

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  if (!session.permissions.includes('branches.add')) return NextResponse.json({ error: 'Forbidden' }, { status: 403 })

  const data = await req.json()
  if (!data.name || !String(data.name).trim()) return NextResponse.json({ error: 'Branch name required' }, { status: 400 })

  const nodeType = data.nodeType === 'Control' ? 'Control' : 'Detail'
  let parentId: string | null = null
  if (data.parentId) {
    const parent = await db.branch.findFirst({ where: { id: data.parentId, isDeleted: false } })
    if (!parent) return NextResponse.json({ error: 'Parent branch not found' }, { status: 400 })
    parentId = parent.id
  }

  // auto-generate code BR-001, BR-002, … via atomic IdSequence (client may still supply one)
  const code = data.code && String(data.code).trim() ? String(data.code).trim() : await makeBranchId()

  try {
    const branch = await db.branch.create({
      data: {
        code,
        name: String(data.name).trim(),
        parentId,
        nodeType,
        address: data.address,
        city: data.city,
        phone: data.phone,
        email: data.email,
        strn: data.strn,
        ntn: data.ntn,
        logo: data.logo,
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
