import bcrypt from 'bcryptjs'

const COST = 10

export function hashPassword(plain: string): string {
  return bcrypt.hashSync(plain, COST)
}

export function comparePassword(plain: string, hash: string): boolean {
  if (!hash) return false
  try {
    return bcrypt.compareSync(plain, hash)
  } catch {
    return false
  }
}
