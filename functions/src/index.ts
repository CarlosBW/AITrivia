import * as admin from "firebase-admin";
import {setGlobalOptions} from "firebase-functions/v2";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import Anthropic from "@anthropic-ai/sdk";

setGlobalOptions({maxInstances: 10});

admin.initializeApp();

const db = admin.firestore();

// Set via `firebase functions:secrets:set ANTHROPIC_API_KEY`. Only bound to
// the callables that actually call Claude (see their `secrets:` option).
const anthropicApiKey = defineSecret("ANTHROPIC_API_KEY");
const AI_SECRETS = [anthropicApiKey];

/**
 * Cloud Functions run with no client context, so notification text sent to
 * a given user must be picked from their own stored `languageCode` field
 * (lib/services/locale_controller.dart writes it on every locale change;
 * lib/features/auth/user_bootstrap.dart seeds it on first launch) rather
 * than any notion of "current locale" — there isn't one here.
 * @param {unknown} languageCode The recipient's stored `languageCode`.
 * @param {string} es Spanish text.
 * @param {string} en English text.
 * @return {string} `en` if languageCode is `"en"`, otherwise `es`.
 */
function pickText(languageCode: unknown, es: string, en: string): string {
  return languageCode === "en" ? en : es;
}

// Mirrors the achievement*Title keys in lib/l10n/app_es.arb / app_en.arb —
// keep in sync.
const ACHIEVEMENT_TITLES: Record<string, {es: string; en: string}> = {
  first_pvp_win: {es: "Primera victoria en duelo", en: "First Duel Win"},
  pvp_wins_10: {es: "Duelista", en: "Duelist"},
  pvp_wins_25: {es: "Veterano de duelos", en: "Duel Veteran"},
  pvp_streak_5: {es: "En racha", en: "On Fire"},
  solo_levels_10: {es: "Explorador solitario", en: "Solo Explorer"},
  solo_levels_25: {es: "Maestro solitario", en: "Solo Master"},
  daily_streak_7: {es: "Hábito semanal", en: "Weekly Habit"},
  daily_streak_21: {es: "Constancia de hierro", en: "Iron Consistency"},
  friends_5: {es: "Jugador social", en: "Social Player"},
  friends_10: {es: "Círculo social", en: "Social Circle"},
  weekly_topics_completed_3: {es: "Explorador semanal", en: "Weekly Explorer"},
  categories_explored_5: {es: "Mente curiosa", en: "Curious Mind"},
};

const DEFAULT_RATING = 1000;
const K_FACTOR = 32;

// Max coins a match can pay its winner. Mirrors the highest stake the UI
// actually offers (create_match_screen.dart's dropdown: 1/2/3/5 coins) — a
// modified client can store any winReward it likes on the match doc before
// finishing it, so this is clamped server-side rather than trusted.
const MAX_WIN_REWARD = 5;

// Mirrors match_service.dart's ranked-disconnect constants exactly.
const RANKED_DISCONNECT_WINNER_BONUS = 12;
const RANKED_ABANDON_RATING_PENALTY = 32;
const RANKED_ABANDON_COOLDOWN_MINUTES = 5;

type PvpLeagueInfo = {
  id: string;
  name: string;
  emoji: string;
  minRating: number;
  maxRating: number;
  colorValue: number;
};

// Mirrors lib/services/pvp_league_service.dart's `leagues` list exactly,
// including colorValue — keep both in sync.
const PVP_LEAGUES: PvpLeagueInfo[] = [
  {
    id: "bronze",
    name: "Bronze",
    emoji: "🥉",
    minRating: 0,
    maxRating: 999,
    colorValue: 0xFF8D6E63,
  },
  {
    id: "silver",
    name: "Silver",
    emoji: "🥈",
    minRating: 1000,
    maxRating: 1199,
    colorValue: 0xFF78909C,
  },
  {
    id: "gold",
    name: "Gold",
    emoji: "🥇",
    minRating: 1200,
    maxRating: 1399,
    colorValue: 0xFFFFA000,
  },
  {
    id: "platinum",
    name: "Platinum",
    emoji: "💎",
    minRating: 1400,
    maxRating: 1599,
    colorValue: 0xFF00ACC1,
  },
  {
    id: "diamond",
    name: "Diamond",
    emoji: "🔷",
    minRating: 1600,
    maxRating: 1899,
    colorValue: 0xFF5E35B1,
  },
  {
    id: "master",
    name: "Master",
    emoji: "👑",
    minRating: 1900,
    maxRating: 5000,
    colorValue: 0xFFD81B60,
  },
];

/**
 * Safely converts a value to integer.
 * @param {unknown} value Value to convert.
 * @param {number} fallback Default value.
 * @return {number} Parsed integer.
 */
function safeInt(value: unknown, fallback: number): number {
  const n = Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : fallback;
}

/**
 * Clamps a client-supplied win reward against the max the UI ever offers.
 * @param {number} value Raw stored winReward.
 * @return {number} Clamped, non-negative reward.
 */
function clampWinReward(value: number): number {
  return Math.max(0, Math.min(MAX_WIN_REWARD, value));
}

/**
 * Recomputes a live-PvP player's real score from their actual submitted
 * answers, ignoring the `score` field a client wrote during play (which
 * was only ever an unverified, optimistic live-display value — see
 * match_service.dart's submitAnswer). `questions` lives on the match doc
 * itself (the same data the client already reads to render the quiz), so
 * this needs no extra fetch: a question counts only if the player's
 * recorded answers map picked the exact stored answerIndex for it.
 * @param {unknown} questions The match doc's `questions` array.
 * @param {unknown} answers The player's `players.{uid}.answers` map.
 * @return {number} The verified number of correct answers.
 */
function computeVerifiedPvpScore(questions: unknown, answers: unknown): number {
  if (!Array.isArray(questions)) return 0;

  const answerMap = (answers && typeof answers === "object") ?
    answers as Record<string, unknown> : {};

  let score = 0;
  for (let i = 0; i < questions.length; i++) {
    const correctIndex = safeInt(
      (questions[i] as Record<string, unknown> | undefined)?.answerIndex, -1
    );
    const selected = answerMap[String(i)];
    if (selected === undefined) continue;
    if (safeInt(selected, -2) === correctIndex) score++;
  }
  return score;
}

// Shared daily cap on coins earned from PvP wins (live + async combined).
// Kept as defense in depth even after finalizePvpMatch/finalizeAsyncPvpMatch
// started recomputing verified scores server-side — it still bounds the
// worst-case from match count abuse or two colluding real accounts
// win-trading, neither of which a per-match score check can catch.
const MAX_DAILY_PVP_COINS = 20;

/**
 * Server-side YYYY-MM-DD bucket key (Cloud Functions clock, never
 * client-supplied) used to rate-limit PvP coin payouts per day.
 * @return {string} Today's date id.
 */
function serverDateId(): string {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}` +
    `-${String(now.getDate()).padStart(2, "0")}`;
}

/**
 * Clamps how many of `rawCoins` a player may actually be paid right now
 * against their shared daily PvP coin cap, resetting the bucket if the
 * server date has rolled over since their last payout.
 * @param {Record<string, unknown>} userData Current user doc data.
 * @param {number} rawCoins Coins this win would otherwise pay out.
 * @return {{payable: number, patch: Record<string, unknown>}} Payable
 *   amount and the user-doc fields to persist the updated bucket.
 */
function clampDailyPvpCoins(
  userData: Record<string, unknown>,
  rawCoins: number
): {payable: number; patch: Record<string, unknown>} {
  if (rawCoins <= 0) return {payable: 0, patch: {}};

  const today = serverDateId();
  const sameDay = userData.pvpCoinsDate === today;
  const earnedSoFar = sameDay ? safeInt(userData.pvpCoinsToday, 0) : 0;

  const payable = Math.max(
    0, Math.min(rawCoins, MAX_DAILY_PVP_COINS - earnedSoFar)
  );

  return {
    payable,
    patch: {
      pvpCoinsToday: earnedSoFar + payable,
      pvpCoinsDate: today,
    },
  };
}

/**
 * Returns the PvP league for a rating.
 * @param {number} rating Player rating.
 * @return {PvpLeagueInfo} League information.
 */
function leagueForRating(rating: number): PvpLeagueInfo {
  const league = PVP_LEAGUES.find((item) => {
    return rating >= item.minRating && rating <= item.maxRating;
  });

  if (league) return league;

  if (rating < PVP_LEAGUES[0].minRating) {
    return PVP_LEAGUES[0];
  }

  return PVP_LEAGUES[PVP_LEAGUES.length - 1];
}

/**
 * Returns a league's ordinal rank (index in PVP_LEAGUES), used to compare
 * "how good" two leagues are relative to each other.
 * @param {string} id League id.
 * @return {number} Ordinal rank, or -1 if unknown.
 */
function leagueRank(id: string): number {
  return PVP_LEAGUES.findIndex((item) => item.id === id);
}

/**
 * Mirrors match_service.dart's `_bestLeaguePatch` — only patches the user's
 * "best league ever reached" fields if the candidate league actually ranks
 * higher than what's already stored.
 * @param {Record<string, unknown>} userData Current user document data.
 * @param {PvpLeagueInfo} candidateLeague League to compare against the
 * stored best.
 * @return {Record<string, unknown>} Fields to merge, or {} if unchanged.
 */
function bestLeaguePatch(
  userData: Record<string, unknown>,
  candidateLeague: PvpLeagueInfo
): Record<string, unknown> {
  const currentBestLeagueId = String(
    userData.bestLeagueId || userData.pvpLeagueId || ""
  );

  if (leagueRank(candidateLeague.id) <= leagueRank(currentBestLeagueId)) {
    return {};
  }

  return {
    bestLeagueId: candidateLeague.id,
    bestLeagueName: candidateLeague.name,
    bestLeagueEmoji: candidateLeague.emoji,
    bestLeagueColorValue: candidateLeague.colorValue,
  };
}

/**
 * Calculates ELO rating changes.
 * @param {{
 *   playerARating:number,
 *   playerBRating:number,
 *   playerAScore:number,
 *   playerBScore:number
 * }} params Match parameters.
 * @return {{newA:number,newB:number}} New ratings.
 */
function calculateRatings(params: {
  playerARating: number;
  playerBRating: number;
  playerAScore: number;
  playerBScore: number;
}): {newA: number; newB: number} {
  let resultA = 0.5;

  if (params.playerAScore > params.playerBScore) resultA = 1.0;
  if (params.playerBScore > params.playerAScore) resultA = 0.0;

  const expectedA =
    1 / (1 + Math.pow(10, (params.playerBRating - params.playerARating) / 400));

  const expectedB = 1 - expectedA;
  const resultB = 1 - resultA;

  const newA = Math.max(
    100,
    Math.min(
      5000,
      Math.round(params.playerARating + K_FACTOR * (resultA - expectedA))
    )
  );

  const newB = Math.max(
    100,
    Math.min(
      5000,
      Math.round(params.playerBRating + K_FACTOR * (resultB - expectedB))
    )
  );

  return {newA, newB};
}

/**
 * Returns match result for a specific user.
 * @param {string} userId User identifier.
 * @param {string|null} winnerUid Winner identifier.
 * @return {string} victory, defeat or draw.
 */
function resultFor(userId: string, winnerUid: string | null): string {
  if (winnerUid === null) return "draw";
  return winnerUid === userId ? "victory" : "defeat";
}

/**
 * Mirrors lib/services/weekly_league_service.dart's `currentWeekId` —
 * the Monday of the current week, as yyyy-MM-dd. Used both as a
 * `weekly_leagues`/`weekly_participation` bucket key and as the weekly
 * "season" id in season_service.dart.
 * @return {string} Week id.
 */
function currentWeekId(): string {
  const now = new Date();
  const jsDay = now.getDay(); // 0=Sun..6=Sat
  const dartWeekday = jsDay === 0 ? 7 : jsDay; // 1=Mon..7=Sun
  const monday = new Date(now);
  monday.setDate(now.getDate() - (dartWeekday - 1));

  const y = monday.getFullYear();
  const m = String(monday.getMonth() + 1).padStart(2, "0");
  const d = String(monday.getDate()).padStart(2, "0");
  return `${y}-${m}-${d}`;
}

/**
 * Computes the current PvP season id/start/end for "now", mirroring
 * lib/services/pvp_season_service.dart's `currentSeason()` (calendar-month
 * seasons).
 * @return {{id:string, start:Date, end:Date}} Season info.
 */
function currentPvpSeason(): {id: string; start: Date; end: Date} {
  const now = new Date();
  const start = new Date(now.getFullYear(), now.getMonth(), 1);
  const end = new Date(now.getFullYear(), now.getMonth() + 1, 1);
  const id = `pvp_${now.getFullYear()}_${String(now.getMonth() + 1).padStart(
    2,
    "0"
  )}`;

  return {id, start, end};
}

/**
 * Mirrors match_service.dart's `_queuePvpSeasonStatsWrite` — updates the
 * player's current-season stats doc and the "season best" fields on their
 * user doc. Ranked-match-only; never called for casual matches.
 * @param {FirebaseFirestore.Transaction} tx Active transaction.
 * @param {FirebaseFirestore.DocumentReference} userRef Player's user doc ref.
 * @param {Record<string, unknown>} userData Player's user doc data (as read
 * earlier in the same transaction).
 * @param {number} oldRating Rating before this match.
 * @param {number} newRating Rating after this match.
 * @param {boolean} won Whether this player won.
 * @param {boolean} lost Whether this player lost.
 * @param {boolean} draw Whether this match was a draw.
 */
function queuePvpSeasonStatsWrite(
  tx: FirebaseFirestore.Transaction,
  userRef: FirebaseFirestore.DocumentReference,
  userData: Record<string, unknown>,
  oldRating: number,
  newRating: number,
  won: boolean,
  lost: boolean,
  draw: boolean
): void {
  const season = currentPvpSeason();

  const sameSeason = String(userData.currentPvpSeasonId || "") === season.id;

  const previousBest = sameSeason ?
    safeInt(userData.pvpSeasonBestRating, oldRating) :
    oldRating;

  const bestRating = Math.max(previousBest, oldRating, newRating);

  const finalLeague = leagueForRating(newRating);
  const bestLeague = leagueForRating(bestRating);

  const statsRef = userRef.collection("pvp_season_stats").doc(season.id);

  tx.set(
    statsRef,
    {
      seasonId: season.id,
      seasonStart: admin.firestore.Timestamp.fromDate(season.start),
      seasonEnd: admin.firestore.Timestamp.fromDate(season.end),
      finalRating: newRating,
      finalLeagueId: finalLeague.id,
      finalLeagueName: finalLeague.name,
      finalLeagueEmoji: finalLeague.emoji,
      bestRating: bestRating,
      bestLeagueId: bestLeague.id,
      bestLeagueName: bestLeague.name,
      bestLeagueEmoji: bestLeague.emoji,
      matchesPlayed: admin.firestore.FieldValue.increment(1),
      ...(won ? {wins: admin.firestore.FieldValue.increment(1)} : {}),
      ...(lost ? {losses: admin.firestore.FieldValue.increment(1)} : {}),
      ...(draw ? {draws: admin.firestore.FieldValue.increment(1)} : {}),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true}
  );

  tx.set(
    userRef,
    {
      currentPvpSeasonId: season.id,
      pvpSeasonBestRating: bestRating,
      pvpSeasonBestLeagueId: bestLeague.id,
      pvpSeasonBestLeagueName: bestLeague.name,
      ...bestLeaguePatch(userData, bestLeague),
      pvpSeasonFinalRating: newRating,
      pvpSeasonFinalLeagueId: finalLeague.id,
      pvpSeasonFinalLeagueName: finalLeague.name,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true}
  );
}

type PvpAchievementDef = {
  id: string;
  title: string;
  target: number;
};

// Mirrors the PvP-related entries in lib/services/achievement_service.dart's
// `achievements` list. Keep these two in sync.
const PVP_ACHIEVEMENTS: PvpAchievementDef[] = [
  {id: "first_pvp_win", title: "First Duel Win", target: 1},
  {id: "pvp_wins_10", title: "Duelist", target: 10},
  {id: "pvp_streak_5", title: "On Fire", target: 5},
  {id: "pvp_wins_25", title: "Duel Veteran", target: 25},
];

/**
 * Reads a player's PvP-related achievement docs inside a transaction.
 * @param {FirebaseFirestore.Transaction} tx Active transaction.
 * @param {string} uid Player id.
 * @return {Promise<FirebaseFirestore.DocumentSnapshot[]>} Snapshots, in
 * PVP_ACHIEVEMENTS order.
 */
async function readPvpAchievementSnaps(
  tx: FirebaseFirestore.Transaction,
  uid: string
): Promise<FirebaseFirestore.DocumentSnapshot[]> {
  const col = db.collection("users").doc(uid).collection("achievements");
  return Promise.all(PVP_ACHIEVEMENTS.map((a) => tx.get(col.doc(a.id))));
}

/**
 * Applies progress to a single PvP achievement doc, mirroring
 * lib/services/achievement_service.dart's setProgress schema, and queues an
 * in-app notification the first time it completes.
 * @param {FirebaseFirestore.Transaction} tx Active transaction.
 * @param {string} uid Player id.
 * @param {PvpAchievementDef} achievement Achievement definition.
 * @param {number} progress New progress value.
 * @param {FirebaseFirestore.DocumentSnapshot} snap Previously-read
 * achievement doc.
 * @param {unknown} languageCode This player's stored `languageCode`
 * (`users/{uid}.languageCode`), used to localize the completion
 * notification — this player is always the notification's own recipient.
 */
function applyPvpAchievementProgress(
  tx: FirebaseFirestore.Transaction,
  uid: string,
  achievement: PvpAchievementDef,
  progress: number,
  snap: FirebaseFirestore.DocumentSnapshot,
  languageCode: unknown
): void {
  const data = snap.data() || {};

  if (data.claimed === true) return;

  const currentProgress = safeInt(data.progress, 0);
  if (progress <= currentProgress) return;

  const completed = progress >= achievement.target;
  const alreadyNotified = data.notificationSent === true;

  const update: Record<string, unknown> = {
    id: achievement.id,
    progress: Math.min(progress, achievement.target),
    target: achievement.target,
    completed,
    claimed: false,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (completed) {
    update.completedAt = admin.firestore.FieldValue.serverTimestamp();
  }

  if (completed && !alreadyNotified) {
    update.notificationSent = true;
    update.notificationSentAt = admin.firestore.FieldValue.serverTimestamp();
  }

  tx.set(snap.ref, update, {merge: true});

  if (completed && !alreadyNotified) {
    const localizedTitle = languageCode === "en" ?
      (ACHIEVEMENT_TITLES[achievement.id]?.en || achievement.title) :
      (ACHIEVEMENT_TITLES[achievement.id]?.es || achievement.title);

    tx.set(db.collection("users").doc(uid).collection("notifications").doc(), {
      type: "achievement_completed",
      title: pickText(
        languageCode, "Logro completado", "Achievement completed"
      ),
      body: pickText(
        languageCode,
        `Completaste "${localizedTitle}". Reclama tu recompensa.`,
        `You completed "${localizedTitle}". Claim your reward.`
      ),
      data: {achievementId: achievement.id},
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
}

type RankedRewardResult = {
  newRating: number;
  ratingDelta: number;
  xpEarned: number;
  coinsEarned: number;
  newStreak: number;
  bestStreak: number;
  oldLeague: PvpLeagueInfo;
  newLeague: PvpLeagueInfo;
};

/**
 * Computes one player's side of a ranked match's rewards — rating, xp,
 * coins, and win-streak — branching on whether this is a normal
 * score-based finish or an opponent-disconnect finish (flat bonus/penalty
 * instead of ELO). Mirrors match_service.dart's `calculateRatings` /
 * `_queueRankedDisconnectPenaltyUpdates` math exactly.
 * @param {{
 *   oldRating:number, opponentOldRating:number, score:number,
 *   opponentScore:number, won:boolean, draw:boolean, winReward:number,
 *   isDisconnect:boolean, currentStreak:number, bestStreak:number
 * }} params Inputs needed to compute this player's reward.
 * @return {RankedRewardResult} Computed reward fields.
 */
function computeRankedReward(params: {
  oldRating: number;
  opponentOldRating: number;
  score: number;
  opponentScore: number;
  won: boolean;
  draw: boolean;
  winReward: number;
  isDisconnect: boolean;
  currentStreak: number;
  bestStreak: number;
}): RankedRewardResult {
  let newRating: number;

  if (params.isDisconnect) {
    const bonus = RANKED_DISCONNECT_WINNER_BONUS;
    const penalty = RANKED_ABANDON_RATING_PENALTY;
    newRating = params.won ?
      Math.max(100, Math.min(5000, params.oldRating + bonus)) :
      Math.max(100, Math.min(5000, params.oldRating - penalty));
  } else {
    const {newA} = calculateRatings({
      playerARating: params.oldRating,
      playerBRating: params.opponentOldRating,
      playerAScore: params.score,
      playerBScore: params.opponentScore,
    });
    newRating = newA;
  }

  const xpEarned = params.isDisconnect ?
    (params.won ? 15 : 0) :
    params.draw ? 10 : params.won ? 15 : 5;

  const coinsEarned = params.won ? params.winReward : 0;

  const newStreak = params.won ? params.currentStreak + 1 : 0;
  const bestStreak = Math.max(params.bestStreak, newStreak);

  const oldLeague = leagueForRating(params.oldRating);
  const newLeague = leagueForRating(newRating);

  return {
    newRating,
    ratingDelta: newRating - params.oldRating,
    xpEarned,
    coinsEarned,
    newStreak,
    bestStreak,
    oldLeague,
    newLeague,
  };
}

export const finalizePvpMatch = onDocumentUpdated(
  "matches/{matchId}",
  async (event) => {
    const matchId = event.params.matchId;
    const after = event.data?.after.data();

    if (!after) return;
    if (after.status === "finished") return;
    if (after.rewarded === true) return;

    const hostUid = String(after.hostUid || "");
    const guestUid = String(after.guestUid || "");

    if (!hostUid || !guestUid) return;

    const players = after.players || {};
    const host = players[hostUid] || {};
    const guest = players[guestUid] || {};

    if (host.finished !== true || guest.finished !== true) return;

    const matchRef = db.collection("matches").doc(matchId);
    const hostRef = db.collection("users").doc(hostUid);
    const guestRef = db.collection("users").doc(guestUid);

    await db.runTransaction(async (tx) => {
      const matchSnap = await tx.get(matchRef);
      const fresh = matchSnap.data();

      if (!fresh) return;
      if (fresh.status === "finished") return;
      if (fresh.rewarded === true) return;

      const freshPlayers = fresh.players || {};
      const freshHost = freshPlayers[hostUid] || {};
      const freshGuest = freshPlayers[guestUid] || {};

      if (freshHost.finished !== true || freshGuest.finished !== true) return;

      const isDisconnect = fresh.finishReason === "opponent_disconnected";

      const hostScore = computeVerifiedPvpScore(
        fresh.questions, freshHost.answers
      );
      const guestScore = computeVerifiedPvpScore(
        fresh.questions, freshGuest.answers
      );

      let winnerUid: string | null = null;

      if (isDisconnect) {
        const storedWinner = String(fresh.winnerUid || "");
        if (storedWinner !== hostUid && storedWinner !== guestUid) return;
        winnerUid = storedWinner;
      } else {
        if (hostScore > guestScore) winnerUid = hostUid;
        if (guestScore > hostScore) winnerUid = guestUid;
      }

      const ranked = fresh.affectsPvpRating === true || fresh.ranked === true;
      const winReward = clampWinReward(safeInt(fresh.winReward, 0));

      const hostSnap = await tx.get(hostRef);
      const guestSnap = await tx.get(guestRef);

      const hostUser = hostSnap.data() || {};
      const guestUser = guestSnap.data() || {};

      const hostName = String(freshHost.displayName || "Host");
      const guestName = String(freshGuest.displayName || "Guest");

      const hostWon = winnerUid === hostUid;
      const guestWon = winnerUid === guestUid;
      const draw = winnerUid === null;

      const hostCurrentStreak = safeInt(hostUser.currentWinStreak1v1, 0);
      const guestCurrentStreak = safeInt(guestUser.currentWinStreak1v1, 0);

      const hostBestStreakSoFar = safeInt(hostUser.bestWinStreak1v1, 0);
      const guestBestStreakSoFar = safeInt(guestUser.bestWinStreak1v1, 0);

      const [hostAchSnaps, guestAchSnaps] = await Promise.all([
        readPvpAchievementSnaps(tx, hostUid),
        readPvpAchievementSnaps(tx, guestUid),
      ]);

      const [
        hostFirstWinSnap, hostWins10Snap, hostStreak5Snap, hostWins25Snap,
      ] = hostAchSnaps;
      const [
        guestFirstWinSnap, guestWins10Snap, guestStreak5Snap, guestWins25Snap,
      ] = guestAchSnaps;

      const ratingResults: Record<string, Record<string, unknown>> = {};

      if (ranked) {
        const hostOldRating = safeInt(hostUser.pvpRating, DEFAULT_RATING);
        const guestOldRating = safeInt(guestUser.pvpRating, DEFAULT_RATING);

        const hostReward = computeRankedReward({
          oldRating: hostOldRating,
          opponentOldRating: guestOldRating,
          score: hostScore,
          opponentScore: guestScore,
          won: hostWon,
          draw,
          winReward,
          isDisconnect,
          currentStreak: hostCurrentStreak,
          bestStreak: hostBestStreakSoFar,
        });

        const guestReward = computeRankedReward({
          oldRating: guestOldRating,
          opponentOldRating: hostOldRating,
          score: guestScore,
          opponentScore: hostScore,
          won: guestWon,
          draw,
          winReward,
          isDisconnect,
          currentStreak: guestCurrentStreak,
          bestStreak: guestBestStreakSoFar,
        });

        applyPvpAchievementProgress(
          tx, hostUid, PVP_ACHIEVEMENTS[0], hostReward.newStreak > 0 ?
            safeInt(hostUser.wins1v1, 0) + (hostWon ? 1 : 0) :
            safeInt(hostUser.wins1v1, 0) + (hostWon ? 1 : 0),
          hostFirstWinSnap, hostUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, hostUid, PVP_ACHIEVEMENTS[1],
          safeInt(hostUser.wins1v1, 0) + (hostWon ? 1 : 0), hostWins10Snap,
          hostUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, hostUid, PVP_ACHIEVEMENTS[2], hostReward.newStreak,
          hostStreak5Snap, hostUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, hostUid, PVP_ACHIEVEMENTS[3],
          safeInt(hostUser.wins1v1, 0) + (hostWon ? 1 : 0), hostWins25Snap,
          hostUser.languageCode
        );

        applyPvpAchievementProgress(
          tx, guestUid, PVP_ACHIEVEMENTS[0],
          safeInt(guestUser.wins1v1, 0) + (guestWon ? 1 : 0),
          guestFirstWinSnap, guestUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, guestUid, PVP_ACHIEVEMENTS[1],
          safeInt(guestUser.wins1v1, 0) + (guestWon ? 1 : 0), guestWins10Snap,
          guestUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, guestUid, PVP_ACHIEVEMENTS[2], guestReward.newStreak,
          guestStreak5Snap, guestUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, guestUid, PVP_ACHIEVEMENTS[3],
          safeInt(guestUser.wins1v1, 0) + (guestWon ? 1 : 0), guestWins25Snap,
          guestUser.languageCode
        );

        const hostCoinClamp = clampDailyPvpCoins(
          hostUser, hostReward.coinsEarned
        );
        const guestCoinClamp = clampDailyPvpCoins(
          guestUser, guestReward.coinsEarned
        );

        ratingResults[hostUid] = {
          oldRating: hostOldRating,
          newRating: hostReward.newRating,
          ratingDelta: hostReward.ratingDelta,
          xpEarned: hostReward.xpEarned,
          coinsEarned: hostCoinClamp.payable,
          winStreak: hostReward.newStreak,
          oldLeagueName: hostReward.oldLeague.name,
          newLeagueName: hostReward.newLeague.name,
        };

        ratingResults[guestUid] = {
          oldRating: guestOldRating,
          newRating: guestReward.newRating,
          ratingDelta: guestReward.ratingDelta,
          xpEarned: guestReward.xpEarned,
          coinsEarned: guestCoinClamp.payable,
          winStreak: guestReward.newStreak,
          oldLeagueName: guestReward.oldLeague.name,
          newLeagueName: guestReward.newLeague.name,
        };

        tx.set(
          hostRef,
          {
            matches1v1: admin.firestore.FieldValue.increment(1),
            wins1v1: admin.firestore.FieldValue.increment(hostWon ? 1 : 0),
            losses1v1: admin.firestore.FieldValue.increment(guestWon ? 1 : 0),
            draws1v1: admin.firestore.FieldValue.increment(draw ? 1 : 0),
            currentWinStreak1v1: hostReward.newStreak,
            bestWinStreak1v1: hostReward.bestStreak,
            pvpRating: hostReward.newRating,
            pvpRatingDelta: hostReward.ratingDelta,
            pvpLeagueId: hostReward.newLeague.id,
            pvpLeagueName: hostReward.newLeague.name,
            ...bestLeaguePatch(hostUser, hostReward.newLeague),
            xp: admin.firestore.FieldValue.increment(hostReward.xpEarned),
            coins: admin.firestore.FieldValue.increment(
              hostCoinClamp.payable
            ),
            ...hostCoinClamp.patch,
            lastRankedXpEarned: hostReward.xpEarned,
            lastRankedCoinsEarned: hostCoinClamp.payable,
            ...(isDisconnect && !hostWon ? {
              pvpAbandonCount: admin.firestore.FieldValue.increment(1),
              pvpCooldownUntil: admin.firestore.Timestamp.fromMillis(
                Date.now() + RANKED_ABANDON_COOLDOWN_MINUTES * 60 * 1000
              ),
              lastPvpPenaltyReason: "disconnect",
            } : {}),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true}
        );

        tx.set(
          guestRef,
          {
            matches1v1: admin.firestore.FieldValue.increment(1),
            wins1v1: admin.firestore.FieldValue.increment(guestWon ? 1 : 0),
            losses1v1: admin.firestore.FieldValue.increment(hostWon ? 1 : 0),
            draws1v1: admin.firestore.FieldValue.increment(draw ? 1 : 0),
            currentWinStreak1v1: guestReward.newStreak,
            bestWinStreak1v1: guestReward.bestStreak,
            pvpRating: guestReward.newRating,
            pvpRatingDelta: guestReward.ratingDelta,
            pvpLeagueId: guestReward.newLeague.id,
            pvpLeagueName: guestReward.newLeague.name,
            ...bestLeaguePatch(guestUser, guestReward.newLeague),
            xp: admin.firestore.FieldValue.increment(guestReward.xpEarned),
            coins: admin.firestore.FieldValue.increment(
              guestCoinClamp.payable
            ),
            ...guestCoinClamp.patch,
            lastRankedXpEarned: guestReward.xpEarned,
            lastRankedCoinsEarned: guestCoinClamp.payable,
            ...(isDisconnect && !guestWon ? {
              pvpAbandonCount: admin.firestore.FieldValue.increment(1),
              pvpCooldownUntil: admin.firestore.Timestamp.fromMillis(
                Date.now() + RANKED_ABANDON_COOLDOWN_MINUTES * 60 * 1000
              ),
              lastPvpPenaltyReason: "disconnect",
            } : {}),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true}
        );

        queuePvpSeasonStatsWrite(
          tx, hostRef, hostUser, safeInt(hostUser.pvpRating, DEFAULT_RATING),
          hostReward.newRating, hostWon, guestWon, draw
        );
        queuePvpSeasonStatsWrite(
          tx, guestRef, guestUser, safeInt(guestUser.pvpRating, DEFAULT_RATING),
          guestReward.newRating, guestWon, hostWon, draw
        );
      } else {
        const hostNewStreak = hostWon ? hostCurrentStreak + 1 : 0;
        const guestNewStreak = guestWon ? guestCurrentStreak + 1 : 0;

        applyPvpAchievementProgress(
          tx, hostUid, PVP_ACHIEVEMENTS[0],
          safeInt(hostUser.wins1v1, 0) + (hostWon ? 1 : 0), hostFirstWinSnap,
          hostUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, hostUid, PVP_ACHIEVEMENTS[1],
          safeInt(hostUser.wins1v1, 0) + (hostWon ? 1 : 0), hostWins10Snap,
          hostUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, hostUid, PVP_ACHIEVEMENTS[2], hostNewStreak, hostStreak5Snap,
          hostUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, hostUid, PVP_ACHIEVEMENTS[3],
          safeInt(hostUser.wins1v1, 0) + (hostWon ? 1 : 0), hostWins25Snap,
          hostUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, guestUid, PVP_ACHIEVEMENTS[0],
          safeInt(guestUser.wins1v1, 0) + (guestWon ? 1 : 0), guestFirstWinSnap,
          guestUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, guestUid, PVP_ACHIEVEMENTS[1],
          safeInt(guestUser.wins1v1, 0) + (guestWon ? 1 : 0), guestWins10Snap,
          guestUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, guestUid, PVP_ACHIEVEMENTS[2], guestNewStreak, guestStreak5Snap,
          guestUser.languageCode
        );
        applyPvpAchievementProgress(
          tx, guestUid, PVP_ACHIEVEMENTS[3],
          safeInt(guestUser.wins1v1, 0) + (guestWon ? 1 : 0), guestWins25Snap,
          guestUser.languageCode
        );

        const hostCoinClamp = clampDailyPvpCoins(
          hostUser, hostWon ? winReward : 0
        );
        const guestCoinClamp = clampDailyPvpCoins(
          guestUser, guestWon ? winReward : 0
        );

        tx.set(
          hostRef,
          {
            matches1v1: admin.firestore.FieldValue.increment(1),
            wins1v1: admin.firestore.FieldValue.increment(hostWon ? 1 : 0),
            losses1v1: admin.firestore.FieldValue.increment(guestWon ? 1 : 0),
            draws1v1: admin.firestore.FieldValue.increment(draw ? 1 : 0),
            currentWinStreak1v1: hostNewStreak,
            bestWinStreak1v1: Math.max(hostBestStreakSoFar, hostNewStreak),
            coins: admin.firestore.FieldValue.increment(
              hostCoinClamp.payable
            ),
            ...hostCoinClamp.patch,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true}
        );

        tx.set(
          guestRef,
          {
            matches1v1: admin.firestore.FieldValue.increment(1),
            wins1v1: admin.firestore.FieldValue.increment(guestWon ? 1 : 0),
            losses1v1: admin.firestore.FieldValue.increment(hostWon ? 1 : 0),
            draws1v1: admin.firestore.FieldValue.increment(draw ? 1 : 0),
            currentWinStreak1v1: guestNewStreak,
            bestWinStreak1v1: Math.max(guestBestStreakSoFar, guestNewStreak),
            coins: admin.firestore.FieldValue.increment(
              guestCoinClamp.payable
            ),
            ...guestCoinClamp.patch,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true}
        );
      }

      tx.set(
        hostRef.collection("match_history").doc(matchId),
        {
          matchId,
          mode: ranked ? "ranked" : "casual",
          ranked,
          result: resultFor(hostUid, winnerUid),
          opponentUid: guestUid,
          opponentName: guestName,
          myScore: hostScore,
          opponentScore: guestScore,
          oldRating: ratingResults[hostUid]?.oldRating ?? null,
          newRating: ratingResults[hostUid]?.newRating ?? null,
          ratingDelta: ratingResults[hostUid]?.ratingDelta ?? null,
          xpEarned: ratingResults[hostUid]?.xpEarned ?? null,
          coinsEarned: ratingResults[hostUid]?.coinsEarned ?? null,
          winStreak: ratingResults[hostUid]?.winStreak ?? null,
          oldLeagueName: ratingResults[hostUid]?.oldLeagueName ?? null,
          newLeagueName: ratingResults[hostUid]?.newLeagueName ?? null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );

      tx.set(
        guestRef.collection("match_history").doc(matchId),
        {
          matchId,
          mode: ranked ? "ranked" : "casual",
          ranked,
          result: resultFor(guestUid, winnerUid),
          opponentUid: hostUid,
          opponentName: hostName,
          myScore: guestScore,
          opponentScore: hostScore,
          oldRating: ratingResults[guestUid]?.oldRating ?? null,
          newRating: ratingResults[guestUid]?.newRating ?? null,
          ratingDelta: ratingResults[guestUid]?.ratingDelta ?? null,
          xpEarned: ratingResults[guestUid]?.xpEarned ?? null,
          coinsEarned: ratingResults[guestUid]?.coinsEarned ?? null,
          winStreak: ratingResults[guestUid]?.winStreak ?? null,
          oldLeagueName: ratingResults[guestUid]?.oldLeagueName ?? null,
          newLeagueName: ratingResults[guestUid]?.newLeagueName ?? null,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );

      tx.update(matchRef, {
        status: "finished",
        endedAt: admin.firestore.FieldValue.serverTimestamp(),
        winnerUid,
        rewarded: true,
        ratingResults,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });
  }
);

/**
 * Async (deferred) 1v1 matches never carry a ranked/affectsPvpRating flag
 * today (createAsyncFixedMatch never sets one) — this trigger only ever
 * applies casual rewards. If async ranked matches are added later, port the
 * ranked branch from finalizePvpMatch here too.
 */
export const finalizeAsyncPvpMatch = onDocumentUpdated(
  "async_matches/{matchId}",
  async (event) => {
    const matchId = event.params.matchId;
    const after = event.data?.after.data();

    if (!after) return;
    if (after.rewarded === true) return;
    if (after.challengerStatus !== "finished") return;
    if (after.challengedStatus !== "finished") return;

    const challengerUid = String(after.challengerUid || "");
    const challengedUid = String(after.challengedUid || "");

    if (!challengerUid || !challengedUid) return;

    const matchRef = db.collection("async_matches").doc(matchId);
    const challengerRef = db.collection("users").doc(challengerUid);
    const challengedRef = db.collection("users").doc(challengedUid);

    await db.runTransaction(async (tx) => {
      const matchSnap = await tx.get(matchRef);
      const fresh = matchSnap.data();

      if (!fresh) return;
      if (fresh.rewarded === true) return;
      if (fresh.challengerStatus !== "finished") return;
      if (fresh.challengedStatus !== "finished") return;

      const challengerScore = computeVerifiedPvpScore(
        fresh.questions, fresh.challenger?.answers
      );
      const challengedScore = computeVerifiedPvpScore(
        fresh.questions, fresh.challenged?.answers
      );

      let winnerUid: string | null = null;
      if (challengerScore > challengedScore) winnerUid = challengerUid;
      if (challengedScore > challengerScore) winnerUid = challengedUid;

      const draw = winnerUid === null;
      const challengerWon = winnerUid === challengerUid;
      const challengedWon = winnerUid === challengedUid;

      const winReward = clampWinReward(safeInt(fresh.winReward, 0));

      const challengerSnap = await tx.get(challengerRef);
      const challengedSnap = await tx.get(challengedRef);
      const challengerUser = challengerSnap.data() || {};
      const challengedUser = challengedSnap.data() || {};

      const challengerCurrentStreak = safeInt(
        challengerUser.currentWinStreak1v1, 0
      );
      const challengedCurrentStreak = safeInt(
        challengedUser.currentWinStreak1v1, 0
      );
      const challengerBestStreakSoFar = safeInt(
        challengerUser.bestWinStreak1v1, 0
      );
      const challengedBestStreakSoFar = safeInt(
        challengedUser.bestWinStreak1v1, 0
      );

      const challengerNewStreak = challengerWon ?
        challengerCurrentStreak + 1 : 0;
      const challengedNewStreak = challengedWon ?
        challengedCurrentStreak + 1 : 0;

      const challengerCoinClamp = clampDailyPvpCoins(
        challengerUser, challengerWon ? winReward : 0
      );
      const challengedCoinClamp = clampDailyPvpCoins(
        challengedUser, challengedWon ? winReward : 0
      );

      tx.set(
        challengerRef,
        {
          matches1v1: admin.firestore.FieldValue.increment(1),
          wins1v1: admin.firestore.FieldValue.increment(challengerWon ? 1 : 0),
          losses1v1: admin.firestore.FieldValue.increment(
            challengedWon ? 1 : 0
          ),
          draws1v1: admin.firestore.FieldValue.increment(draw ? 1 : 0),
          currentWinStreak1v1: challengerNewStreak,
          bestWinStreak1v1: Math.max(
            challengerBestStreakSoFar, challengerNewStreak
          ),
          coins: admin.firestore.FieldValue.increment(
            challengerCoinClamp.payable
          ),
          ...challengerCoinClamp.patch,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );

      tx.set(
        challengedRef,
        {
          matches1v1: admin.firestore.FieldValue.increment(1),
          wins1v1: admin.firestore.FieldValue.increment(
            challengedWon ? 1 : 0
          ),
          losses1v1: admin.firestore.FieldValue.increment(
            challengerWon ? 1 : 0
          ),
          draws1v1: admin.firestore.FieldValue.increment(draw ? 1 : 0),
          currentWinStreak1v1: challengedNewStreak,
          bestWinStreak1v1: Math.max(
            challengedBestStreakSoFar, challengedNewStreak
          ),
          coins: admin.firestore.FieldValue.increment(
            challengedCoinClamp.payable
          ),
          ...challengedCoinClamp.patch,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );

      const challengerName = String(
        fresh.challengerDisplayName || "Player"
      );
      const challengedName = String(
        fresh.challengedDisplayName || "Player"
      );

      const notify = (
        targetUid: string,
        esTitle: string,
        enTitle: string,
        esBody: string,
        enBody: string
      ): void => {
        const languageCode = targetUid === challengerUid ?
          challengerUser.languageCode : challengedUser.languageCode;

        tx.set(
          db.collection("users").doc(targetUid).collection("notifications")
            .doc(),
          {
            type: "match_result",
            title: pickText(languageCode, esTitle, enTitle),
            body: pickText(languageCode, esBody, enBody),
            data: {matchId},
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          }
        );
      };

      if (draw) {
        notify(
          challengerUid, "Partida terminada", "Async match finished",
          `Tu partida contra ${challengedName} terminó en empate.`,
          `Your match against ${challengedName} ended in a draw.`
        );
        notify(
          challengedUid, "Partida terminada", "Async match finished",
          `Tu partida contra ${challengerName} terminó en empate.`,
          `Your match against ${challengerName} ended in a draw.`
        );
      } else {
        const loserUid = challengerWon ? challengedUid : challengerUid;
        const winnerOpponentName = challengerWon ?
          challengedName : challengerName;
        const loserOpponentName = loserUid === challengerUid ?
          challengedName : challengerName;

        notify(
          winnerUid as string, "¡Ganaste!", "You won!",
          `Ganaste tu partida asíncrona contra ${winnerOpponentName}.`,
          `You won your async match against ${winnerOpponentName}.`
        );
        notify(
          loserUid, "Partida terminada", "Match finished",
          `Perdiste tu partida asíncrona contra ${loserOpponentName}.`,
          `You lost your async match against ${loserOpponentName}.`
        );
      }

      tx.update(matchRef, {
        status: "completed",
        endedAt: admin.firestore.FieldValue.serverTimestamp(),
        winnerUid,
        rewarded: true,
        challengerScore,
        challengedScore,
        resultNotificationsSent: true,
      });
    });
  }
);

/**
 * Callable replacement for pvp_season_service.dart's
 * `claimAllPendingPvpSeasonRewards`. The source data (pvp_season_stats /
 * pvp_season_history) is already server-only (rules: write:false), so the
 * reward amounts here can't be forged — this function exists purely because
 * the actual `coins` increment must move server-side once `coins` is
 * protected in firestore.rules.
 */
export const claimPvpSeasonRewards = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const userRef = db.collection("users").doc(uid);
  const currentSeasonId = currentPvpSeason().id;

  return db.runTransaction(async (tx) => {
    const statsSnap = await tx.get(userRef.collection("pvp_season_stats"));
    const historySnap = await tx.get(
      userRef.collection("pvp_season_history")
    );

    const claimedSeasonIds = new Set(historySnap.docs.map((d) => d.id));

    type Pending = {
      seasonId: string;
      finalRating: number;
      bestRating: number;
      leagueId: string;
      leagueName: string;
      leagueEmoji: string;
      rewardCoins: number;
      matchesPlayed: number;
      wins: number;
      losses: number;
      draws: number;
    };

    // Mirrors lib/services/pvp_league_service.dart's `masterTierIndex` +
    // lib/services/pvp_season_service.dart's `rewardForRating` — Master has
    // no rating ceiling, so a flat reward regardless of rating meant
    // progression stopped paying off once a player got there.
    const rewardForLeague = (league: PvpLeagueInfo, rating: number): number => {
      if (league.id !== "master") {
        switch (league.id) {
        case "diamond": return 40;
        case "platinum": return 20;
        case "gold": return 10;
        case "silver": return 5;
        default: return 2;
        }
      }

      if (rating >= 2200) return 150;
      if (rating >= 2050) return 110;
      return 80;
    };

    const pending: Pending[] = [];

    for (const doc of statsSnap.docs) {
      const seasonId = doc.id;
      if (seasonId.localeCompare(currentSeasonId) >= 0) continue;
      if (claimedSeasonIds.has(seasonId)) continue;

      const data = doc.data();
      const finalRating = safeInt(data.finalRating, DEFAULT_RATING);
      const bestRating = safeInt(data.bestRating, finalRating);
      const bestLeague = leagueForRating(bestRating);

      pending.push({
        seasonId,
        finalRating,
        bestRating,
        leagueId: bestLeague.id,
        leagueName: bestLeague.name,
        leagueEmoji: bestLeague.emoji,
        rewardCoins: rewardForLeague(bestLeague, bestRating),
        matchesPlayed: safeInt(data.matchesPlayed, 0),
        wins: safeInt(data.wins, 0),
        losses: safeInt(data.losses, 0),
        draws: safeInt(data.draws, 0),
      });
    }

    pending.sort((a, b) => b.seasonId.localeCompare(a.seasonId));

    if (pending.length === 0) {
      return {claimedCount: 0, totalCoins: 0, rewards: []};
    }

    let totalCoins = 0;
    const results = [];

    for (const reward of pending) {
      totalCoins += reward.rewardCoins;

      const finalLeague = leagueForRating(reward.finalRating);
      const historyRef = userRef
        .collection("pvp_season_history")
        .doc(reward.seasonId);

      tx.set(
        historyRef,
        {
          seasonId: reward.seasonId,
          finalRating: reward.finalRating,
          finalLeagueId: finalLeague.id,
          finalLeagueName: finalLeague.name,
          finalLeagueEmoji: finalLeague.emoji,
          bestRating: reward.bestRating,
          bestLeagueId: reward.leagueId,
          bestLeagueName: reward.leagueName,
          bestLeagueEmoji: reward.leagueEmoji,
          matchesPlayed: reward.matchesPlayed,
          wins: reward.wins,
          losses: reward.losses,
          draws: reward.draws,
          rewardCoins: reward.rewardCoins,
          rewardBasedOn: "bestRating",
          claimedAt: admin.firestore.FieldValue.serverTimestamp(),
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );

      results.push({
        seasonId: reward.seasonId,
        leagueId: reward.leagueId,
        leagueName: reward.leagueName,
        finalRating: reward.finalRating,
        bestRating: reward.bestRating,
        rewardCoins: reward.rewardCoins,
        alreadyClaimed: false,
      });
    }

    tx.set(
      userRef,
      {
        coins: admin.firestore.FieldValue.increment(totalCoins),
        lastClaimedPvpSeasonId: pending[0].seasonId,
        lastPvpSeasonRewardCoins: totalCoins,
        lastPvpSeasonRewardCount: pending.length,
        lastPvpSeasonRewardClaimedAt:
          admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    return {
      claimedCount: results.length,
      totalCoins,
      rewards: results,
    };
  });
});

// ============================================================
// DAILY CHALLENGE
// ============================================================

const DAILY_COINS_PER_BLOCK = 5;
const DAILY_CORRECT_PER_COIN_BLOCK = 10;
const DAILY_STREAK_3_DAYS_COINS = 5;
const DAILY_STREAK_7_DAYS_COINS = 15;
const DAILY_STREAK_14_DAYS_COINS = 30;
const DAILY_LEVEL_UP_COINS = 15;
const DAILY_QUESTION_LIMIT = 60;

type LeagueInfo = {
  id: string;
  name: string;
  emoji: string;
  minScore: number;
  colorValue: number;
};

// Mirrors lib/services/league_service.dart's `leagues` list exactly.
const LEAGUES: LeagueInfo[] = [
  {
    id: "bronze", name: "Bronze", emoji: "🥉", minScore: 0,
    colorValue: 0xFFCD7F32,
  },
  {
    id: "silver", name: "Silver", emoji: "🥈", minScore: 300,
    colorValue: 0xFFC0C0C0,
  },
  {
    id: "gold", name: "Gold", emoji: "🥇", minScore: 700,
    colorValue: 0xFFFFD700,
  },
  {
    id: "diamond", name: "Diamond", emoji: "💎", minScore: 1200,
    colorValue: 0xFF6EC6FF,
  },
  {
    id: "master", name: "Master", emoji: "👑", minScore: 2000,
    colorValue: 0xFF9C27B0,
  },
];

/**
 * Mirrors lib/services/league_service.dart's `getLeagueFromScore`.
 * @param {number} score Player's league score.
 * @return {LeagueInfo} Matching league.
 */
function getLeagueFromScore(score: number): LeagueInfo {
  let current = LEAGUES[0];
  for (const league of LEAGUES) {
    if (score >= league.minScore) current = league;
  }
  return current;
}

/**
 * Mirrors lib/services/player_level_service.dart's `xpRequiredForLevel`.
 * @param {number} level Player level.
 * @return {number} XP required to complete that level.
 */
function xpRequiredForLevel(level: number): number {
  if (level <= 1) return 100;
  return Math.round(100 * (1.18 * (level - 1)));
}

/**
 * Mirrors lib/services/player_level_service.dart's `getLevelInfo` — only
 * the `level` field is needed here.
 * @param {number} totalXp Player's total XP.
 * @return {number} Player level for that XP total.
 */
function levelForXp(totalXp: number): number {
  let level = 1;
  let remainingXp = totalXp;

  for (;;) {
    const needed = xpRequiredForLevel(level);
    if (remainingXp < needed) return level;
    remainingXp -= needed;
    level++;
  }
}

/**
 * Mirrors DailyChallengeService's `calculateCoinsEarned`.
 * @param {number} correct Correct answers.
 * @return {number} Coins earned.
 */
function calculateDailyCoinsEarned(correct: number): number {
  return Math.floor(correct / DAILY_CORRECT_PER_COIN_BLOCK) *
    DAILY_COINS_PER_BLOCK;
}

/**
 * Mirrors DailyChallengeService's `calculateXpEarned`.
 * @param {number} correct Correct answers.
 * @param {number} totalAnswered Total questions answered.
 * @return {number} XP earned.
 */
function calculateDailyXpEarned(
  correct: number,
  totalAnswered: number
): number {
  const wrong = Math.max(totalAnswered - correct, 0);
  const baseXp = correct * 2;
  const participationXp = totalAnswered > 0 ? 5 : 0;
  const accuracyBonus = totalAnswered > 0 && wrong === 0 ? 5 : 0;
  return baseXp + participationXp + accuracyBonus;
}

/**
 * Mirrors DailyChallengeService's `calculateScore`.
 * @param {number} correct Correct answers.
 * @param {number} totalAnswered Total questions answered.
 * @param {number} streak Daily streak after this play.
 * @return {number} Daily score.
 */
function calculateDailyScore(
  correct: number,
  totalAnswered: number,
  streak: number
): number {
  const accuracyBonus = totalAnswered <= 0 ?
    0 : Math.round((correct / totalAnswered) * 100);
  const streakBonus = Math.min(streak, 30) * 2;
  return correct * 10 + accuracyBonus + streakBonus;
}

/**
 * Mirrors DailyChallengeService's `calculateStreakBonusCoins`.
 * @param {number} streak Daily streak after this play.
 * @return {number} Bonus coins for hitting a streak milestone.
 */
function calculateDailyStreakBonusCoins(streak: number): number {
  if (streak > 0 && streak % 14 === 0) return DAILY_STREAK_14_DAYS_COINS;
  if (streak > 0 && streak % 7 === 0) return DAILY_STREAK_7_DAYS_COINS;
  if (streak > 0 && streak % 3 === 0) return DAILY_STREAK_3_DAYS_COINS;
  return 0;
}

/**
 * Checks whether `dateId` (yyyy-MM-dd) is exactly one day before `today`.
 * @param {string} dateId Previous play date.
 * @param {string} today Today's date id.
 * @return {boolean} True if dateId is yesterday relative to today.
 */
function isYesterday(dateId: string, today: string): boolean {
  const last = new Date(`${dateId}T00:00:00Z`);
  const todayDate = new Date(`${today}T00:00:00Z`);
  if (isNaN(last.getTime()) || isNaN(todayDate.getTime())) return false;
  const diffDays = Math.round(
    (todayDate.getTime() - last.getTime()) / (24 * 60 * 60 * 1000)
  );
  return diffDays === 1;
}

type QuestionAnswer = { questionIndex: number; selectedIndex: number };

/**
 * Parses client-submitted per-question answers (Daily Challenge and Solo
 * Levels both use this exact shape), dropping anything malformed rather
 * than throwing — an invalid/missing entry for a given question just
 * never counts toward correct or totalAnswered below.
 * @param {unknown} raw The raw `request.data.answers` value.
 * @return {QuestionAnswer[]} The well-formed entries.
 */
function parseQuestionAnswers(raw: unknown): QuestionAnswer[] {
  if (!Array.isArray(raw)) return [];

  const out: QuestionAnswer[] = [];
  for (const entry of raw) {
    if (!entry || typeof entry !== "object") continue;
    const e = entry as Record<string, unknown>;
    const questionIndex = safeInt(e.questionIndex, -1);
    const selectedIndex = safeInt(e.selectedIndex, -1);
    if (questionIndex < 0 || selectedIndex < 0) continue;
    out.push({questionIndex, selectedIndex});
  }
  return out;
}

/**
 * Recomputes a player's real correct/totalAnswered from their actual
 * submitted per-question answers, ignoring the `correct`/`totalAnswered`
 * a client reports directly. `questions` lives on the same session doc
 * the client already reads to render the quiz (Daily Challenge's
 * createTodaySession, or Solo Levels' sessions_fixed/sessions_ai), so
 * this needs no extra fetch beyond that doc.
 * @param {unknown} questions The session doc's `questions` array.
 * @param {QuestionAnswer[]} answers The player's submitted answers, in
 * the order they were given (may repeat a questionIndex if the session's
 * question pool wrapped around during play, as Daily Challenge allows).
 * @param {number} maxAnswers Hard cap on how many answers count, matching
 * the most questions this session could legitimately contain.
 * @return {{correct: number, totalAnswered: number}} Verified counts.
 */
function computeVerifiedQuizResult(
  questions: unknown, answers: QuestionAnswer[], maxAnswers: number
): {correct: number; totalAnswered: number} {
  const list = Array.isArray(questions) ? questions : [];

  let correct = 0;
  let totalAnswered = 0;

  for (const a of answers) {
    if (totalAnswered >= maxAnswers) break;

    const q = list[a.questionIndex] as Record<string, unknown> | undefined;
    if (!q) continue;

    totalAnswered++;
    const correctIndex = safeInt(q.answerIndex ?? q.correctIndex, -1);
    if (a.selectedIndex === correctIndex) correct++;
  }

  return {correct, totalAnswered};
}

/**
 * Server-authoritative Daily Challenge reward grant, replacing
 * DailyChallengeService.saveResult's client-side transaction.
 * `dateId`/`weekId` are accepted from the client (they're just bucket
 * keys matching what createTodaySession already computed locally — not
 * economically sensitive). The client's reported `correct`/`totalAnswered`
 * are used only for a fast shape-check; the real values that determine
 * the reward are recomputed from `answers` (this player's actual selected
 * option per question) against the session doc's own stored `questions`,
 * so a modified client reporting an inflated correct count can no longer
 * affect the real result.
 */
export const submitDailyChallengeResult = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  // `correct`/`totalAnswered` are only used for a fast request-shape
  // check here — the real, reward-determining values are recomputed
  // below from `answers` against the session's own stored `questions`.
  const reportedCorrect = safeInt(request.data?.correct, -1);
  const reportedTotalAnswered = safeInt(request.data?.totalAnswered, -1);
  const answers = parseQuestionAnswers(request.data?.answers);
  const dateId = String(request.data?.dateId || "");
  const weekId = String(request.data?.weekId || "");

  if (
    reportedCorrect < 0 || reportedTotalAnswered < 0 ||
    reportedCorrect > reportedTotalAnswered ||
    reportedTotalAnswered > DAILY_QUESTION_LIMIT
  ) {
    throw new HttpsError("invalid-argument", "Invalid answer counts.");
  }

  const dateIdPattern = /^\d{4}-\d{2}-\d{2}$/;
  if (!dateIdPattern.test(dateId) || !dateIdPattern.test(weekId)) {
    throw new HttpsError("invalid-argument", "Invalid dateId/weekId.");
  }

  const userRef = db.collection("users").doc(uid);
  const dailyRef = userRef.collection("daily_challenges").doc(dateId);
  const leaderboardRef = db
    .collection("daily_leaderboards").doc(dateId)
    .collection("players").doc(uid);
  const weeklyParticipationRef = userRef
    .collection("weekly_participation").doc(weekId);
  const dailyStreakAchievementRef = userRef
    .collection("achievements").doc("daily_streak_7");
  const dailyStreak21AchievementRef = userRef
    .collection("achievements").doc("daily_streak_21");

  return db.runTransaction(async (tx) => {
    const dailySnap = await tx.get(dailyRef);
    const userSnap = await tx.get(userRef);
    const dailyStreakAchievementSnap = await tx.get(dailyStreakAchievementRef);
    const dailyStreak21AchievementSnap =
      await tx.get(dailyStreak21AchievementRef);

    const alreadyPlayed = dailySnap.data()?.played === true;

    if (alreadyPlayed) {
      const data = dailySnap.data() || {};
      const userData = userSnap.data() || {};
      const userXp = safeInt(userData.xp, 0);
      const level = levelForXp(userXp);

      return {
        saved: false,
        alreadyPlayed: true,
        correct: safeInt(data.correct, reportedCorrect),
        totalAnswered: safeInt(data.totalAnswered, reportedTotalAnswered),
        coinsEarned: safeInt(data.coinsEarned, 0),
        streak: safeInt(data.streak ?? userData.dailyStreak, 0),
        streakBonusCoins: safeInt(data.streakBonusCoins, 0),
        levelUpBonusCoins: safeInt(data.levelUpBonusCoins, 0),
        score: safeInt(data.score, 0),
        leveledUp: false,
        oldLevel: level,
        newLevel: level,
        xpEarned: safeInt(data.xpEarned, 0),
      };
    }

    const {correct, totalAnswered} = computeVerifiedQuizResult(
      dailySnap.data()?.questions, answers, DAILY_QUESTION_LIMIT
    );
    const coinsEarned = calculateDailyCoinsEarned(correct);

    const userData = userSnap.data() || {};

    const previousStreak = safeInt(userData.dailyStreak, 0);
    const lastDailyPlayed = userData.lastDailyPlayed ?
      String(userData.lastDailyPlayed) : null;

    const username = String(
      userData.username || userData.displayName || "Player"
    );
    const avatarId = String(userData.avatarId || "avatar_1");
    const frameId = String(userData.equippedFrame || "");
    const bestLeagueId = String(userData.bestLeagueId || "");

    const currentXp = safeInt(userData.xp, 0);
    const oldLevel = levelForXp(currentXp);

    const xpEarned = calculateDailyXpEarned(correct, totalAnswered);
    const newXp = currentXp + xpEarned;
    const newLevel = levelForXp(newXp);
    const leveledUp = newLevel > oldLevel;

    const levelUpBonusCoins = leveledUp ?
      (newLevel - oldLevel) * DAILY_LEVEL_UP_COINS : 0;

    const newStreak = lastDailyPlayed && isYesterday(lastDailyPlayed, dateId) ?
      previousStreak + 1 : 1;

    // Progress for this achievement is written here (rather than by a
    // client-side follow-up call) since completed/progress/claimed are
    // locked against direct client writes for this id in firestore.rules —
    // this is the one place newStreak is already computed authoritatively.
    applyPvpAchievementProgress(
      tx, uid, {id: "daily_streak_7", title: "Weekly Habit", target: 7},
      newStreak, dailyStreakAchievementSnap, userData.languageCode
    );
    applyPvpAchievementProgress(
      tx, uid,
      {id: "daily_streak_21", title: "Iron Consistency", target: 21},
      newStreak, dailyStreak21AchievementSnap, userData.languageCode
    );

    const streakBonusCoins = calculateDailyStreakBonusCoins(newStreak);
    const totalCoinsToAdd = coinsEarned + streakBonusCoins + levelUpBonusCoins;

    const score = calculateDailyScore(correct, totalAnswered, newStreak);
    const totalLeagueScore = safeInt(userData.leagueScore, 0) + score;
    const league = getLeagueFromScore(totalLeagueScore);

    const weeklyRef = db
      .collection("weekly_leagues").doc(weekId)
      .collection(league.id).doc(uid);

    const wrongAnswers = Math.max(totalAnswered - correct, 0);
    const totalQuestionsAnswered = safeInt(userData.correctAnswers, 0) +
      safeInt(userData.wrongAnswers, 0) + correct + wrongAnswers;

    tx.set(dailyRef, {
      dateId,
      played: true,
      correct,
      totalAnswered,
      coinsEarned,
      streak: newStreak,
      streakBonusCoins,
      levelUpBonusCoins,
      totalCoinsEarned: totalCoinsToAdd,
      score,
      xpEarned,
      oldLevel,
      newLevel,
      leveledUp,
      finishedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    const userPatch: Record<string, unknown> = {
      username,
      displayName: username,
      avatarId,
      dailyStreak: newStreak,
      maxDailyStreak: Math.max(previousStreak, newStreak),
      lastDailyPlayed: dateId,
      gamesPlayed: admin.firestore.FieldValue.increment(1),
      correctAnswers: admin.firestore.FieldValue.increment(correct),
      wrongAnswers: admin.firestore.FieldValue.increment(wrongAnswers),
      xp: admin.firestore.FieldValue.increment(xpEarned),
      level: newLevel,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      leagueScore: totalLeagueScore,
      leagueId: league.id,
      leagueName: league.name,
    };

    if (totalCoinsToAdd > 0) {
      userPatch.coins = admin.firestore.FieldValue.increment(totalCoinsToAdd);
    }

    const userBestDailyScore = safeInt(userData.bestDailyScore, 0);
    if (score > userBestDailyScore) {
      userPatch.bestDailyScore = score;
    }

    // Question-count achievement avatars are granted here (rather than by
    // a client-side follow-up write) since `unlockedAvatars` is locked
    // against direct client writes in firestore.rules — this is the one
    // place totalQuestionsAnswered is already computed authoritatively.
    const existingUnlockedAvatars: string[] =
      Array.isArray(userData.unlockedAvatars) ?
        userData.unlockedAvatars.map((v: unknown) => String(v)) : [];

    const newlyUnlockedAvatarIds: string[] = [];
    if (
      totalQuestionsAnswered >= 100 &&
      !existingUnlockedAvatars.includes("achievement_100_questions")
    ) {
      newlyUnlockedAvatarIds.push("achievement_100_questions");
    }
    if (
      totalQuestionsAnswered >= 1000 &&
      !existingUnlockedAvatars.includes("achievement_1000_questions")
    ) {
      newlyUnlockedAvatarIds.push("achievement_1000_questions");
    }

    if (newlyUnlockedAvatarIds.length > 0) {
      userPatch.unlockedAvatars =
        admin.firestore.FieldValue.arrayUnion(...newlyUnlockedAvatarIds);

      const latestUnlockedAvatarId =
        newlyUnlockedAvatarIds[newlyUnlockedAvatarIds.length - 1];
      userPatch.lastUnlockedAvatarId = latestUnlockedAvatarId;
      userPatch.lastUnlockedAvatarReason =
        latestUnlockedAvatarId === "achievement_1000_questions" ?
          "Answered 1000 questions" : "Answered 100 questions";
      userPatch.lastUnlockedAvatarAt =
        admin.firestore.FieldValue.serverTimestamp();
    }

    tx.set(userRef, userPatch, {merge: true});

    tx.set(leaderboardRef, {
      uid,
      username,
      displayName: username,
      avatarId,
      equippedFrame: frameId,
      bestLeagueId,
      dateId,
      correct,
      totalAnswered,
      score,
      streak: newStreak,
      coinsEarned,
      streakBonusCoins,
      levelUpBonusCoins,
      xpEarned,
      level: newLevel,
      finishedAt: admin.firestore.FieldValue.serverTimestamp(),
      leagueId: league.id,
      leagueName: league.name,
    }, {merge: true});

    tx.set(weeklyRef, {
      uid,
      username,
      displayName: username,
      avatarId,
      equippedFrame: frameId,
      bestLeagueId,
      weekId,
      leagueId: league.id,
      leagueName: league.name,
      weeklyScore: admin.firestore.FieldValue.increment(score),
      level: newLevel,
      streak: newStreak,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    tx.set(weeklyParticipationRef, {
      weekId,
      leagueId: league.id,
      leagueName: league.name,
      weeklyScore: admin.firestore.FieldValue.increment(score),
      lastDailyScore: score,
      level: newLevel,
      streak: newStreak,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    return {
      saved: true,
      alreadyPlayed: false,
      correct,
      totalAnswered,
      totalQuestionsAnswered,
      coinsEarned,
      streak: newStreak,
      streakBonusCoins,
      levelUpBonusCoins,
      score,
      leveledUp,
      oldLevel,
      newLevel,
      xpEarned,
    };
  });
});

// ============================================================
// WEEKLY LEAGUE SEASON REWARDS
// ============================================================

/**
 * Mirrors lib/services/season_service.dart's `rewardForLeague`. The
 * returned `message` is persisted permanently into the claiming user's
 * `season_history` doc (see `claimWeeklySeasonRewards` below), so it's
 * localized at claim time from that user's own `languageCode` — same as
 * every other Cloud-Function-generated notification/history string here.
 * @param {string} leagueId Weekly league id.
 * @param {number} rank Player's rank within that league for the season.
 * @param {unknown} languageCode Claiming user's stored `languageCode`.
 * @return {{coins:number, message:string}} Reward for that placement.
 */
function weeklySeasonRewardForLeague(
  leagueId: string,
  rank: number,
  languageCode: unknown
): {coins: number; message: string} {
  const baseCoins = ((): number => {
    switch (leagueId) {
    case "bronze": return 20;
    case "silver": return 40;
    case "gold": return 80;
    case "diamond": return 150;
    case "master": return 300;
    default: return 20;
    }
  })();

  let bonus = 0;
  if (rank === 1) bonus = baseCoins;
  else if (rank <= 3) bonus = Math.round(baseCoins * 0.5);
  else if (rank <= 10) bonus = Math.round(baseCoins * 0.25);

  const message = rank === 1 ?
    pickText(languageCode, "¡Bono de campeón!", "Champion bonus!") :
    rank <= 3 ?
      pickText(languageCode, "¡Bono top 3!", "Top 3 bonus!") :
      rank <= 10 ?
        pickText(languageCode, "¡Bono top 10!", "Top 10 bonus!") :
        pickText(
          languageCode, "Recompensa de liga semanal", "Weekly league reward"
        );

  return {coins: baseCoins + bonus, message};
}

/**
 * Server-authoritative weekly-league season reward claim, replacing
 * SeasonService.claimAllPendingRewards's client-side batch writes. Reads
 * `weekly_participation`/`weekly_leagues` — both now Cloud-Function-only
 * writable (via submitDailyChallengeResult), so the rank/score used here
 * can no longer be forged by the client.
 */
export const claimWeeklySeasonRewards = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const userRef = db.collection("users").doc(uid);
  const currentSeasonId = currentWeekId();

  const userSnap = await userRef.get();
  const languageCode = userSnap.data()?.languageCode;

  const participationSnap = await userRef
    .collection("weekly_participation")
    .orderBy("weekId", "desc")
    .limit(8)
    .get();

  const historySnap = await userRef.collection("season_history").get();
  const claimedSeasonIds = new Set(
    historySnap.docs
      .filter((d) => d.data().claimed === true)
      .map((d) => d.id)
  );

  type Pending = {
    seasonId: string;
    leagueId: string;
    leagueName: string;
    rank: number;
    weeklyScore: number;
    rewardCoins: number;
    rewardMessage: string;
  };

  const pending: Pending[] = [];

  for (const doc of participationSnap.docs) {
    const data = doc.data();
    const seasonId = String(data.weekId || doc.id);

    if (seasonId === currentSeasonId) continue;
    if (claimedSeasonIds.has(seasonId)) continue;

    const leagueId = String(data.leagueId || "bronze");
    const leagueName = String(data.leagueName || "Bronze");
    const weeklyScore = safeInt(data.weeklyScore, 0);
    if (weeklyScore <= 0) continue;

    const betterPlayersSnap = await db
      .collection("weekly_leagues").doc(seasonId)
      .collection(leagueId)
      .where("weeklyScore", ">", weeklyScore)
      .count().get();
    const rank = (betterPlayersSnap.data().count || 0) + 1;

    const reward = weeklySeasonRewardForLeague(leagueId, rank, languageCode);

    pending.push({
      seasonId,
      leagueId,
      leagueName,
      rank,
      weeklyScore,
      rewardCoins: reward.coins,
      rewardMessage: reward.message,
    });
  }

  if (pending.length === 0) {
    return {claimedCount: 0, totalCoins: 0};
  }

  const batch = db.batch();
  let totalCoins = 0;

  for (const reward of pending) {
    const historyRef = userRef.collection("season_history").doc(
      reward.seasonId
    );

    batch.set(historyRef, {
      seasonId: reward.seasonId,
      leagueId: reward.leagueId,
      leagueName: reward.leagueName,
      rank: reward.rank,
      weeklyScore: reward.weeklyScore,
      rewardCoins: reward.rewardCoins,
      rewardMessage: reward.rewardMessage,
      claimed: true,
      claimedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});

    totalCoins += reward.rewardCoins;
  }

  if (totalCoins > 0) {
    batch.set(userRef, {
      coins: admin.firestore.FieldValue.increment(totalCoins),
      lastSeasonRewardClaimed: pending[pending.length - 1].seasonId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, {merge: true});
  }

  await batch.commit();

  return {claimedCount: pending.length, totalCoins};
});

/**
 * Relays every newly created in-app notification (friend requests,
 * achievements, season rewards, match invites/results, streak reminders...)
 * as a push notification, if the target user has a saved FCM token.
 */
export const sendPushOnNotificationCreated = onDocumentCreated(
  "users/{uid}/notifications/{notificationId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const uid = event.params.uid;
    const userSnap = await db.collection("users").doc(uid).get();
    const token = userSnap.data()?.fcmToken;

    if (!token || typeof token !== "string") return;

    const title = String(data.title || "TriviaIA");
    const body = String(data.body || "");

    try {
      await admin.messaging().send({
        token,
        notification: {title, body},
        data: {type: String(data.type || "")},
      });
    } catch (e) {
      console.warn(`Push send failed for user ${uid}: ${e}`);
    }
  }
);

/**
 * Once a day, reminds users with an active Daily Challenge streak who
 * haven't played yet today, so they don't lose it silently.
 */
export const notifyStreakAtRisk = onSchedule(
  {schedule: "0 19 * * *", timeZone: "America/Lima"},
  async () => {
    const now = new Date();
    const dateId = `${now.getFullYear()}-${String(
      now.getMonth() + 1
    ).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;

    const snap = await db
      .collection("users")
      .where("dailyStreak", ">", 0)
      .get();

    await Promise.all(
      snap.docs.map(async (doc) => {
        const data = doc.data();
        if (data.lastDailyPlayed === dateId) return;

        const streak = safeInt(data.dailyStreak, 0);

        await doc.ref.collection("notifications").add({
          type: "streak_at_risk",
          title: pickText(
            data.languageCode,
            "Tu racha está en riesgo",
            "Your streak is at risk"
          ),
          body: pickText(
            data.languageCode,
            `Tienes una racha de ${streak} días. Juega el Daily ` +
              "Challenge de hoy antes de perderla.",
            `You have a ${streak}-day streak. Play today's Daily ` +
              "Challenge before you lose it."
          ),
          data: {streak},
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      })
    );
  }
);

// ============================================================
// LOGIN STREAK BONUS
//
// Mirrors user_bootstrap.dart's per-launch login-streak logic. `loginStreak`
// and `lastLoginDate` are now protected fields — previously a client could
// write them directly (e.g. rewind `lastLoginDate` to "yesterday" and bump
// `loginStreak` by hand) to repeatedly claim the 3/7/14-day coin bonus.
// `todayDateId` is trusted from the client only as a bucket key (same as
// submitDailyChallengeResult's dateId/weekId) — the streak math and coin
// amount are entirely server-computed.
// ============================================================

const LOGIN_STREAK_3_DAYS_COINS = 3;
const LOGIN_STREAK_7_DAYS_COINS = 8;
const LOGIN_STREAK_14_DAYS_COINS = 15;

/**
 * Mirrors user_bootstrap.dart's `_loginStreakBonusCoins`.
 * @param {number} streak Login streak after today's login.
 * @return {number} Bonus coins for hitting a streak milestone.
 */
function loginStreakBonusCoins(streak: number): number {
  if (streak > 0 && streak % 14 === 0) return LOGIN_STREAK_14_DAYS_COINS;
  if (streak > 0 && streak % 7 === 0) return LOGIN_STREAK_7_DAYS_COINS;
  if (streak > 0 && streak % 3 === 0) return LOGIN_STREAK_3_DAYS_COINS;
  return 0;
}

export const claimLoginStreakBonus = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const todayDateId = String(request.data?.todayDateId || "");
  if (!/^\d{4}-\d{2}-\d{2}$/.test(todayDateId)) {
    throw new HttpsError("invalid-argument", "Invalid todayDateId.");
  }

  const userRef = db.collection("users").doc(uid);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.data() || {};

    const lastLoginDate = data.lastLoginDate ?
      String(data.lastLoginDate) : null;
    const previousStreak = safeInt(data.loginStreak, 0);

    if (lastLoginDate === todayDateId) {
      return {
        streak: previousStreak,
        coinsEarned: 0,
        alreadyProcessedToday: true,
      };
    }

    const newStreak = lastLoginDate && isYesterday(lastLoginDate, todayDateId) ?
      previousStreak + 1 : 1;

    const coinsEarned = loginStreakBonusCoins(newStreak);

    const patch: Record<string, unknown> = {
      loginStreak: newStreak,
      lastLoginDate: todayDateId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (coinsEarned > 0) {
      patch.coins = admin.firestore.FieldValue.increment(coinsEarned);
      patch.loginStreakCelebrationPending = true;
      patch.loginStreakCelebrationCoins = coinsEarned;
    }

    tx.set(userRef, patch, {merge: true});

    return {streak: newStreak, coinsEarned, alreadyProcessedToday: false};
  });
});

// ============================================================
// SOLO LEVEL REWARDS
//
// Mirrors level_play_screen.dart's `_saveProgress` transaction. `coins`/
// `xp` are protected fields in firestore.rules, so the reward grant (and
// the progress/achievement bookkeeping that determines whether a grant is
// due) moved here in full. `levelCount` — used only to decide the
// "completed all levels in this category" bonus — is read from the
// authoritative fixed_categories/ai_topics doc rather than trusted from
// the client, closing a minor "claim the completion bonus early" gap.
// ============================================================

const SOLO_PERFECT_LEVEL_COINS = 3;
const SOLO_GREAT_LEVEL_COINS = 2;
const SOLO_GOOD_LEVEL_COINS = 1;
const COMPLETE_FIXED_CATEGORY_COINS = 10;
const AI_LEVELS_PER_TOPIC = 10;
const AI_QUESTIONS_PER_LEVEL = 10;
const AI_INITIAL_GENERATED_LEVELS = 2;
const AI_GENERATION_BUFFER_LEVELS = 2;
const AI_MODEL = "claude-haiku-4-5";

/**
 * Mirrors level_play_screen.dart's `_calculateLevelRewards`.
 * @param {number} correct Correct answers in this level attempt.
 * @param {number} total Total questions in this level attempt.
 * @return {{xp:number, coins:number}} Reward for this attempt.
 */
function calculateLevelRewards(
  correct: number,
  total: number
): {xp: number; coins: number} {
  const pct = total === 0 ? 0 : correct / total;
  const xp = correct * 10;

  let coins = 0;
  if (pct >= 0.9) coins = SOLO_PERFECT_LEVEL_COINS;
  else if (pct >= 0.7) coins = SOLO_GREAT_LEVEL_COINS;
  else if (pct >= 0.4) coins = SOLO_GOOD_LEVEL_COINS;

  return {xp, coins};
}

export const submitSoloLevelResult = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const isAiTopic = request.data?.isAiTopic === true;
  const categoryId = String(request.data?.categoryId || "");
  const aiTopicId = request.data?.aiTopicId ?
    String(request.data.aiTopicId) : null;
  const levelNumber = safeInt(request.data?.levelNumber, -1);
  // `correct`/`total` are only used for a fast request-shape check here —
  // the real, reward-determining values are recomputed below from
  // `answers` against the level session's own stored `questions`.
  const reportedCorrect = safeInt(request.data?.correct, -1);
  const reportedTotal = safeInt(request.data?.total, -1);
  const answers = parseQuestionAnswers(request.data?.answers);

  if (
    levelNumber < 1 || reportedCorrect < 0 || reportedTotal < 0 ||
    reportedCorrect > reportedTotal
  ) {
    throw new HttpsError("invalid-argument", "Invalid level result.");
  }
  if (isAiTopic && !aiTopicId) {
    throw new HttpsError("invalid-argument", "Missing aiTopicId.");
  }
  if (!isAiTopic && !categoryId) {
    throw new HttpsError("invalid-argument", "Missing categoryId.");
  }

  const userRef = db.collection("users").doc(uid);
  const progressRef = isAiTopic ?
    userRef.collection("progress_ai").doc(aiTopicId as string) :
    userRef.collection("progress_fixed").doc(categoryId);
  const soloLevelsAchievementRef = userRef
    .collection("achievements").doc("solo_levels_10");
  const soloLevels25AchievementRef = userRef
    .collection("achievements").doc("solo_levels_25");
  const categoriesExploredAchievementRef = userRef
    .collection("achievements").doc("categories_explored_5");

  const sessionId = isAiTopic ?
    `${aiTopicId}_${levelNumber}` : `${categoryId}_${levelNumber}`;
  const sessionRef = userRef
    .collection(isAiTopic ? "sessions_ai" : "sessions_fixed").doc(sessionId);

  let levelCount = 0;
  if (isAiTopic) {
    const topicSnap = await userRef
      .collection("ai_topics").doc(aiTopicId as string).get();
    const topicData = topicSnap.data();
    levelCount = safeInt(
      topicData?.targetLevels ?? topicData?.levelsCount,
      AI_LEVELS_PER_TOPIC
    );
  } else {
    const catSnap = await db
      .collection("fixed_categories").doc(categoryId).get();
    levelCount = safeInt(catSnap.data()?.levelCount, 0);
  }

  return db.runTransaction(async (tx) => {
    const progressSnap = await tx.get(progressRef);
    const userSnap = await tx.get(userRef);
    const soloLevelsAchievementSnap = await tx.get(soloLevelsAchievementRef);
    const soloLevels25AchievementSnap =
      await tx.get(soloLevels25AchievementRef);
    const categoriesExploredAchievementSnap =
      await tx.get(categoriesExploredAchievementRef);
    const sessionSnap = await tx.get(sessionRef);

    const sessionQuestions = sessionSnap.data()?.questions;
    const total = Array.isArray(sessionQuestions) ?
      sessionQuestions.length : 0;
    const {correct} = computeVerifiedQuizResult(
      sessionQuestions, answers, total
    );

    const percent = total === 0 ? 0 : correct / total;
    const passedLevel = percent >= 0.4;
    const {xp: levelXp, coins: levelCoins} =
      calculateLevelRewards(correct, total);

    const prev = progressSnap.data();
    const userData = userSnap.data() || {};
    const prevUserXp = safeInt(userData.xp, 0);

    const prevCompleted = new Set<number>(
      ((prev?.completedLevels as unknown[]) || [])
        .map((e) => safeInt(e, 0))
    );

    const prevLevelStats: Record<string, Record<string, unknown>> = {
      ...((prev?.levelStats as Record<string, Record<string, unknown>>) ||
        {}),
    };

    const migratedPassedLevels = new Set<number>();
    for (const [key, stat] of Object.entries(prevLevelStats)) {
      const level = parseInt(key, 10);
      const statPercent = Number(stat?.percent ?? 0);
      if (!isNaN(level) && statPercent >= 0.4) {
        migratedPassedLevels.add(level);
      }
    }

    const prevPassed = new Set<number>(
      prev?.passedLevels ?
        (prev.passedLevels as unknown[]).map((e) => safeInt(e, 0)) :
        Array.from(migratedPassedLevels)
    );

    const wasAlreadyPlayed = prevCompleted.has(levelNumber);
    const wasAlreadyPassed = prevPassed.has(levelNumber);
    const categoryWasUnexplored = prevPassed.size === 0;

    prevCompleted.add(levelNumber);
    if (passedLevel) prevPassed.add(levelNumber);

    const levelKey = String(levelNumber);
    const oldStat = prevLevelStats[levelKey] || {};
    const oldPercent = Number(oldStat.percent ?? -1);

    if (percent >= oldPercent) {
      prevLevelStats[levelKey] = {
        correct,
        total,
        percent,
        passed: passedLevel,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
    }

    const newlyPassed = passedLevel && !wasAlreadyPassed;
    // Replaying a level once its one-time coin payout is spent still earns
    // a small XP trickle (20%, floor 1) instead of flatly zero — XP has no
    // cap and no coin equivalent (see player_level_service.dart), so this
    // gives completionist players something to keep working toward without
    // reopening the coin-farming exploit the one-time gate exists to block.
    const grantedXp = wasAlreadyPlayed ?
      Math.max(1, Math.floor(levelXp * 0.2)) : levelXp;
    let grantedCoins = newlyPassed ? levelCoins : 0;
    const shouldEnsureAiBuffer = isAiTopic && newlyPassed;

    // Progress for this achievement is written here (rather than by a
    // client-side follow-up call) since completed/progress/claimed are
    // locked against direct client writes for this id in firestore.rules —
    // newlyPassed is already computed authoritatively above, from this
    // same transaction's own tracked completedLevels/passedLevels.
    if (newlyPassed) {
      const currentSoloLevelsProgress = safeInt(
        soloLevelsAchievementSnap.data()?.progress, 0
      );
      applyPvpAchievementProgress(
        tx, uid, {id: "solo_levels_10", title: "Solo Explorer", target: 10},
        currentSoloLevelsProgress + 1, soloLevelsAchievementSnap,
        userData.languageCode
      );

      const currentSoloLevels25Progress = safeInt(
        soloLevels25AchievementSnap.data()?.progress, 0
      );
      applyPvpAchievementProgress(
        tx, uid, {id: "solo_levels_25", title: "Solo Master", target: 25},
        currentSoloLevels25Progress + 1, soloLevels25AchievementSnap,
        userData.languageCode
      );
    }

    // A category counts as "explored" the moment its first level is passed
    // — `categoriesExploredCount` on the user doc is the running total
    // (cheaper than re-scanning the whole progress_fixed subcollection on
    // every level completion) and only ever grows here.
    const categoryNewlyExplored =
      !isAiTopic && categoryWasUnexplored && passedLevel;

    const newCategoriesExploredCount = categoryNewlyExplored ?
      safeInt(userData.categoriesExploredCount, 0) + 1 : null;

    if (newCategoriesExploredCount !== null) {
      applyPvpAchievementProgress(
        tx, uid,
        {id: "categories_explored_5", title: "Curious Mind", target: 5},
        newCategoriesExploredCount, categoriesExploredAchievementSnap,
        userData.languageCode
      );
    }

    const completedAll = levelCount > 0 && prevPassed.size >= levelCount;
    const rewardGranted = prev?.categoryRewardGranted === true;
    const categoryBonusGranted = completedAll && !rewardGranted;

    if (categoryBonusGranted) {
      grantedCoins += COMPLETE_FIXED_CATEGORY_COINS;
    }

    const progressPatch: Record<string, unknown> = {
      completedLevels: Array.from(prevCompleted).sort((a, b) => a - b),
      passedLevels: Array.from(prevPassed).sort((a, b) => a - b),
      levelStats: prevLevelStats,
      lastScore: {correct, total, percent, passed: passedLevel, levelNumber},
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    };

    if (grantedXp > 0 || grantedCoins > 0) {
      progressPatch.lastLevelReward = {
        levelNumber,
        xp: grantedXp,
        coins: grantedCoins,
        passed: passedLevel,
        grantedAt: admin.firestore.FieldValue.serverTimestamp(),
      };
    }

    if (completedAll) {
      progressPatch.completedAllLevels = true;
      if (categoryBonusGranted) {
        progressPatch.categoryRewardGranted = true;
        progressPatch.rewardGrantedAt =
          admin.firestore.FieldValue.serverTimestamp();
      }
    }

    tx.set(progressRef, progressPatch, {merge: true});

    if (
      grantedXp > 0 || grantedCoins > 0 || newCategoriesExploredCount !== null
    ) {
      tx.set(
        userRef,
        {
          ...(grantedXp > 0 ?
            {xp: admin.firestore.FieldValue.increment(grantedXp)} : {}),
          ...(grantedCoins > 0 ?
            {coins: admin.firestore.FieldValue.increment(grantedCoins)} : {}),
          ...(newCategoriesExploredCount !== null ?
            {categoriesExploredCount: newCategoriesExploredCount} : {}),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
    }

    return {
      grantedXp,
      grantedCoins,
      passed: passedLevel,
      newlyPassed,
      userTotalXp: prevUserXp + grantedXp,
      completedAll,
      shouldEnsureAiBuffer,
    };
  });
});

// ============================================================
// ACHIEVEMENTS
//
// Only the final reward claim moves here — setProgress/incrementProgress
// keep writing achievements/{id} straight from the client (not economy
// protected). Mirrors achievement_service.dart's `achievements` list
// exactly; keep both in sync.
// ============================================================

type AchievementRewardDef = {
  id: string;
  rewardCoins: number;
  rewardXp: number;
};

const ACHIEVEMENT_REWARDS: AchievementRewardDef[] = [
  {id: "first_pvp_win", rewardCoins: 10, rewardXp: 20},
  {id: "pvp_wins_10", rewardCoins: 40, rewardXp: 80},
  {id: "pvp_wins_25", rewardCoins: 100, rewardXp: 150},
  {id: "pvp_streak_5", rewardCoins: 50, rewardXp: 100},
  {id: "solo_levels_10", rewardCoins: 30, rewardXp: 60},
  {id: "solo_levels_25", rewardCoins: 60, rewardXp: 100},
  {id: "daily_streak_7", rewardCoins: 50, rewardXp: 100},
  {id: "daily_streak_21", rewardCoins: 90, rewardXp: 150},
  {id: "friends_5", rewardCoins: 25, rewardXp: 50},
  {id: "friends_10", rewardCoins: 50, rewardXp: 80},
  {id: "weekly_topics_completed_3", rewardCoins: 60, rewardXp: 100},
  {id: "categories_explored_5", rewardCoins: 40, rewardXp: 70},
];

export const claimAchievementReward = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const achievementId = String(request.data?.achievementId || "");
  const achievement = ACHIEVEMENT_REWARDS.find((a) => a.id === achievementId);

  if (!achievement) {
    throw new HttpsError("invalid-argument", "Achievement not found.");
  }

  const userRef = db.collection("users").doc(uid);
  const achievementRef = userRef.collection("achievements").doc(
    achievementId
  );

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(achievementRef);
    const data = snap.data();

    if (!data) {
      throw new HttpsError("failed-precondition", "Achievement not started.");
    }
    if (data.completed !== true) {
      throw new HttpsError(
        "failed-precondition", "Achievement not completed yet."
      );
    }
    if (data.claimed === true) {
      throw new HttpsError("failed-precondition", "Reward already claimed.");
    }

    tx.set(
      userRef,
      {
        coins: admin.firestore.FieldValue.increment(achievement.rewardCoins),
        xp: admin.firestore.FieldValue.increment(achievement.rewardXp),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    tx.set(
      achievementRef,
      {
        claimed: true,
        claimedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    return {
      rewardCoins: achievement.rewardCoins,
      rewardXp: achievement.rewardXp,
    };
  });
});

// ============================================================
// LIFE SYSTEM
//
// Only the coin-for-lifeUnits purchase moves here — lifeUnits/regen
// ticking (tryConsumeLevelEntry, tryConsumeWrongAnswer, refreshLives)
// don't touch `coins`/`xp` and keep working straight from the client.
// Cost is a server constant, never trusted from the client.
// ============================================================

const BUY_FULL_LIFE_COST = 10;
const DEFAULT_MAX_LIFE_UNITS = 10;
const DEFAULT_LIFE_REGEN_SECONDS = 150;
const UNITS_PER_LIFE = 2;

/**
 * Mirrors life_service.dart's `_stateFromData` (lifeUnits/maxLifeUnits
 * portion only — buyFullLife doesn't need the countdown fields).
 * @param {Record<string, unknown>} data User document data.
 * @return {{lifeUnits:number, maxLifeUnits:number}} Current life state,
 * accounting for regen elapsed since the last tick.
 */
function computeLifeUnits(
  data: Record<string, unknown>
): {lifeUnits: number; maxLifeUnits: number} {
  const now = Date.now();

  let lifeUnits = safeInt(data.lifeUnits, DEFAULT_MAX_LIFE_UNITS);
  const maxLifeUnits = safeInt(data.maxLifeUnits, DEFAULT_MAX_LIFE_UNITS);
  const lifeRegenSeconds = safeInt(
    data.lifeRegenSeconds, DEFAULT_LIFE_REGEN_SECONDS
  );

  const lastTick = data.lastLifeTickAt as
    FirebaseFirestore.Timestamp | undefined;
  const lastTickMs = lastTick ? lastTick.toMillis() : now;

  if (lifeUnits < maxLifeUnits) {
    const elapsedSeconds = Math.floor((now - lastTickMs) / 1000);
    if (elapsedSeconds >= lifeRegenSeconds) {
      const recoveredUnits = Math.floor(elapsedSeconds / lifeRegenSeconds);
      lifeUnits = Math.min(lifeUnits + recoveredUnits, maxLifeUnits);
    }
  } else {
    lifeUnits = maxLifeUnits;
  }

  return {lifeUnits, maxLifeUnits};
}

export const buyFullLife = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const userRef = db.collection("users").doc(uid);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(userRef);
    const data = snap.data() || {};

    const coins = safeInt(data.coins, 0);
    const {lifeUnits, maxLifeUnits} = computeLifeUnits(data);

    if (coins < BUY_FULL_LIFE_COST) {
      throw new HttpsError("failed-precondition", "Not enough coins.");
    }
    if (lifeUnits >= maxLifeUnits) {
      throw new HttpsError("failed-precondition", "Life is already full.");
    }

    const newLifeUnits = Math.min(lifeUnits + UNITS_PER_LIFE, maxLifeUnits);
    const newCoins = coins - BUY_FULL_LIFE_COST;

    tx.set(
      userRef,
      {
        coins: newCoins,
        lifeUnits: newLifeUnits,
        maxLifeUnits,
        lastLifeTickAt: admin.firestore.Timestamp.now(),
      },
      {merge: true}
    );

    return {lifeUnits: newLifeUnits, coins: newCoins};
  });
});

// ============================================================
// COIN PURCHASES (IAP)
//
// Structure only — Google Play Console / App Store Connect aren't set up
// yet, so there is no real receipt to verify against. This function must
// stay fail-closed (reject every call) until that's wired up; it must
// NEVER credit coins based on the client's say-so alone, the same way no
// other economy path in this file trusts a client-reported amount.
//
// Mirrors economy_service.dart's `EconomyService.coinPacks` exactly —
// keep both in sync. Ids must match the products configured in each
// store once those accounts exist.
// ============================================================

const COIN_PACKS: Record<string, number> = {
  "coins_pack_small": 100,
  "coins_pack_ai_topic": 600,
  "coins_pack_medium": 1500,
  "coins_pack_large": 4000,
};

export const verifyCoinPurchase = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const productId = String(request.data?.productId || "");
  const source = String(request.data?.source || "");
  const verificationData = String(request.data?.verificationData || "");

  const coins = COIN_PACKS[productId];
  if (!coins) {
    throw new HttpsError("invalid-argument", "Unknown coin pack.");
  }
  if (!source || !verificationData) {
    throw new HttpsError("invalid-argument", "Missing verification data.");
  }

  // TODO(store-setup): once both store accounts exist and the packs
  // above are configured as real products, verify `verificationData`
  // against the actual store before granting `coins`:
  //  - source === "google_play": call the Google Play Developer API's
  //    purchases.products.get with a service-account credential,
  //    confirm purchaseState is "purchased", and acknowledge/consume the
  //    token so it can't be replayed.
  //  - source === "app_store": call the App Store Server API (or the
  //    legacy verifyReceipt endpoint) with the app's shared secret,
  //    confirm the transaction is valid, and track its transaction id in
  //    Firestore so the same receipt can't be replayed for a second
  //    payout.
  // Only after that check passes should this run a transaction crediting
  // `coins` to the user doc — exactly like every other reward path in
  // this file, never trust a client-supplied amount directly.
  throw new HttpsError(
    "failed-precondition",
    "Coin purchases aren't enabled yet."
  );
});

// ============================================================
// AI TOPICS ECONOMY
//
// Content generation is deterministic mock data (not a real AI call), so
// each function generates first and only charges after the generation
// succeeds — if generation throws, nothing was ever charged, so there's
// no refund case to handle for new topics. `refundAiTopicCost` remains as
// a safety net solely for topics created before this migration that may
// still be sitting in a `failed`/`invalid` state from the old two-step
// client flow.
// ============================================================

const CREATE_AI_TOPIC_COST = 600;
const REGENERATE_AI_QUESTIONS_COST = 150;
const EXPAND_AI_TOPIC_COST = 300;
const MAX_AI_TOPICS_PER_USER = 20;
const FIRST_AI_TOPIC_FREE_PASSES = 1;

// Mirrors ai_topic_service.dart's `_reservedTopicNames` exactly.
const RESERVED_TOPIC_NAMES = new Set([
  "movies", "movie", "cine", "history", "historia", "science", "ciencia",
  "geography", "geografia", "geografía", "books", "libros", "video games",
  "videogames", "videojuegos", "sports", "deportes",
]);

/**
 * Mirrors ai_topic_service.dart's `normalizeTopicTitle`.
 * @param {string} title Raw title.
 * @return {string} Normalized title.
 */
function normalizeTopicTitle(title: string): string {
  return title.trim().toLowerCase().replace(/\s+/g, " ");
}

interface GeneratedAiQuestion {
  q: string;
  options: string[];
  answerIndex: number;
  explanation: string;
}

/**
 * Difficulty label for a given AI-topic level number (1-10, scaled easy
 * to hard), localized via the recipient's stored languageCode.
 * @param {number} levelNumber Level number (1-10).
 * @param {unknown} languageCode Recipient's stored languageCode.
 * @return {string} Localized difficulty label.
 */
function aiLevelDifficultyLabel(
  levelNumber: number,
  languageCode: unknown
): string {
  if (levelNumber <= 3) return pickText(languageCode, "fácil", "easy");
  if (levelNumber <= 7) return pickText(languageCode, "intermedio", "medium");
  return pickText(languageCode, "difícil", "hard");
}

/**
 * Calls Claude Haiku 4.5 to generate one level's worth of trivia questions
 * for a user-created AI topic and validates the shape of the response.
 * Retries once on a malformed/incomplete response before giving up.
 * @param {string} title Topic title (e.g. "Dinosaurios").
 * @param {number} levelNumber Level number (1-10) — scales difficulty.
 * @param {unknown} languageCode Recipient's stored languageCode.
 * @return {Promise<GeneratedAiQuestion[]>} Exactly AI_QUESTIONS_PER_LEVEL
 * validated questions.
 */
async function requestAiQuestionsFromClaude(
  title: string,
  levelNumber: number,
  languageCode: unknown
): Promise<GeneratedAiQuestion[]> {
  const client = new Anthropic({apiKey: anthropicApiKey.value()});
  const outputLanguage = pickText(languageCode, "Spanish", "English");
  const difficulty = aiLevelDifficultyLabel(levelNumber, languageCode);

  const prompt = `Generate exactly ${AI_QUESTIONS_PER_LEVEL} multiple-choice ` +
    `trivia questions about "${title}", at ${difficulty} difficulty ` +
    `(this is level ${levelNumber} of ${AI_LEVELS_PER_TOPIC}; difficulty ` +
    "should scale up with the level number). Write every question, " +
    `option, and explanation in ${outputLanguage}. Each question needs ` +
    "exactly 4 answer options with exactly one correct answer. Vary the " +
    "position of the correct answer across questions instead of always " +
    "using the same index. Do not repeat questions or trivially reword " +
    "the same fact twice.";

  const schema = {
    type: "object",
    properties: {
      questions: {
        type: "array",
        items: {
          type: "object",
          properties: {
            q: {type: "string"},
            options: {type: "array", items: {type: "string"}},
            answerIndex: {type: "integer"},
            explanation: {type: "string"},
          },
          required: ["q", "options", "answerIndex", "explanation"],
          additionalProperties: false,
        },
      },
    },
    required: ["questions"],
    additionalProperties: false,
  };

  let lastError: unknown;

  for (let attempt = 0; attempt < 2; attempt++) {
    try {
      const response = await client.messages.create({
        model: AI_MODEL,
        max_tokens: 4096,
        messages: [{role: "user", content: prompt}],
        output_config: {format: {type: "json_schema", schema}},
      });

      const block = response.content[0];
      if (!block || block.type !== "text") {
        throw new Error("Unexpected response block type from Claude.");
      }

      const parsed = JSON.parse(block.text) as {
        questions?: GeneratedAiQuestion[];
      };
      const questions = parsed.questions || [];

      if (questions.length !== AI_QUESTIONS_PER_LEVEL) {
        throw new Error(
          `Expected ${AI_QUESTIONS_PER_LEVEL} questions, got ` +
          `${questions.length}.`
        );
      }

      for (const question of questions) {
        if (
          typeof question.q !== "string" || question.q.trim() === "" ||
          !Array.isArray(question.options) ||
          question.options.length !== 4 ||
          question.options.some((o) => typeof o !== "string") ||
          !Number.isInteger(question.answerIndex) ||
          question.answerIndex < 0 || question.answerIndex > 3
        ) {
          throw new Error("Malformed question from Claude.");
        }
      }

      return questions;
    } catch (error) {
      lastError = error;
    }
  }

  console.error("AI topic question generation failed", lastError);
  throw new HttpsError(
    "internal", "No se pudo generar el tema con IA. Intenta de nuevo."
  );
}

/**
 * Generates one level's worth of real AI trivia questions via Claude
 * Haiku 4.5 and writes them to Firestore. Writes the same schema the old
 * mock generator used, so no client-side rendering changes are needed.
 * @param {FirebaseFirestore.DocumentReference} topicRef Topic document ref.
 * @param {number} levelNumber Level to (re)generate.
 * @param {string} title Topic title, used as the generation subject.
 * @param {unknown} languageCode Recipient's stored languageCode.
 * @return {Promise<void>} Resolves once the batch commits.
 */
async function generateAiTopicLevel(
  topicRef: FirebaseFirestore.DocumentReference,
  levelNumber: number,
  title: string,
  languageCode: unknown
): Promise<void> {
  const questions = await requestAiQuestionsFromClaude(
    title, levelNumber, languageCode
  );

  const levelRef = topicRef.collection("levels").doc(`level_${levelNumber}`);
  const batch = db.batch();

  batch.set(levelRef, {
    levelNumber,
    title: `Level ${levelNumber}`,
    questionsCount: AI_QUESTIONS_PER_LEVEL,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  questions.forEach((question, index) => {
    batch.set(levelRef.collection("questions").doc(`q_${index + 1}`), {
      q: question.q,
      options: question.options,
      answerIndex: question.answerIndex,
      explanation: question.explanation,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  });

  await batch.commit();
}

export const createAiTopic = onCall({
  secrets: AI_SECRETS,
}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const cleanTitle = String(request.data?.title || "").trim();

  if (cleanTitle.length < 3) {
    throw new HttpsError(
      "invalid-argument", "Escribe un tema más específico."
    );
  }
  if (cleanTitle.length > 60) {
    throw new HttpsError(
      "invalid-argument", "El tema no puede superar 60 caracteres."
    );
  }

  const normalizedTitle = normalizeTopicTitle(cleanTitle);

  if (RESERVED_TOPIC_NAMES.has(normalizedTitle)) {
    throw new HttpsError(
      "failed-precondition", "Ese tema ya existe como categoría oficial."
    );
  }

  const topicsCol = db.collection("users").doc(uid).collection("ai_topics");

  const existing = await topicsCol
    .where("normalizedTitle", "==", normalizedTitle)
    .where("status", "in", ["pending_generation", "ready"])
    .limit(1)
    .get();

  if (!existing.empty) {
    throw new HttpsError(
      "already-exists", "Ya tienes un tema con ese nombre."
    );
  }

  const activeTopicsSnap = await topicsCol
    .where("status", "in", ["pending_generation", "ready", "failed"])
    .limit(MAX_AI_TOPICS_PER_USER)
    .get();

  if (activeTopicsSnap.size >= MAX_AI_TOPICS_PER_USER) {
    throw new HttpsError(
      "resource-exhausted",
      `You can have up to ${MAX_AI_TOPICS_PER_USER} AI topics. ` +
      "Delete one to create another."
    );
  }

  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  const userData = userSnap.data() || {};

  const coins = safeInt(userData.coins, 0);
  const freePasses = safeInt(
    userData.freeTopicPasses, FIRST_AI_TOPIC_FREE_PASSES
  );
  const usesFreePass = freePasses > 0;
  const cost = usesFreePass ? 0 : CREATE_AI_TOPIC_COST;

  if (!usesFreePass && coins < cost) {
    throw new HttpsError(
      "failed-precondition", `Necesitas ${cost} monedas para crear un tema IA.`
    );
  }

  const topicRef = topicsCol.doc();

  for (let level = 1; level <= AI_INITIAL_GENERATED_LEVELS; level++) {
    await generateAiTopicLevel(
      topicRef, level, cleanTitle, userData.languageCode
    );
  }

  await topicRef.set({
    topicId: topicRef.id,
    title: cleanTitle,
    normalizedTitle,
    status: "ready",
    source: "ai",
    targetLevels: AI_LEVELS_PER_TOPIC,
    levelCount: AI_LEVELS_PER_TOPIC,
    levelsCount: AI_LEVELS_PER_TOPIC,
    generatedLevels: AI_INITIAL_GENERATED_LEVELS,
    questionsCount: AI_INITIAL_GENERATED_LEVELS * AI_QUESTIONS_PER_LEVEL,
    generationMode: "claude_haiku_4_5",
    generationCostCoins: cost,
    usedFreePass: usesFreePass,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  await userRef.set(
    {
      ...(usesFreePass ?
        {freeTopicPasses: admin.firestore.FieldValue.increment(-1)} :
        {coins: admin.firestore.FieldValue.increment(-cost)}),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true}
  );

  return {topicId: topicRef.id};
});

export const regenerateAiTopicQuestions = onCall({
  secrets: AI_SECRETS,
}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const topicId = String(request.data?.topicId || "");
  if (!topicId) {
    throw new HttpsError("invalid-argument", "Missing topicId.");
  }

  const topicRef = db.collection("users").doc(uid)
    .collection("ai_topics").doc(topicId);
  const topicSnap = await topicRef.get();
  const topicData = topicSnap.data();

  if (!topicData) {
    throw new HttpsError("not-found", "Este tema ya no existe.");
  }
  if (topicData.status !== "ready") {
    throw new HttpsError(
      "failed-precondition", "El tema todavía se está preparando."
    );
  }

  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  const coins = safeInt(userSnap.data()?.coins, 0);

  if (coins < REGENERATE_AI_QUESTIONS_COST) {
    throw new HttpsError(
      "failed-precondition",
      `Necesitas ${REGENERATE_AI_QUESTIONS_COST} monedas para regenerar ` +
      "las preguntas."
    );
  }

  const generatedLevels = safeInt(topicData.generatedLevels, 0);
  const title = String(topicData.title || "Custom Topic");
  const languageCode = userSnap.data()?.languageCode;

  for (let level = 1; level <= generatedLevels; level++) {
    await generateAiTopicLevel(topicRef, level, title, languageCode);
  }

  return db.runTransaction(async (tx) => {
    const freshSnap = await tx.get(userRef);
    const freshCoins = safeInt(freshSnap.data()?.coins, 0);

    if (freshCoins < REGENERATE_AI_QUESTIONS_COST) {
      throw new HttpsError(
        "failed-precondition",
        `Necesitas ${REGENERATE_AI_QUESTIONS_COST} monedas para regenerar ` +
        "las preguntas."
      );
    }

    tx.set(
      userRef,
      {
        coins: admin.firestore.FieldValue.increment(
          -REGENERATE_AI_QUESTIONS_COST
        ),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    return {success: true};
  });
});

export const expandAiTopic = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const topicId = String(request.data?.topicId || "");
  if (!topicId) {
    throw new HttpsError("invalid-argument", "Missing topicId.");
  }

  const topicRef = db.collection("users").doc(uid)
    .collection("ai_topics").doc(topicId);
  const topicSnap = await topicRef.get();
  const topicData = topicSnap.data();

  if (!topicData) {
    throw new HttpsError("not-found", "Este tema ya no existe.");
  }
  if (topicData.status !== "ready") {
    throw new HttpsError(
      "failed-precondition", "El tema todavía se está preparando."
    );
  }

  const userRef = db.collection("users").doc(uid);
  const userSnap = await userRef.get();
  const coins = safeInt(userSnap.data()?.coins, 0);

  if (coins < EXPAND_AI_TOPIC_COST) {
    throw new HttpsError(
      "failed-precondition",
      `Necesitas ${EXPAND_AI_TOPIC_COST} monedas para ampliar este tema.`
    );
  }

  const currentTarget = safeInt(topicData.targetLevels, AI_LEVELS_PER_TOPIC);
  const newTarget = currentTarget + AI_LEVELS_PER_TOPIC;

  return db.runTransaction(async (tx) => {
    const freshSnap = await tx.get(userRef);
    const freshCoins = safeInt(freshSnap.data()?.coins, 0);

    if (freshCoins < EXPAND_AI_TOPIC_COST) {
      throw new HttpsError(
        "failed-precondition",
        `Necesitas ${EXPAND_AI_TOPIC_COST} monedas para ampliar este tema.`
      );
    }

    tx.set(
      topicRef,
      {
        targetLevels: newTarget,
        levelCount: newTarget,
        levelsCount: newTarget,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    tx.set(
      userRef,
      {
        coins: admin.firestore.FieldValue.increment(-EXPAND_AI_TOPIC_COST),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    return {newTarget};
  });
});

/**
 * Server-side replacement for the old client-side `ensureAiTopicBuffer` —
 * generates real AI levels ahead of the player as they progress, instead
 * of trusting the client to write mock question content directly. Mirrors
 * ai_topic_service.dart's buffering math (generate up to
 * `completedLevel + AI_GENERATION_BUFFER_LEVELS`, clamped to
 * `targetLevels`) but calls Claude server-side via `generateAiTopicLevel`.
 */
export const ensureAiTopicLevelsGenerated = onCall({
  secrets: AI_SECRETS,
}, async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const topicId = String(request.data?.topicId || "");
  if (!topicId) {
    throw new HttpsError("invalid-argument", "Missing topicId.");
  }
  const completedLevel = safeInt(request.data?.completedLevel, 0);

  const topicRef = db.collection("users").doc(uid)
    .collection("ai_topics").doc(topicId);
  const topicSnap = await topicRef.get();
  const topicData = topicSnap.data();

  if (!topicData || topicData.status !== "ready") {
    return {generatedLevels: safeInt(topicData?.generatedLevels, 0)};
  }

  const generatedLevels = safeInt(topicData.generatedLevels, 0);
  const targetLevels = safeInt(topicData.targetLevels, AI_LEVELS_PER_TOPIC);
  const desiredGeneratedLevel = Math.max(0, Math.min(
    completedLevel + AI_GENERATION_BUFFER_LEVELS, targetLevels
  ));

  if (generatedLevels >= desiredGeneratedLevel) {
    return {generatedLevels};
  }

  const userSnap = await db.collection("users").doc(uid).get();
  const languageCode = userSnap.data()?.languageCode;
  const title = String(topicData.title || "Custom Topic");

  for (
    let level = generatedLevels + 1;
    level <= desiredGeneratedLevel;
    level++
  ) {
    await generateAiTopicLevel(topicRef, level, title, languageCode);
  }

  await topicRef.set({
    generatedLevels: desiredGeneratedLevel,
    questionsCount: desiredGeneratedLevel * AI_QUESTIONS_PER_LEVEL,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  }, {merge: true});

  return {generatedLevels: desiredGeneratedLevel};
});

/**
 * Safety net for topics created under the old client-side flow that may
 * still be stuck `failed`/`invalid` from before this migration. Mirrors
 * ai_topic_service.dart's `_refundAiTopicCostIfNeeded` exactly, including
 * the `costRefunded` guard against a double refund on repeated retries.
 */
export const refundAiTopicCost = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const topicId = String(request.data?.topicId || "");
  if (!topicId) {
    throw new HttpsError("invalid-argument", "Missing topicId.");
  }

  const topicRef = db.collection("users").doc(uid)
    .collection("ai_topics").doc(topicId);
  const userRef = db.collection("users").doc(uid);

  return db.runTransaction(async (tx) => {
    const topicSnap = await tx.get(topicRef);
    const topicData = topicSnap.data();

    if (!topicData || topicData.costRefunded === true) {
      return {refunded: false};
    }

    const usedFreePass = topicData.usedFreePass === true;
    const cost = safeInt(topicData.generationCostCoins, 0);

    if (!usedFreePass && cost <= 0) {
      return {refunded: false};
    }

    tx.set(
      userRef,
      {
        ...(usedFreePass ?
          {freeTopicPasses: admin.firestore.FieldValue.increment(1)} : {}),
        ...(!usedFreePass && cost > 0 ?
          {coins: admin.firestore.FieldValue.increment(cost)} : {}),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    tx.set(topicRef, {costRefunded: true}, {merge: true});

    return {refunded: true};
  });
});

// A question hitting this many reports (from replays of the same level, or
// any future case where reports on the same questionId accumulate) gets
// excluded from that level's question pool going forward — see
// reportAiQuestion below.
const AI_QUESTION_REPORT_THRESHOLD = 3;

const AI_QUESTION_REPORT_REASONS = new Set([
  "wrong_answer",
  "confusing",
  "inappropriate",
  "other",
]);

/**
 * Logs a player's report of a bad AI-generated question (wrong answer
 * marked correct, confusing, inappropriate, etc.) to a global collection
 * for reviewing AI-generation quality, and — once the same questionId
 * within a level has been reported [AI_QUESTION_REPORT_THRESHOLD] times —
 * invalidates that level's cached session so the next play rebuilds the
 * question set excluding it (see level_play_screen.dart's _ensureSession,
 * which already filters by this same reportedQuestionCounts field).
 */
export const reportAiQuestion = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const topicId = String(request.data?.topicId || "");
  const levelNumber = safeInt(request.data?.levelNumber, -1);
  const questionId = String(request.data?.questionId || "");
  const questionText = String(request.data?.questionText || "");
  const reason = String(request.data?.reason || "");
  const details = String(request.data?.details || "").slice(0, 500);

  if (
    !topicId || levelNumber < 1 || !questionId ||
    !AI_QUESTION_REPORT_REASONS.has(reason)
  ) {
    throw new HttpsError("invalid-argument", "Invalid report.");
  }

  const userRef = db.collection("users").doc(uid);
  const topicRef = userRef.collection("ai_topics").doc(topicId);
  const levelRef = topicRef.collection("levels").doc(`level_${levelNumber}`);
  const sessionRef = userRef.collection("sessions_ai")
    .doc(`${topicId}_${levelNumber}`);
  const reportRef = db.collection("ai_question_reports").doc();

  const topicSnap = await topicRef.get();
  if (!topicSnap.exists) {
    throw new HttpsError("not-found", "Topic not found.");
  }

  return db.runTransaction(async (tx) => {
    const levelSnap = await tx.get(levelRef);
    const reportedCounts: Record<string, number> = {
      ...(levelSnap.data()?.reportedQuestionCounts || {}),
    };

    const newCount = safeInt(reportedCounts[questionId], 0) + 1;
    reportedCounts[questionId] = newCount;

    tx.set(reportRef, {
      uid,
      topicId,
      levelNumber,
      questionId,
      questionText,
      reason,
      details,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    tx.set(
      levelRef,
      {reportedQuestionCounts: reportedCounts},
      {merge: true}
    );

    const excluded = newCount >= AI_QUESTION_REPORT_THRESHOLD;
    if (excluded) {
      tx.delete(sessionRef);
    }

    return {reportCount: newCount, excluded};
  });
});

// ============================================================
// WEEKLY TOPIC
//
// `users/{uid}/weekly_participation/{weekId}` is now fully
// Cloud-Function-only (write:false) since submitDailyChallengeResult also
// writes there for weekly-league scoring — so weekly-topic progress and
// reward claims move here too, even though only the reward-claim half
// actually touches `coins`.
// ============================================================

// Mirrors lib/features/home/home_screen.dart's Weekly Topic card and the
// 9 fixed_categories seeded by tools/seed_categories.js — rotating through
// real, already-seeded question pools instead of authoring separate
// weekly-only content. Each entry's rewardAvatarId matches an AvatarInfo in
// lib/services/avatar_service.dart's weeklyAvatars list.
const WEEKLY_TOPIC_CATEGORIES: {
  categoryId: string;
  title: string;
  descriptionEs: string;
  descriptionEn: string;
  rewardAvatarId: string;
}[] = [
  {
    categoryId: "cine", title: "Cine Week",
    descriptionEs: "Completa niveles de cine y gana recompensas.",
    descriptionEn: "Complete cinema levels and earn rewards.",
    rewardAvatarId: "weekly_cine",
  },
  {
    categoryId: "historia", title: "History Week",
    descriptionEs: "Completa niveles de historia y gana recompensas.",
    descriptionEn: "Complete history levels and earn rewards.",
    rewardAvatarId: "weekly_history",
  },
  {
    categoryId: "ciencia", title: "Science Week",
    descriptionEs: "Completa niveles de ciencia y gana recompensas.",
    descriptionEn: "Complete science levels and earn rewards.",
    rewardAvatarId: "weekly_science",
  },
  {
    categoryId: "musica", title: "Music Week",
    descriptionEs: "Completa niveles de música y gana recompensas.",
    descriptionEn: "Complete music levels and earn rewards.",
    rewardAvatarId: "weekly_music",
  },
  {
    categoryId: "arte", title: "Art Week",
    descriptionEs: "Completa niveles de arte y gana recompensas.",
    descriptionEn: "Complete art levels and earn rewards.",
    rewardAvatarId: "weekly_art",
  },
  {
    categoryId: "geografia", title: "Geography Week",
    descriptionEs: "Completa niveles de geografía y gana recompensas.",
    descriptionEn: "Complete geography levels and earn rewards.",
    rewardAvatarId: "weekly_geography",
  },
  {
    categoryId: "deportes", title: "Sports Week",
    descriptionEs: "Completa niveles de deportes y gana recompensas.",
    descriptionEn: "Complete sports levels and earn rewards.",
    rewardAvatarId: "weekly_sports",
  },
  {
    categoryId: "videojuegos", title: "Gaming Week",
    descriptionEs: "Completa niveles de videojuegos y gana recompensas.",
    descriptionEn: "Complete video game levels and earn rewards.",
    rewardAvatarId: "weekly_videogames",
  },
  {
    categoryId: "libros", title: "Books Week",
    descriptionEs: "Completa niveles de libros y gana recompensas.",
    descriptionEn: "Complete book levels and earn rewards.",
    rewardAvatarId: "weekly_books",
  },
];

const WEEKLY_TOPIC_REWARD_COINS = 10;

// Weekly Topic used to just reuse Solo's own fixed levels 1-10 for the
// chosen category — meaning a repeat occurrence of the same category
// (every 9 weeks) showed the exact same 10 question sets a player had
// already seen in Solo. These constants back a decoupled flow instead:
// rounds draw a fresh random sample from the category's difficulty pools
// (mirrors Daily Challenge's own sourcing), and progress is measured in
// correct answers rather than levels completed.
const WEEKLY_TOPIC_ROUND_SIZE = 10;
const WEEKLY_TOPIC_COIN_THRESHOLD = 25;
const WEEKLY_TOPIC_COMPLETION_THRESHOLD = 50;

/**
 * Deterministic weekly rotation index — a pure function of the week's
 * Monday date, so no extra "which week did we last rotate" bookkeeping is
 * needed and re-running this function mid-week is a safe no-op.
 * @param {string} weekId Monday-of-week date string (YYYY-MM-DD).
 * @param {number} categoryCount Number of rotation slots.
 * @return {number} Index into WEEKLY_TOPIC_CATEGORIES for this week.
 */
function weeklyTopicCategoryIndex(
  weekId: string,
  categoryCount: number
): number {
  const monday = new Date(`${weekId}T00:00:00Z`);
  const epoch = new Date("2024-01-01T00:00:00Z");
  const diffWeeks = Math.floor(
    (monday.getTime() - epoch.getTime()) / (7 * 24 * 60 * 60 * 1000)
  );
  return ((diffWeeks % categoryCount) + categoryCount) % categoryCount;
}

/**
 * Rotates weekly_topics/current to the next category every Monday, so the
 * Weekly Topic card never goes stale waiting on a manual update — see the
 * dead-end audit that flagged this doc as having no automated writer
 * before this function existed.
 */
export const rotateWeeklyTopic = onSchedule(
  {schedule: "0 0 * * 1", timeZone: "America/Lima"},
  async () => {
    const weekId = currentWeekId();
    const topicRef = db.collection("weekly_topics").doc("current");
    const snap = await topicRef.get();

    if (snap.data()?.weekId === weekId) return;

    const idx = weeklyTopicCategoryIndex(
      weekId, WEEKLY_TOPIC_CATEGORIES.length
    );
    const chosen = WEEKLY_TOPIC_CATEGORIES[idx];

    await topicRef.set({
      active: true,
      weekId,
      title: chosen.title,
      description_es: chosen.descriptionEs,
      description_en: chosen.descriptionEn,
      categoryId: chosen.categoryId,
      rewardCoins: WEEKLY_TOPIC_REWARD_COINS,
      rewardAvatarId: chosen.rewardAvatarId,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
);

/**
 * Server-authoritative Weekly Topic round grant. Draws for the round come
 * from the client (see WeeklyTopicService.loadRandomRound), each tagged
 * with its own difficulty/questionId — this refetches each one directly
 * from fixed_pools and compares against its stored answerIndex, so a
 * modified client reporting an inflated correct count can't affect the
 * real result, exactly like submitDailyChallengeResult/
 * submitSoloLevelResult.
 */
export const submitWeeklyTopicRound = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const weekId = String(request.data?.weekId || "");
  const categoryId = String(request.data?.categoryId || "");
  const rawAnswers = Array.isArray(request.data?.answers) ?
    request.data.answers : [];

  if (
    !weekId || !categoryId || rawAnswers.length === 0 ||
    rawAnswers.length > WEEKLY_TOPIC_ROUND_SIZE
  ) {
    throw new HttpsError("invalid-argument", "Invalid round submission.");
  }

  const topicSnap = await db.collection("weekly_topics").doc("current").get();
  const topicData = topicSnap.data();
  if (
    !topicData || String(topicData.weekId || "") !== weekId ||
    String(topicData.categoryId || "") !== categoryId
  ) {
    throw new HttpsError(
      "failed-precondition", "This weekly topic is no longer active."
    );
  }

  type RoundAnswer = {
    difficulty: number; questionId: string; selectedIndex: number;
  };

  const answers: RoundAnswer[] = rawAnswers.map(
    (a: Record<string, unknown>): RoundAnswer => ({
      difficulty: safeInt(a?.sourceDifficulty, 0),
      questionId: String(a?.sourceQuestionId || ""),
      selectedIndex: safeInt(a?.selectedIndex, -1),
    })
  ).filter((a: RoundAnswer) =>
    a.questionId && [1, 2, 3].includes(a.difficulty)
  );

  if (answers.length === 0) {
    throw new HttpsError("invalid-argument", "No valid answers submitted.");
  }

  const questionSnaps = await Promise.all(answers.map((a) =>
    db.collection("fixed_pools").doc(categoryId)
      .collection(`difficulty_${a.difficulty}`).doc("pool")
      .collection("questions").doc(a.questionId).get()
  ));

  let correct = 0;
  const answeredQuestionIds: string[] = [];

  answers.forEach((a, i) => {
    const data = questionSnaps[i].data();
    if (!data) return;

    answeredQuestionIds.push(a.questionId);
    const correctIndex = safeInt(data.answerIndex ?? data.correctIndex, -1);
    if (a.selectedIndex === correctIndex) correct++;
  });

  const totalAnswered = answeredQuestionIds.length;

  const userRef = db.collection("users").doc(uid);
  const participationRef = userRef
    .collection("weekly_participation").doc(weekId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(participationRef);
    const data = snap.data() || {};

    const newCorrectAnswers = safeInt(data.correctAnswers, 0) + correct;
    const newTotalAnswered = safeInt(data.totalAnswered, 0) + totalAnswered;

    const usedQuestionIds = new Set<string>(
      ((data.usedQuestionIds as unknown[]) || []).map((e) => String(e))
    );
    answeredQuestionIds.forEach((id) => usedQuestionIds.add(id));

    tx.set(
      participationRef,
      {
        weekId,
        categoryId,
        correctAnswers: newCorrectAnswers,
        totalAnswered: newTotalAnswered,
        usedQuestionIds: Array.from(usedQuestionIds),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        ...(snap.exists ?
          {} : {createdAt: admin.firestore.FieldValue.serverTimestamp()}),
      },
      {merge: true}
    );

    return {correct, totalAnswered, correctAnswers: newCorrectAnswers};
  });
});

export const claimWeeklyTopicCoinReward = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const weekId = String(request.data?.weekId || "");
  if (!weekId) {
    throw new HttpsError("invalid-argument", "Missing weekId.");
  }

  const topicSnap = await db.collection("weekly_topics").doc("current").get();
  const topicData = topicSnap.data();

  if (!topicData) {
    throw new HttpsError("not-found", "No active weekly topic.");
  }
  if (String(topicData.weekId || "") !== weekId) {
    throw new HttpsError(
      "failed-precondition", "This weekly topic is no longer active."
    );
  }

  const rewardCoins = safeInt(topicData.rewardCoins, 0);

  const userRef = db.collection("users").doc(uid);
  const participationRef = userRef
    .collection("weekly_participation").doc(weekId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(participationRef);
    const data = snap.data() || {};

    const correctAnswers = safeInt(data.correctAnswers, 0);
    const claimed = data.coinRewardClaimed === true;

    if (correctAnswers < WEEKLY_TOPIC_COIN_THRESHOLD || claimed) {
      return {claimed: false, rewardCoins: 0};
    }

    tx.set(
      participationRef,
      {
        coinRewardClaimed: true,
        coinRewardClaimedAt: admin.firestore.FieldValue.serverTimestamp(),
        coinRewardCoins: rewardCoins,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    tx.set(
      userRef,
      {
        coins: admin.firestore.FieldValue.increment(rewardCoins),
        lastWeeklyTopicRewardWeekId: weekId,
        lastWeeklyTopicRewardCoins: rewardCoins,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    return {claimed: true, rewardCoins};
  });
});

export const claimWeeklyTopicCompletionReward = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const weekId = String(request.data?.weekId || "");
  if (!weekId) {
    throw new HttpsError("invalid-argument", "Missing weekId.");
  }

  const topicSnap = await db.collection("weekly_topics").doc("current").get();
  const topicData = topicSnap.data();

  if (!topicData) {
    throw new HttpsError("not-found", "No active weekly topic.");
  }
  if (String(topicData.weekId || "") !== weekId) {
    throw new HttpsError(
      "failed-precondition", "This weekly topic is no longer active."
    );
  }

  const rewardAvatarId = String(topicData.rewardAvatarId || "");
  if (!rewardAvatarId) {
    throw new HttpsError(
      "failed-precondition", "No avatar reward configured."
    );
  }

  const userRef = db.collection("users").doc(uid);
  const participationRef = userRef
    .collection("weekly_participation").doc(weekId);
  const weeklyTopicsAchievementRef = userRef
    .collection("achievements").doc("weekly_topics_completed_3");

  return db.runTransaction(async (tx) => {
    const participationSnap = await tx.get(participationRef);
    const participationData = participationSnap.data() || {};

    const correctAnswers = safeInt(participationData.correctAnswers, 0);
    const claimed = participationData.completionRewardClaimed === true;

    if (correctAnswers < WEEKLY_TOPIC_COMPLETION_THRESHOLD || claimed) {
      return {claimed: false};
    }

    const userSnap = await tx.get(userRef);
    const userData = userSnap.data() || {};
    const weeklyTopicsAchievementSnap =
      await tx.get(weeklyTopicsAchievementRef);

    const unlockedAvatars = new Set<string>(
      ((userData.unlockedAvatars as unknown[]) || []).map((e) => String(e))
    );
    const alreadyUnlocked = unlockedAvatars.has(rewardAvatarId);
    unlockedAvatars.add(rewardAvatarId);

    const newWeeklyTopicsCompletedCount =
      safeInt(userData.weeklyTopicsCompletedCount, 0) + 1;
    applyPvpAchievementProgress(
      tx, uid,
      {
        id: "weekly_topics_completed_3",
        title: "Weekly Explorer",
        target: 3,
      },
      newWeeklyTopicsCompletedCount, weeklyTopicsAchievementSnap,
      userData.languageCode
    );

    tx.set(
      participationRef,
      {
        completionRewardClaimed: true,
        completionRewardClaimedAt: admin.firestore.FieldValue.serverTimestamp(),
        completionRewardAvatarId: rewardAvatarId,
        completionRewardAlreadyUnlocked: alreadyUnlocked,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    tx.set(
      userRef,
      {
        unlockedAvatars: Array.from(unlockedAvatars).sort(),
        lastUnlockedAvatarId: rewardAvatarId,
        lastUnlockedAvatarReason: "Weekly Topic completed",
        lastUnlockedAvatarAt: admin.firestore.FieldValue.serverTimestamp(),
        lastWeeklyTopicCompletionRewardWeekId: weekId,
        weeklyTopicsCompletedCount: newWeeklyTopicsCompletedCount,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );

    return {claimed: true, rewardAvatarId, alreadyUnlocked};
  });
});

// ============================================================
// FRIENDS
//
// users/{uid}/friends/{friendId} is Cloud-Function-only (write:false) —
// the rule that let either side of a friendship write there (needed so
// accepting could write both mirror docs in one transaction) also let a
// client fabricate a "friend" doc directly, with no real request/accept
// ever happening, inflating friend counts and polluting friend lists.
// sendFriendRequest/rejectFriendRequest stay client-side (they only touch
// friend_requests/sent_friend_requests, which aren't part of this trust
// boundary); only the two writes that touch `friends` itself move here.
// ============================================================

/**
 * Recomputes and applies the friends_5 achievement's progress for a
 * player, using their real friends subcollection count as the source of
 * truth (rather than a client-reported number).
 * @param {string} uid Player id.
 */
async function syncFriendsAchievementProgress(uid: string): Promise<void> {
  const friendsSnap = await db
    .collection("users").doc(uid).collection("friends").get();
  const friendCount = friendsSnap.size;

  const achRef = db.collection("users").doc(uid)
    .collection("achievements").doc("friends_5");
  const ach10Ref = db.collection("users").doc(uid)
    .collection("achievements").doc("friends_10");

  await db.runTransaction(async (tx) => {
    const achSnap = await tx.get(achRef);
    const ach10Snap = await tx.get(ach10Ref);
    const userSnap = await tx.get(db.collection("users").doc(uid));
    const languageCode = userSnap.data()?.languageCode;

    applyPvpAchievementProgress(
      tx, uid, {id: "friends_5", title: "Social Player", target: 5},
      friendCount, achSnap, languageCode
    );
    applyPvpAchievementProgress(
      tx, uid, {id: "friends_10", title: "Social Circle", target: 10},
      friendCount, ach10Snap, languageCode
    );
  });
}

export const acceptFriendRequest = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const requesterUid = String(request.data?.requesterUid || "");
  if (!requesterUid || requesterUid === uid) {
    throw new HttpsError("invalid-argument", "Invalid request.");
  }

  const myRef = db.collection("users").doc(uid);
  const requesterRef = db.collection("users").doc(requesterUid);
  const requestRef = myRef.collection("friend_requests").doc(requesterUid);
  const myFriendRef = myRef.collection("friends").doc(requesterUid);
  const requesterFriendRef = requesterRef.collection("friends").doc(uid);
  const requesterSentRequestRef = requesterRef
    .collection("sent_friend_requests").doc(uid);

  await db.runTransaction(async (tx) => {
    const mySnap = await tx.get(myRef);
    const requesterSnap = await tx.get(requesterRef);
    const requestSnap = await tx.get(requestRef);

    if (!requestSnap.exists) {
      throw new HttpsError(
        "failed-precondition", "The request no longer exists."
      );
    }

    const requestStatus = String(requestSnap.data()?.status || "pending");
    if (requestStatus !== "pending") {
      throw new HttpsError(
        "failed-precondition", "The request was already processed."
      );
    }

    const myData = mySnap.data() || {};
    const requesterData = requesterSnap.data() || {};

    const myDisplayName = String(
      myData.displayName || myData.username || `Player${uid.slice(0, 4)}`
    );
    const requesterDisplayName = String(
      requesterData.displayName || requesterData.username ||
        `Player${requesterUid.slice(0, 4)}`
    );

    const now = admin.firestore.FieldValue.serverTimestamp();

    tx.set(myFriendRef, {
      uid: requesterUid,
      displayName: requesterDisplayName,
      username: String(requesterData.username || requesterDisplayName),
      avatarId: String(requesterData.avatarId || "avatar_1"),
      equippedFrame: requesterData.equippedFrame || "bronze",
      bestLeagueId: requesterData.bestLeagueId || "bronze",
      pvpRating: requesterData.pvpRating || 1000,
      pvpLeagueId: requesterData.pvpLeagueId || "bronze",
      pvpLeagueName: requesterData.pvpLeagueName || "Bronze",
      pvpLeagueEmoji: requesterData.pvpLeagueEmoji || "🥉",
      createdAt: now,
      updatedAt: now,
    }, {merge: true});

    tx.set(requesterFriendRef, {
      uid,
      displayName: myDisplayName,
      username: String(myData.username || myDisplayName),
      avatarId: String(myData.avatarId || "avatar_1"),
      equippedFrame: myData.equippedFrame || "bronze",
      bestLeagueId: myData.bestLeagueId || "bronze",
      pvpRating: myData.pvpRating || 1000,
      pvpLeagueId: myData.pvpLeagueId || "bronze",
      pvpLeagueName: myData.pvpLeagueName || "Bronze",
      pvpLeagueEmoji: myData.pvpLeagueEmoji || "🥉",
      createdAt: now,
      updatedAt: now,
    }, {merge: true});

    tx.update(requestRef, {status: "accepted", updatedAt: now});
    tx.set(requesterSentRequestRef, {status: "accepted", updatedAt: now},
      {merge: true});
  });

  await Promise.all([
    syncFriendsAchievementProgress(uid),
    syncFriendsAchievementProgress(requesterUid),
  ]);

  return {accepted: true};
});

export const removeFriend = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const friendUid = String(request.data?.friendUid || "");
  if (!friendUid || friendUid === uid) {
    throw new HttpsError("invalid-argument", "Invalid friend.");
  }

  const myFriendRef = db.collection("users").doc(uid)
    .collection("friends").doc(friendUid);
  const theirFriendRef = db.collection("users").doc(friendUid)
    .collection("friends").doc(uid);

  await db.runTransaction(async (tx) => {
    tx.delete(myFriendRef);
    tx.delete(theirFriendRef);
  });

  return {removed: true};
});
