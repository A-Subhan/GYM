import { db } from './db'

// =================================================================
// Business ID generation — atomic, per-branch, per-period sequences.
//
// FINAL CONTRACT FORMATS (Database/migrations seed these exact keys):
//   Book vouchers : {CRV|CPV|BRV|BPV|JV|OTV}/{branchCode}/{MMMyy}/{000001}
//   Reversal      : append -R  ->  CRV/BR-001/SEP26/000001-R
//   Knock-off bill: OTB-{branchCode}/{0000001}          key KOFF/{branchCode}
//   Member        : {branchCode}/{MMMyy}/{00001}        key MEMBER/{branchCode}/{MMMyy}
//   Membershipplan: {branchCode}/{MMMyy}/{00001}        key PLAN/{branchCode}/{MMMyy}
//   Attendance    : {branchCode}/{MMMyy}/{00001}        key ATTENDANCE/{branchCode}/{MMMyy}
//   Prospect      : {branchCode}/p-00001                key PROSPECT/{branchCode}
//   Follow-up     : {branchCode}/fw-000001              key FOLLOWUP/{branchCode}
//   Progress entry: {branchCode}/Pg-000001              key PROGRESS/{branchCode}
//   Freeze        : f-000001                            key FREEZE
//   Workout plan  : WO-000001                           key WORKOUTPLAN
//   Diet plan     : DP-000001                           key DIETPLAN
//   Fee           : {branchCode}/{MMMyy}/{00001}        key FEE/{branchCode}/{MMMyy} *
//   Leave         : LV-0001                             key LEAVE
//   Branch        : BR-001                              key BRANCH
//   Equipment     : EQ-00001                            key EQUIPMENT
//   Employee      : EMP-00001                           key EMPLOYEE
//   PT session    : PT-00001                            key PTSESSION
//   POS sale      : POS/{branchCode}/{MMMyy}/{00001}    key POS/{branchCode}/{MMMyy}
//   Payroll run   : PAY/{branchCode}/{MMMyy}/{00001}    key PAY/{branchCode}/{MMMyy}
//
// MMMyy is UPPERCASE (SEP26) — the migration scripts seed the sequence keys
// with the uppercase form and generate ids like OTV/BR-001/SEP26/000001.
//
// * No FEE sequence key is seeded by Database/migrations (fee ids were
//   regenerated in place). makeFeeId therefore reconciles the counter with
//   the existing Fee rows for that branch/period before reserving.
// =================================================================

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'] as const

/** Uppercase month + 2-digit year, e.g. 'SEP26'. */
export function mmmYY(d: Date = new Date()): string {
  return `${MONTHS[d.getMonth()]}${String(d.getFullYear()).slice(-2)}`.toUpperCase()
}

export function pad(n: number, width: number): string {
  return String(n).padStart(width, '0')
}

/**
 * Atomically reserves the next number for a sequence key.
 * Creates the key on first use (starting at 1).
 * Runs as its own transaction so concurrent callers serialize on the row.
 * `minNext` guarantees the returned number is >= minNext (used by makeFeeId
 * to jump past ids that already exist without a seeded sequence row).
 */
export async function nextSequence(key: string, minNext = 1): Promise<number> {
  return reserve(key, minNext)
}

export async function peekSequence(key: string): Promise<number> {
  const row = await db.idSequence.findUnique({ where: { key } })
  return row?.next ?? 1
}

/** Reserve next number for a composite key and return it (1-based). */
async function reserve(key: string, minNext = 1): Promise<number> {
  const row = await db.$transaction(async (tx) => {
    const existing = await tx.idSequence.findUnique({ where: { key } })
    if (existing) {
      const target = Math.max(existing.next, minNext)
      return tx.idSequence.update({ where: { key }, data: { next: target + 1 } })
    }
    return tx.idSequence.create({ data: { key, next: minNext + 1 } })
  })
  return row.next - 1
}

// --- Book voucher ids -------------------------------------------------

export type BookVoucherPrefix = 'CRV' | 'CPV' | 'BRV' | 'BPV' | 'JV' | 'OTV'

/** e.g. makeBookVoucherId('CRV', 'BR-001', new Date()) -> CRV/BR-001/SEP26/000001 */
export async function makeBookVoucherId(prefix: BookVoucherPrefix, branchCode: string, date: Date): Promise<string> {
  const key = `${prefix}/${branchCode}/${mmmYY(date)}`
  const seq = await reserve(key)
  return `${key}/${pad(seq, 6)}`
}

// --- Book line ids --------------------------------------------------------
// Per FINANCE DB upgrade (09_upgrade_finance_hr.sql) line ids are business ids:
//   CashBookLine  C/{year}/{000001}   (C = cash payment/receipt voucher)
//   BankBookLine  B/{year}/{000001}   (B = bank payment/receipt voucher)
//   JVLine        J/{year}/{000001}
//   OpenTBLine    O/{year}/{000001}
// The sequence RESETS per year (sequence key includes the year).
export type BookLineKind = 'C' | 'B' | 'J' | 'O'

/** e.g. makeBookLineId('B', new Date()) -> B/2026/000001 */
export async function makeBookLineId(kind: BookLineKind, date: Date, client?: any): Promise<string> {
  const year = date.getFullYear()
  const key = `LINE/${kind}/${year}`
  const prefix = `${kind}/${year}/`
  // The migrations regenerated line ids in place without advancing the
  // LINE/{kind}/{year} sequence rows, so reconcile the counter with the
  // highest existing line id for this kind/year before reserving
  // (same pattern as makeFeeId/makeEmployeeId). When called inside a
  // transaction, pass that client — running the read on a separate
  // connection self-blocks on the transaction's own row locks.
  const modelName = kind === 'C' ? 'cashBookLine'
    : kind === 'B' ? 'bankBookLine'
    : kind === 'J' ? 'journalVoucherLine'
    : 'openingTbLine'
  const reader: any = client || db
  const rows = await reader[modelName].findMany({ where: { id: { startsWith: prefix } }, select: { id: true } })
  const maxSeq = rows.reduce((m: number, r: any) => {
    const n = Number(r.id.slice(prefix.length))
    return Number.isFinite(n) && n > m ? n : m
  }, 0)
  const seq = await reserve(key, maxSeq + 1)
  return `${prefix}${pad(seq, 6)}`
}

/** Knock-off bill id: OTB-{branch}/{0000001}, key KOFF/{branch} */
export async function makeKnockOffBillId(branchCode: string): Promise<string> {
  const seq = await reserve(`KOFF/${branchCode}`)
  return `OTB-${branchCode}/${pad(seq, 7)}`
}

// --- Per-branch, per-period ids -----------------------------------------

/** {branchCode}/{MMMyy}/{00001} — members (MEMBER), plans (PLAN), attendance (ATTENDANCE) */
export async function makeBranchPeriodId(entity: string, branchCode: string, date: Date, width = 5): Promise<string> {
  const key = `${entity}/${branchCode}/${mmmYY(date)}`
  const seq = await reserve(key)
  return `${branchCode}/${mmmYY(date)}/${pad(seq, width)}`
}

/**
 * Fee id {branchCode}/{MMMyy}/{00001}. The migrations regenerate fee ids but
 * do NOT seed a FEE sequence row, so the counter is reconciled with the
 * highest existing Fee id for that branch/period before reserving.
 */
export async function makeFeeId(branchCode: string, date: Date): Promise<string> {
  const mon = mmmYY(date)
  const key = `FEE/${branchCode}/${mon}`
  const prefix = `${branchCode}/${mon}/`
  const rows = await db.fee.findMany({ where: { id: { startsWith: prefix } }, select: { id: true } })
  const maxSeq = rows.reduce((m, r) => {
    const n = Number(r.id.slice(prefix.length))
    return Number.isFinite(n) && n > m ? n : m
  }, 0)
  const seq = await reserve(key, maxSeq + 1)
  return `${prefix}${pad(seq, 5)}`
}

// --- Per-branch ids ------------------------------------------------------

/** {branchCode}/p-00001, key PROSPECT/{branchCode} */
export async function makeProspectId(branchCode: string): Promise<string> {
  const seq = await reserve(`PROSPECT/${branchCode}`)
  return `${branchCode}/p-${pad(seq, 5)}`
}

/** {branchCode}/fw-000001, key FOLLOWUP/{branchCode} */
export async function makeFollowUpId(branchCode: string): Promise<string> {
  const seq = await reserve(`FOLLOWUP/${branchCode}`)
  return `${branchCode}/fw-${pad(seq, 6)}`
}

/** {branchCode}/Pg-000001, key PROGRESS/{branchCode} */
export async function makeProgressEntryId(branchCode: string): Promise<string> {
  const seq = await reserve(`PROGRESS/${branchCode}`)
  return `${branchCode}/Pg-${pad(seq, 6)}`
}

// --- Global sequence ids --------------------------------------------------

/** f-000001 (membership freeze), key FREEZE */
export async function makeFreezeId(): Promise<string> {
  const seq = await reserve('FREEZE')
  return `f-${pad(seq, 6)}`
}

/** WO-000001 (workout plans), key WORKOUTPLAN */
export async function makeWorkoutPlanId(): Promise<string> {
  const seq = await reserve('WORKOUTPLAN')
  return `WO-${pad(seq, 6)}`
}

/** DP-000001 (diet plans), key DIETPLAN */
export async function makeDietPlanId(): Promise<string> {
  const seq = await reserve('DIETPLAN')
  return `DP-${pad(seq, 6)}`
}

/** BR-001 (branch file), key BRANCH */
export async function makeBranchId(): Promise<string> {
  const seq = await reserve('BRANCH')
  return `BR-${pad(seq, 3)}`
}

/** LV-0001 (leaves), key LEAVE */
export async function makeLeaveId(): Promise<string> {
  const seq = await reserve('LEAVE')
  return `LV-${pad(seq, 4)}`
}

/**
 * EMP-00001 (staff). Since the HR DB upgrade the staff id IS the employee id,
 * so callers use this value as the Prisma `id` of the Staff row.
 * Reconciles with existing Staff rows so legacy EMP ids without a sequence
 * row never collide (same pattern as makeFeeId).
 */
export async function makeEmployeeId(): Promise<string> {
  const rows = await db.staff.findMany({ where: { id: { startsWith: 'EMP-' } }, select: { id: true } })
  const maxSeq = rows.reduce((m, r) => {
    const n = Number(r.id.slice('EMP-'.length))
    return Number.isFinite(n) && n > m ? n : m
  }, 0)
  const seq = await reserve('EMPLOYEE', maxSeq + 1)
  return `EMP-${pad(seq, 5)}`
}

/**
 * 001, 002, 003 … (shifts). Reconciles with existing Shift rows so migrated
 * numeric ids are honoured even without a seeded sequence row.
 */
export async function makeShiftId(): Promise<string> {
  const shifts = await db.shift.findMany({ select: { id: true } })
  const maxSeq = shifts.reduce((m, s) => {
    const n = Number(s.id)
    return Number.isFinite(n) && /^\d+$/.test(s.id) && n > m ? n : m
  }, 0)
  const seq = await reserve('SHIFT', maxSeq + 1)
  return pad(seq, 3)
}

/**
 * 001, 002, 003 … (calendar days). Same reconciliation pattern as shifts.
 */
export async function makeCalendarDayId(): Promise<string> {
  const days = await db.calendarDay.findMany({ select: { id: true } })
  const maxSeq = days.reduce((m, d) => {
    const n = Number(d.id)
    return Number.isFinite(n) && /^\d+$/.test(d.id) && n > m ? n : m
  }, 0)
  const seq = await reserve('CALENDARDAY', maxSeq + 1)
  return pad(seq, 3)
}

/** EQ-00001 (equipment), key EQUIPMENT */
export async function makeEquipmentId(): Promise<string> {
  const seq = await reserve('EQUIPMENT')
  return `EQ-${pad(seq, 5)}`
}

/** PT-00001 (personal training sessions), key PTSESSION */
export async function makePtSessionId(): Promise<string> {
  const seq = await reserve('PTSESSION')
  return `PT-${pad(seq, 5)}`
}

// --- Combined formats ------------------------------------------------------

/** POS/{branchCode}/{MMMyy}/{00001}, key POS/{branchCode}/{MMMyy} */
export async function makePosSaleId(branchCode: string, date: Date): Promise<string> {
  const key = `POS/${branchCode}/${mmmYY(date)}`
  const seq = await reserve(key)
  return `POS/${branchCode}/${mmmYY(date)}/${pad(seq, 5)}`
}

/** PAY/{branchCode}/{MMMyy}/{00001} (payroll runs), key PAY/{branchCode}/{MMMyy} */
export async function makePayrollId(branchCode: string, date: Date): Promise<string> {
  const key = `PAY/${branchCode}/${mmmYY(date)}`
  const seq = await reserve(key)
  return `PAY/${branchCode}/${mmmYY(date)}/${pad(seq, 5)}`
}

/** FP/{branchCode}/{MMMyy}/{000001} (fee payments), key FEEPAY/{branchCode}/{MMMyy} */
export async function makeFeePaymentId(branchCode: string, date: Date): Promise<string> {
  const key = `FEEPAY/${branchCode}/${mmmYY(date)}`
  const seq = await reserve(key)
  return `FP/${branchCode}/${mmmYY(date)}/${pad(seq, 6)}`
}
