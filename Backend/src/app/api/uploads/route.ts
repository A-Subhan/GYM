import { NextRequest, NextResponse } from 'next/server'
import { getSession } from '@/lib/auth'
import { writeFile, mkdir } from 'fs/promises'
import path from 'path'
import { randomUUID } from 'crypto'

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const formData = await req.formData()
  const file = formData.get('file') as File | null
  if (!file) return NextResponse.json({ error: 'No file uploaded' }, { status: 400 })

  // Validate file type (SVG added for company logos / icons)
  const allowedTypes = ['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/svg+xml']
  if (!allowedTypes.includes(file.type)) {
    return NextResponse.json({ error: 'Only JPG, PNG, WebP, GIF, SVG images allowed' }, { status: 400 })
  }
  // Max 5MB (company logo enforces 2MB in the company PATCH route)
  if (file.size > 5 * 1024 * 1024) {
    return NextResponse.json({ error: 'File too large (max 5MB)' }, { status: 400 })
  }

  // For SVG, use .svg extension; otherwise use the original extension
  let ext: string
  if (file.type === 'image/svg+xml') {
    ext = 'svg'
  } else {
    ext = file.name.split('.').pop()?.toLowerCase() || 'jpg'
  }
  const filename = `${randomUUID()}.${ext}`
  const uploadDir = path.join(process.cwd(), 'public', 'uploads')
  await mkdir(uploadDir, { recursive: true })
  const filepath = path.join(uploadDir, filename)
  const bytes = await file.arrayBuffer()
  await writeFile(filepath, Buffer.from(bytes))

  // Return URL path that works in Next.js dev + production
  const url = `/uploads/${filename}`
  return NextResponse.json({ url, filename })
}
