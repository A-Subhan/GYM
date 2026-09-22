// HMAC-based signed JWT-like tokens using Web Crypto (works in Edge runtime)
import { cookies } from 'next/headers'

const COOKIE_NAME = 'contoura_session'
const SECRET = process.env.JWT_SECRET || 'contoura-labs-default-secret-change-me'
const ACCESS_TTL = 60 * 60 * 8 // 8 hours

function b64url(buf: ArrayBuffer | Uint8Array): string {
  const bytes = buf instanceof Uint8Array ? buf : new Uint8Array(buf)
  let s = ''
  for (const b of bytes) s += String.fromCharCode(b)
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

function b64urlDecode(s: string): Uint8Array {
  s = s.replace(/-/g, '+').replace(/_/g, '/')
  while (s.length % 4) s += '='
  const bin = atob(s)
  const arr = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i)
  return arr
}

async function getKey(): Promise<CryptoKey> {
  const enc = new TextEncoder()
  return crypto.subtle.importKey('raw', enc.encode(SECRET), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify'])
}

export interface TokenPayload {
  userId: string
  username: string
  roleId: string
  branchId?: string | null
  accessibleBranchIds: string
  exp: number
}

export async function signToken(payload: Omit<TokenPayload, 'exp'>): Promise<string> {
  const body = { ...payload, exp: Math.floor(Date.now() / 1000) + ACCESS_TTL }
  const header = { alg: 'HS256', typ: 'JWT' }
  const headerB = b64url(new TextEncoder().encode(JSON.stringify(header)).buffer as ArrayBuffer)
  const bodyB = b64url(new TextEncoder().encode(JSON.stringify(body)).buffer as ArrayBuffer)
  const key = await getKey()
  const sig = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${headerB}.${bodyB}`))
  const sigB = b64url(sig)
  return `${headerB}.${bodyB}.${sigB}`
}

export async function verifyToken(token: string): Promise<TokenPayload | null> {
  try {
    const parts = token.split('.')
    if (parts.length !== 3) return null
    const [headerB, bodyB, sigB] = parts
    const key = await getKey()
    const ok = await crypto.subtle.verify('HMAC', key, b64urlDecode(sigB), new TextEncoder().encode(`${headerB}.${bodyB}`))
    if (!ok) return null
    const payload = JSON.parse(new TextDecoder().decode(b64urlDecode(bodyB))) as TokenPayload
    if (payload.exp && payload.exp < Math.floor(Date.now() / 1000)) return null
    return payload
  } catch {
    return null
  }
}

export async function setSessionCookie(token: string) {
  const c = await cookies()
  c.set(COOKIE_NAME, token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'lax',
    path: '/',
    maxAge: ACCESS_TTL,
  })
}

export async function clearSessionCookie() {
  const c = await cookies()
  c.delete(COOKIE_NAME)
}

export async function getSessionToken(): Promise<string | null> {
  const c = await cookies()
  return c.get(COOKIE_NAME)?.value ?? null
}

export const SESSION_COOKIE = COOKIE_NAME
