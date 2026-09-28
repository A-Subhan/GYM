import { db } from './db'

// =================================================================
// Business ID generation — atomic, per-branch, per-period sequences
//
// Formats (client-confirmed):
//   Book vouchers : {CRV|CPV|BRV|BPV|JV|OTV}/{branchCode}/{MMMyy}/{000001}
//   Reversal      : append -R  ->  CRV/MAIN/Sep25/000001-R
//   Knock-off Bill: OTB-{branchCode}/{0000001}
//   Members etc.  : {branchCode}/{MMMyy}/{00001}
//   Prospects     : p-00001
//   Follow-ups    : f-000001
//   Workout plans : WO-00001
//   Diet plans    : DP-00001
//   Leaves        : LV-0001
//   Memberships   : MP-0001 (plans), fees {branchCode}/{MMMyy}/{00001}
// =================================================================

export const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'] as const

export function mmmYY(d: Date = new Date()): string {
  return `${MONTHS[d.getMonth()]}${String(d.getFullYear()).slice(-2)}`
}

export function pad(n: number, width: number): string {
  return String(n).padStart(width, '0')
}

/**
 * Atomically reserves the next number for a sequence key.
 * Creates the key on first use (starting at 1).
 * Runs as its own transaction so concurrent callers serialize on the row.
 */
export async function nextSequence(key: string): Promise<number> {
  return reserve(key)
}

export async function peekSequence(key: string): Promise<number> {
  const row = await db.idSequence.findUnique({ where: { key } })
  return row?.next ?? 1
}

/** Reserve next number for a composite key and return it (1-based). */
async function reserve(key: string): Promise<number> {
  const row = await db.$transaction(async (tx) => {
    const existing = await tx.idSequence.findUnique({ where: { key } })
    if (existing) return tx.idSequence.update({ where: { key }, data: { next: { increment: 1 } } })
    return tx.idSequence.create({ data: { key, next: 2 } })
  })
  return row.next - 1
}

// --- Book voucher ids -------------------------------------------------

export type BookVoucherPrefix = 'CRV' | 'CPV' | 'BRV' | 'BPV' | 'JV' | 'OTV'

/** e.g. makeBookVoucherId('CRV', 'MAIN', new Date()) -> CRV/MAIN/Sep25/000001 */
export async function makeBookVoucherId(prefix: BookVoucherPrefix, branchCode: string, date: Date): Promise<string> {
  const key = `${prefix}/${branchCode}/${mmmYY(date)}`
  const seq = await reserve(key)
  return `${key}/${pad(seq, 6)}`
}

/** Knock-off bill id: OTB-{branch}/{0000001} */
export async function makeKnockOffBillId(branchCode: string): Promise<string> {
  const key = `KOFF/${branchCode}`
  const seq = await reserve(key)
  return `OTB-${branchCode}/${pad(seq, 7)}`
}

// --- Business ids ------------------------------------------------------

/** {branchCode}/{MMMyy}/{00001} — members, fees, invoices, etc. */
export async function makeBranchPeriodId(entity: string, branchCode: string, date: Date, width = 5): Promise<string> {
  const key = `${entity}/${branchCode}/${mmmYY(date)}`
  const seq = await reserve(key)
  return `${branchCode}/${mmmYY(date)}/${pad(seq, width)}`
}

/** p-00001 */
export async function makeProspectId(): Promise<string> {
  const seq = await reserve('PROSPECT')
  return `p-${pad(seq, 5)}`
}

/** f-000001 */
export async function makeFollowUpId(): Promise<string> {
  const seq = await reserve('FOLLOWUP')
  return `f-${pad(seq, 6)}`
}

/** WO-00001 */
export async function makeWorkoutPlanId(): Promise<string> {
  const seq = await reserve('WORKOUTPLAN')
  return `WO-${pad(seq, 5)}`
}

/** DP-00001 */
export async function makeDietPlanId(): Promise<string> {
  const seq = await reserve('DIETPLAN')
  return `DP-${pad(seq, 5)}`
}

/** LV-0001 */
export async function makeLeaveId(): Promise<string> {
  const seq = await reserve('LEAVE')
  return `LV-${pad(seq, 4)}`
}

/** MP-0001 (membership plans) */
export async function makeMembershipPlanId(): Promise<string> {
  const seq = await reserve('MEMBERSHIPPLAN')
  return `MP-${pad(seq, 4)}`
}

/** PT-00001 (personal training sessions) */
export async function makePtSessionId(): Promise<string> {
  const seq = await reserve('PTSESSION')
  return `PT-${pad(seq, 5)}`
}

/** FRZ-0001 (membership freezes) */
export async function makeFreezeId(): Promise<string> {
  const seq = await reserve('FREEZE')
  return `FRZ-${pad(seq, 4)}`
}

/** EQ-00001 (equipment) */
export async function makeEquipmentId(): Promise<string> {
  const seq = await reserve('EQUIPMENT')
  return `EQ-${pad(seq, 5)}`
}

/** POS/{branchCode}/{MMMyy}/{00001} */
export async function makePosSaleId(branchCode: string, date: Date): Promise<string> {
  const key = `POS/${branchCode}/${mmmYY(date)}`
  const seq = await reserve(key)
  return `POS/${branchCode}/${mmmYY(date)}/${pad(seq, 5)}`
}

/** PAY/{branchCode}/{MMMyy}/{00001} (payroll runs) */
export async function makePayrollId(branchCode: string, date: Date): Promise<string> {
  const key = `PAY/${branchCode}/${mmmYY(date)}`
  const seq = await reserve(key)
  return `PAY/${branchCode}/${mmmYY(date)}/${pad(seq, 5)}`
}
