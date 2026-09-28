import { NextRequest, NextResponse } from 'next/server'
import { db } from '@/lib/db'
import { getSession } from '@/lib/auth'

export async function GET(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })
  const url = new URL(req.url)
  const memberId = url.searchParams.get('memberId')
  const records = await db.personalTrainingSession.findMany({
    where: { ...(memberId ? { memberId } : {}), member: { isDeleted: false } },
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
  if (!data.memberId || !data.trainerId) {
    return NextResponse.json({ error: 'Member and trainer are required' }, { status: 400 })
  }
  const member = await db.member.findFirst({ where: { id: data.memberId, isDeleted: false } })
  if (!member) return NextResponse.json({ error: 'Member not found' }, { status: 404 })
  const purchased = Math.max(0, Number(data.sessionsPurchased) || 0)
  const used = Math.max(0, Number(data.sessionsUsed) || 0)
  const record = await db.personalTrainingSession.create({
    data: {
      memberId: data.memberId,
      trainerId: data.trainerId,
      branchId: data.branchId || member.branchId,
      sessionsPurchased: purchased,
      sessionsUsed: used,
      sessionsRemaining: data.sessionsRemaining !== undefined ? Math.max(0, Number(data.sessionsRemaining) || 0) : purchased - used,
      sessionDate: data.sessionDate ? new Date(data.sessionDate) : null,
      sessionStatus: data.sessionStatus || 'Scheduled',
      startDate: data.startDate ? new Date(data.startDate) : null,
      endDate: data.endDate ? new Date(data.endDate) : null,
      notes: data.notes || null,
    },
    include: { member: true },
  })
  return NextResponse.json({ record })
}
