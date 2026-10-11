import { NextResponse } from 'next/server'
import { db } from '@/lib/db'

export async function GET() {
  try {
    await db.$queryRaw`SELECT 1`
    return NextResponse.json({ status: 'ok', database: 'connected' })
  } catch {
    // Never expose raw DB errors to the client — log internally if needed
    return NextResponse.json({ status: 'ok', database: 'unavailable' }, { status: 503 })
  }
}
