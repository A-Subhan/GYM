import { NextResponse } from 'next/server'
import { db } from '@/lib/db'

export async function GET() {
  try {
    await db.$queryRaw`SELECT 1`
    return NextResponse.json({ status: 'ok', database: 'connected (SQL Server GymDB)' })
  } catch (e: any) {
    return NextResponse.json({ status: 'ok', database: 'error: ' + String(e?.message || e) }, { status: 500 })
  }
}
