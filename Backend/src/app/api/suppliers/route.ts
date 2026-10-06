import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET() {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const records = await db.supplier.findMany({
    include: { branch: true },
    orderBy: { name: 'asc' }
  })
  return NextResponse.json({ records })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const data = await req.json()
  if (!data.name) return NextResponse.json({ error: 'Name required' }, { status: 400 })
  const count = await db.supplier.count()
  const code = `SUP-${String(count + 1).padStart(4, '0')}`
  const record = await db.supplier.create({
    data: { code, name: data.name, contactPerson: data.contactPerson, phone: data.phone, email: data.email, address: data.address, branchId: data.branchId || null, status: data.status || 'Active' }
  })
  return NextResponse.json({ record })
}
