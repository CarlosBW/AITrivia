import * as admin from "firebase-admin";
import {setGlobalOptions} from "firebase-functions/v2";
import {
  onDocumentCreated,
  onDocumentUpdated,
} from "firebase-functions/v2/firestore";
import {onSchedule} from "firebase-functions/v2/scheduler";
import {onCall, HttpsError} from "firebase-functions/v2/https";

setGlobalOptions({maxInstances: 10});

admin.initializeApp();

const db = admin.firestore();

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
 */
function applyPvpAchievementProgress(
  tx: FirebaseFirestore.Transaction,
  uid: string,
  achievement: PvpAchievementDef,
  progress: number,
  snap: FirebaseFirestore.DocumentSnapshot
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
    tx.set(db.collection("users").doc(uid).collection("notifications").doc(), {
      type: "achievement_completed",
      title: "Achievement completed",
      body: `You completed "${achievement.title}". Claim your reward.`,
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

      const hostScore = safeInt(freshHost.score, 0);
      const guestScore = safeInt(freshGuest.score, 0);

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

      const [hostFirstWinSnap, hostWins10Snap, hostStreak5Snap] =
        hostAchSnaps;
      const [guestFirstWinSnap, guestWins10Snap, guestStreak5Snap] =
        guestAchSnaps;

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
          hostFirstWinSnap
        );
        applyPvpAchievementProgress(
          tx, hostUid, PVP_ACHIEVEMENTS[1],
          safeInt(hostUser.wins1v1, 0) + (hostWon ? 1 : 0), hostWins10Snap
        );
        applyPvpAchievementProgress(
          tx, hostUid, PVP_ACHIEVEMENTS[2], hostReward.newStreak,
          hostStreak5Snap
        );

        applyPvpAchievementProgress(
          tx, guestUid, PVP_ACHIEVEMENTS[0],
          safeInt(guestUser.wins1v1, 0) + (guestWon ? 1 : 0),
          guestFirstWinSnap
        );
        applyPvpAchievementProgress(
          tx, guestUid, PVP_ACHIEVEMENTS[1],
          safeInt(guestUser.wins1v1, 0) + (guestWon ? 1 : 0), guestWins10Snap
        );
        applyPvpAchievementProgress(
          tx, guestUid, PVP_ACHIEVEMENTS[2], guestReward.newStreak,
          guestStreak5Snap
        );

        ratingResults[hostUid] = {
          oldRating: hostOldRating,
          newRating: hostReward.newRating,
          ratingDelta: hostReward.ratingDelta,
          xpEarned: hostReward.xpEarned,
          coinsEarned: hostReward.coinsEarned,
          winStreak: hostReward.newStreak,
          oldLeagueName: hostReward.oldLeague.name,
          newLeagueName: hostReward.newLeague.name,
        };

        ratingResults[guestUid] = {
          oldRating: guestOldRating,
          newRating: guestReward.newRating,
          ratingDelta: guestReward.ratingDelta,
          xpEarned: guestReward.xpEarned,
          coinsEarned: guestReward.coinsEarned,
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
            coins: admin.firestore.FieldValue.increment(hostReward.coinsEarned),
            lastRankedXpEarned: hostReward.xpEarned,
            lastRankedCoinsEarned: hostReward.coinsEarned,
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
              guestReward.coinsEarned
            ),
            lastRankedXpEarned: guestReward.xpEarned,
            lastRankedCoinsEarned: guestReward.coinsEarned,
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
          safeInt(hostUser.wins1v1, 0) + (hostWon ? 1 : 0), hostFirstWinSnap
        );
        applyPvpAchievementProgress(
          tx, hostUid, PVP_ACHIEVEMENTS[1],
          safeInt(hostUser.wins1v1, 0) + (hostWon ? 1 : 0), hostWins10Snap
        );
        applyPvpAchievementProgress(
          tx, hostUid, PVP_ACHIEVEMENTS[2], hostNewStreak, hostStreak5Snap
        );
        applyPvpAchievementProgress(
          tx, guestUid, PVP_ACHIEVEMENTS[0],
          safeInt(guestUser.wins1v1, 0) + (guestWon ? 1 : 0), guestFirstWinSnap
        );
        applyPvpAchievementProgress(
          tx, guestUid, PVP_ACHIEVEMENTS[1],
          safeInt(guestUser.wins1v1, 0) + (guestWon ? 1 : 0), guestWins10Snap
        );
        applyPvpAchievementProgress(
          tx, guestUid, PVP_ACHIEVEMENTS[2], guestNewStreak, guestStreak5Snap
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
              hostWon ? winReward : 0
            ),
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
              guestWon ? winReward : 0
            ),
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

      const challengerScore = safeInt(fresh.challenger?.score, 0);
      const challengedScore = safeInt(fresh.challenged?.score, 0);

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
            challengerWon ? winReward : 0
          ),
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
            challengedWon ? winReward : 0
          ),
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
        title: string,
        body: string
      ): void => {
        tx.set(
          db.collection("users").doc(targetUid).collection("notifications")
            .doc(),
          {
            type: "match_result",
            title,
            body,
            data: {matchId},
            read: false,
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
          }
        );
      };

      if (draw) {
        notify(
          challengerUid, "Async match finished",
          `Your match against ${challengedName} ended in a draw.`
        );
        notify(
          challengedUid, "Async match finished",
          `Your match against ${challengerName} ended in a draw.`
        );
      } else {
        const loserUid = challengerWon ? challengedUid : challengerUid;
        const winnerOpponentName = challengerWon ?
          challengedName : challengerName;
        const loserOpponentName = loserUid === challengerUid ?
          challengedName : challengerName;

        notify(
          winnerUid as string, "You won!",
          `You won your async match against ${winnerOpponentName}.`
        );
        notify(
          loserUid, "Match finished",
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

    const rewardForLeague = (league: PvpLeagueInfo): number => {
      switch (league.id) {
      case "master": return 80;
      case "diamond": return 40;
      case "platinum": return 20;
      case "gold": return 10;
      case "silver": return 5;
      default: return 2;
      }
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
        rewardCoins: rewardForLeague(bestLeague),
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

/**
 * Server-authoritative Daily Challenge reward grant, replacing
 * DailyChallengeService.saveResult's client-side transaction.
 * `dateId`/`weekId` are accepted from the client (they're just bucket
 * keys matching what createTodaySession already computed locally — not
 * economically sensitive), but `correct`/`totalAnswered` only ever
 * determine the reward through this function's own math, never through a
 * client-supplied coins/xp value.
 */
export const submitDailyChallengeResult = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }

  const correct = safeInt(request.data?.correct, -1);
  const totalAnswered = safeInt(request.data?.totalAnswered, -1);
  const dateId = String(request.data?.dateId || "");
  const weekId = String(request.data?.weekId || "");

  if (
    correct < 0 || totalAnswered < 0 || correct > totalAnswered ||
    totalAnswered > DAILY_QUESTION_LIMIT
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
  const coinsEarned = calculateDailyCoinsEarned(correct);

  return db.runTransaction(async (tx) => {
    const dailySnap = await tx.get(dailyRef);
    const userSnap = await tx.get(userRef);

    const alreadyPlayed = dailySnap.data()?.played === true;

    if (alreadyPlayed) {
      const data = dailySnap.data() || {};
      const userData = userSnap.data() || {};
      const userXp = safeInt(userData.xp, 0);
      const level = levelForXp(userXp);

      return {
        saved: false,
        alreadyPlayed: true,
        correct: safeInt(data.correct, correct),
        totalAnswered: safeInt(data.totalAnswered, totalAnswered),
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
 * Mirrors lib/services/season_service.dart's `rewardForLeague`.
 * @param {string} leagueId Weekly league id.
 * @param {number} rank Player's rank within that league for the season.
 * @return {{coins:number, message:string}} Reward for that placement.
 */
function weeklySeasonRewardForLeague(
  leagueId: string,
  rank: number
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
    "Champion bonus!" :
    rank <= 3 ? "Top 3 bonus!" : rank <= 10 ? "Top 10 bonus!" :
      "Weekly league reward";

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

    const reward = weeklySeasonRewardForLeague(leagueId, rank);

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
          title: "Tu racha está en riesgo",
          body:
            `Tienes una racha de ${streak} días. Juega el Daily ` +
            "Challenge de hoy antes de perderla.",
          data: {streak},
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      })
    );
  }
);
