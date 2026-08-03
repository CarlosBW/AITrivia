/**
 * Pure date helpers backing the daily-challenge endpoints in index.ts.
 * Kept in their own module (like ai_topic_similarity.ts) purely so they
 * can be unit-tested without pulling in firebase-admin — nothing here
 * touches Firestore, the clock, or any Firebase SDK. The server's "today"
 * is passed in rather than read, so tests are deterministic.
 */

// How far a client-supplied `dateId` may sit from the server's own date
// before it's treated as forged. The client derives its date from the
// *device's* local calendar while functions run in UTC, and real UTC
// offsets span -12 to +14, so a legitimate player's date is never more
// than one calendar day either side of the server's.
export const MAX_CLIENT_DATE_SKEW_DAYS = 1;

/**
 * Parses a `YYYY-MM-DD` id into a UTC-midnight timestamp, or NaN if it
 * isn't a real calendar date. A bare regex isn't enough: "2026-02-30"
 * matches the shape but doesn't exist.
 * @param {string} dateId Candidate date id.
 * @return {number} Epoch ms at UTC midnight, or NaN.
 */
export function parseDateId(dateId: string): number {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateId)) return NaN;

  const parsed = Date.parse(`${dateId}T00:00:00Z`);
  if (Number.isNaN(parsed)) return NaN;

  // Date.parse rolls some out-of-range days over instead of rejecting
  // them, so round-trip it and require the input back verbatim.
  return new Date(parsed).toISOString().slice(0, 10) === dateId ?
    parsed : NaN;
}

/**
 * Whether a client-supplied `dateId` is a real date within
 * [MAX_CLIENT_DATE_SKEW_DAYS] of the server's own.
 *
 * The daily-challenge endpoints key their documents off this id, so
 * without this check an arbitrary but well-formed date (tomorrow, then
 * the day after, then the day after that) lets a modified client walk
 * `dailyStreak` upward one forged submission at a time, collecting streak
 * bonuses and the daily-streak achievements without ever playing.
 * @param {string} dateId Client-supplied date id.
 * @param {string} serverToday The server's own `YYYY-MM-DD` date.
 * @return {boolean} True if the id is usable.
 */
export function isPlausibleDateId(
  dateId: string,
  serverToday: string
): boolean {
  const parsed = parseDateId(dateId);
  if (Number.isNaN(parsed)) return false;

  const serverMidnight = parseDateId(serverToday);
  if (Number.isNaN(serverMidnight)) return false;

  const skewDays = Math.round((parsed - serverMidnight) / 86400000);
  return Math.abs(skewDays) <= MAX_CLIENT_DATE_SKEW_DAYS;
}

/**
 * The Monday-anchored week id containing [dateId], matching
 * weekly_league_service.dart's `currentWeekId` (which the client derives
 * from the same local date it derives `todayDateId` from). Used to check
 * a client's `weekId` actually belongs to the `dateId` it was sent with,
 * so the two can't be mixed to write into an unrelated weekly bucket.
 * @param {string} dateId A date id that already passed [parseDateId].
 * @return {string} `YYYY-MM-DD` of that week's Monday, in UTC.
 */
export function weekIdForDateId(dateId: string): string {
  const date = new Date(`${dateId}T00:00:00Z`);
  const jsDay = date.getUTCDay(); // 0=Sun..6=Sat
  const isoWeekday = jsDay === 0 ? 7 : jsDay; // 1=Mon..7=Sun
  date.setUTCDate(date.getUTCDate() - (isoWeekday - 1));
  return date.toISOString().slice(0, 10);
}
