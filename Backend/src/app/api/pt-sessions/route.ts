import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const memberId = url.searchParams.get('memberId')
  const records = await db.personalTrainingSession.findMany({
    where: { ...(memberId ? { memberId } : {}) },
    include: { member: true },
    orderBy: { createdAt: 'desc' },
    take: 200,
  })
  return NextResponse.json({ records })
}

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const data = await req.json()
  const record = await db.personalTrainingSession.create({ data, include: { member: true } })
  return NextResponse.json({ record })
}
