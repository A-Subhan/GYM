import { NextRequest, NextResponse } from 'next/server'
import { getSession } from '@/lib/auth'
import { writeFile, mkdir } from 'fs/promises'
import path from 'path'
import { randomUUID } from 'crypto'

// Allowed image MIME types and their file extensions.
const ALLOWED_IMAGE_TYPES: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/gif': 'gif',
  'image/svg+xml': 'svg',
}

// Max upload size: 5 MB for general uploads, 2 MB when the caller marks the
// upload as a company logo (via the `purpose` form field or a `maxSize`
// query param). The company PATCH route also re-validates the path.
const MAX_GENERAL_BYTES = 5 * 1024 * 1024
const MAX_LOGO_BYTES = 2 * 1024 * 1024

export async function POST(req: NextRequest) {
  const session = await getSession()
  if (!session) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 })

  const formData = await req.formData()
  const file = formData.get('file') as File | null
  if (!file) return NextResponse.json({ error: 'No file uploaded' }, { status: 400 })

  // Determine the size limit — logo uploads are capped at 2 MB.
  const purpose = (formData.get('purpose') as string) || ''
  const isLogo = purpose === 'logo'
  const maxBytes = isLogo ? MAX_LOGO_BYTES : MAX_GENERAL_BYTES

  // Validate file type (server-side authoritative).
  const ext = ALLOWED_IMAGE_TYPES[file.type]
  if (!ext) {
    return NextResponse.json(
      { error: `Only JPG, PNG, WebP, GIF, SVG images allowed (got ${file.type || 'unknown type'})` },
      { status: 400 },
    )
  }

  // Validate file size (server-side authoritative).
  if (file.size > maxBytes) {
    return NextResponse.json(
      { error: `File too large (max ${isLogo ? '2' : '5'} MB; got ${(file.size / 1024 / 1024).toFixed(2)} MB)` },
      { status: 400 },
    )
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
