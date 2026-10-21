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

/** What a login-streak claim should do — see [loginStreakStep]. */
export type LoginStreakStep =
  | {status: "invalid"}
  | {status: "already"}
  | {status: "advance"; streak: number};

/**
 * Decides a daily login-streak claim.
 *
 * The client sends its own calendar date, and that date is what the
 * streak is keyed on. It used to be checked for shape only, so a script
 * could claim tomorrow, then the day after, and collect a streak bonus on
 * every call. It now has to sit within [MAX_CLIENT_DATE_SKEW_DAYS] of the
 * server's date, and a claim never moves the streak backwards — a device
 * a day ahead that already claimed tomorrow gets nothing new today.
 * @param {string|null} lastLoginDate The last claimed date, if any.
 * @param {number} previousStreak The streak as stored.
 * @param {string} todayDateId Client-supplied date id.
 * @param {string} serverToday The server's own `YYYY-MM-DD` date.
 * @return {LoginStreakStep} What to do with the claim.
 */
export function loginStreakStep(
  lastLoginDate: string | null,
  previousStreak: number,
  todayDateId: string,
  serverToday: string
): LoginStreakStep {
  if (!isPlausibleDateId(todayDateId, serverToday)) {
    return {status: "invalid"};
  }

  const last = lastLoginDate ? parseDateId(lastLoginDate) : NaN;
  if (Number.isNaN(last)) return {status: "advance", streak: 1};

  const days = Math.round((parseDateId(todayDateId) - last) / 86400000);
  if (days <= 0) return {status: "already"};
  return {status: "advance", streak: days === 1 ? previousStreak + 1 : 1};
}

/**
 * The `YYYY-MM-DD` calendar date at [epochMs] in [timeZone].
 *
 * Functions run in UTC, so `new Date().getDate()` is the UTC date. A job
 * scheduled for 19:00 in Lima runs at midnight UTC, when that is already
 * tomorrow.
 * @param {number} epochMs The instant.
 * @param {string} timeZone An IANA zone, e.g. "America/Lima".
 * @return {string} The date id in that zone.
 */
export function dateIdInTimeZone(epochMs: number, timeZone: string): string {
  // en-CA formats dates as YYYY-MM-DD.
  return new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date(epochMs));
}

/**
 * Whether a player whose last daily play was [lastDailyPlayed] still has a
 * streak to lose today: they played yesterday and not yet today.
 * @param {string|undefined} lastDailyPlayed Stored last play date.
 * @param {string} today Today's date id.
 * @return {boolean} True if a reminder makes sense.
 */
export function isStreakAtRisk(
  lastDailyPlayed: string | undefined,
  today: string
): boolean {
  if (!lastDailyPlayed) return false;
  const last = parseDateId(lastDailyPlayed);
  const now = parseDateId(today);
  if (Number.isNaN(last) || Number.isNaN(now)) return false;
  return Math.round((now - last) / 86400000) === 1;
}
