import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

const MASTER_TYPES = ['Education', 'Designation', 'Country', 'Department', 'Shirt', 'EmployeeType', 'LeaveType']

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const masterType = url.searchParams.get('type')
  const records = await db.payrollMasterFile.findMany({
    where: { ...(masterType ? { masterType } : {}) },
    orderBy: { code: 'asc' },
  })
  return NextResponse.json({ records, types: MASTER_TYPES })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const data = await req.json()
  if (!data.masterType || !data.name) return NextResponse.json({ error: 'masterType and name required' }, { status: 400 })
  const existing = await db.payrollMasterFile.findMany({ where: { masterType: data.masterType } })
  const codes = existing.map(r => parseInt(r.code, 10)).filter(n => !isNaN(n))
  const code = String((codes.length ? Math.max(...codes) : 0) + 1).padStart(3, '0')
  const record = await db.payrollMasterFile.create({
    data: {
      masterType: data.masterType,
      code,
      name: data.name,
      description: data.description,
      isActive: data.isActive !== false,
    },
  })
  return NextResponse.json({ record })
}

export async function PATCH(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const data = await req.json()
  if (!data.id) return NextResponse.json({ error: 'id required' }, { status: 400 })
  const record = await db.payrollMasterFile.update({
    where: { id: data.id },
    data: { name: data.name, description: data.description, isActive: data.isActive },
  })
  return NextResponse.json({ record })
}

export async function DELETE(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const id = url.searchParams.get('id')
  if (!id) return NextResponse.json({ error: 'id required' }, { status: 400 })
  await db.payrollMasterFile.delete({ where: { id } })
  return NextResponse.json({ success: true })
}
