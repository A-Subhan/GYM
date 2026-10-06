/**
 * Attendance date helpers (gym module).
 *
 * Business rules (client-confirmed):
 *  - Attendance dates must be within the CURRENT month.
 *  - Attendance dates must never be in the future.
 *  - checkOut must be after checkIn.
 */

/** Returns a clear error message when the date is invalid, null when OK. */
export function validateAttendanceDate(d: Date): string | null {
  const now = new Date()
  const monthStart = new Date(now.getFullYear(), now.getMonth(), 1, 0, 0, 0, 0)
  const endOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999)
  if (d < monthStart) return 'Date must be within the current month — earlier dates are not allowed'
  if (d > endOfToday) return 'Date cannot be in the future'
  return null
}

/** Returns an error message when checkOut <= checkIn, null when OK. */
export function validateCheckOutAfterCheckIn(checkIn: Date | null, checkOut: Date | null): string | null {
  if (!checkIn || !checkOut) return null
  if (checkOut.getTime() <= checkIn.getTime()) return 'Check-out time must be after check-in time'
  return null
}
