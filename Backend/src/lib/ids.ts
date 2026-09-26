// ID format helpers for Contoura Gym ERP
// Centralizes all the entity ID generation patterns

/**
 * Generate BranchID/MonthYear/sequence format
 * Example: "BR-001/0926/00001"
 */
export function genBranchMonthSeq(branchId: string, date: Date, seq: number, padLen = 5): string {
  const monthYear = String(date.getMonth() + 1).padStart(2, '0') + String(date.getFullYear()).slice(-2)
  return `${branchId}/${monthYear}/${String(seq).padStart(padLen, '0')}`
}

/**
 * Get current month-year string MMYY
 */
export function getMonthYear(date: Date = new Date()): string {
  return String(date.getMonth() + 1).padStart(2, '0') + String(date.getFullYear()).slice(-2)
}

/**
 * Generate BranchID/P-00001 format for prospects
 * Example: "BR-001/P-00001"
 */
export function genProspectId(branchId: string, seq: number): string {
  return `${branchId}/P-${String(seq).padStart(5, '0')}`
}

/**
 * Generate BranchID/FW-000001 format for follow-ups
 */
export function genFollowUpId(branchId: string, seq: number): string {
  return `${branchId}/FW-${String(seq).padStart(6, '0')}`
}

/**
 * Generate BranchID/PG-000001 format for progress entries
 */
export function genProgressId(branchId: string, seq: number): string {
  return `${branchId}/PG-${String(seq).padStart(6, '0')}`
}

/**
 * Generate F-000001 format for member freezes
 */
export function genFreezeId(seq: number): string {
  return `F-${String(seq).padStart(6, '0')}`
}

/**
 * Generate WO-000001 format for workout plans
 */
export function genWorkoutPlanId(seq: number): string {
  return `WO-${String(seq).padStart(6, '0')}`
}

/**
 * Generate DP-000001 format for diet plans
 */
export function genDietPlanId(seq: number): string {
  return `DP-${String(seq).padStart(6, '0')}`
}

/**
 * Generate LV-0001 format for leaves
 */
export function genLeaveId(seq: number): string {
  return `LV-${String(seq).padStart(4, '0')}`
}

/**
 * Count existing records and produce the next sequence number (1-based)
 * Falls back to 1 if the table is empty.
 */
export function nextSeq(count: number): number {
  return count + 1
}
