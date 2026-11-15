/**
 * Rewarded ads: what watching one pays, how many count per day, and
 * whether a "this player watched an ad" callback really came from AdMob.
 *
 * The app never reports a watched ad itself. AdMob's servers call ours
 * (server-side verification) with a signed query string, and that call is
 * the only thing that pays out: a reward the client could claim would be
 * free coins for anyone who can replay a request.
 *
 * Kept out of index.ts so all of it can be unit-tested without
 * firebase-admin, the network or an AdMob account.
 */

import {createVerify} from "node:crypto";

/** What a player can earn by watching an ad. */
export type AdRewardKind = "lives" | "coins";

/**
 * What each reward pays and how many of them count per day.
 *
 * Lives come three at a time: one regenerates in three minutes, so a
 * thirty-second ad for a single life would be a poor trade next to
 * waiting. Coins are few on purpose — a level pays one to three.
 *
 * Mirrored by `AdRewards` in lib/services/ad_rewards.dart, which shows
 * these figures; `test/services/ad_rewards_sync_test.dart` keeps the two
 * from drifting apart.
 */
export const AD_REWARDS = {
  lives: {dailyCap: 5, lifeUnits: 6},
  coins: {dailyCap: 5, coins: 15},
} as const;

/**
 * Which reward an ad was shown for, from the `custom_data` the app
 * attached to it.
 * @param {unknown} customData The callback's `custom_data`.
 * @return {AdRewardKind | null} The reward, or null if it names none.
 */
export function adRewardKind(customData: unknown): AdRewardKind | null {
  return customData === "lives" || customData === "coins" ? customData : null;
}

/** A reward callback, taken apart. */
export interface RewardCallback {
  /** The part of the query string AdMob signed. */
  signedContent: string;
  /** The signature over it. */
  signature: Buffer;
  /** Which of AdMob's keys signed it. */
  keyId: string;
  /** The ad unit the ad was shown from (`ad_unit`). */
  adUnit: string;
  /** The player, as the app declared them (`user_id`). */
  userId: string;
  /** What the app attached to the ad (`custom_data`). */
  customData: string;
  /** AdMob's id for this one reward (`transaction_id`). */
  transactionId: string;
}

/**
 * Takes a reward callback's query string apart.
 *
 * AdMob signs everything before `&signature=`, byte for byte as sent, and
 * always sends `signature` and `key_id` last — so the signed part is cut
 * from the raw string rather than rebuilt from parsed parameters, which
 * would not survive re-encoding.
 * @param {string} rawQuery The query string, without the leading `?`.
 * @return {RewardCallback | null} Its parts, or null if it isn't one.
 */
export function parseRewardCallback(rawQuery: string): RewardCallback | null {
  const marker = "&signature=";
  const at = rawQuery.indexOf(marker);
  if (at <= 0) return null;

  const signedContent = rawQuery.slice(0, at);
  const tail = new URLSearchParams(rawQuery.slice(at + 1));
  const signature = tail.get("signature") || "";
  const keyId = tail.get("key_id") || "";
  if (!signature || !keyId) return null;

  const params = new URLSearchParams(signedContent);
  const transactionId = params.get("transaction_id") || "";
  const userId = params.get("user_id") || "";
  if (!transactionId || !userId) return null;

  return {
    signedContent,
    signature: Buffer.from(signature, "base64url"),
    keyId,
    adUnit: params.get("ad_unit") || "",
    userId,
    customData: params.get("custom_data") || "",
    transactionId,
  };
}

/**
 * AdMob's verification keys by id, from the JSON it publishes
 * (https://www.gstatic.com/admob/reward/verifier-keys.json).
 * @param {unknown} json That document, parsed.
 * @return {Record<string, string>} Key id to PEM public key.
 */
export function parseVerifierKeys(json: unknown): Record<string, string> {
  const keys: Record<string, string> = {};
  const list = (json as {keys?: unknown})?.keys;
  if (!Array.isArray(list)) return keys;

  for (const entry of list) {
    const keyId = (entry as {keyId?: unknown})?.keyId;
    const pem = (entry as {pem?: unknown})?.pem;
    if ((typeof keyId === "number" || typeof keyId === "string") &&
        typeof pem === "string" && pem) {
      keys[String(keyId)] = pem;
    }
  }
  return keys;
}

/**
 * Whether a callback carries AdMob's signature (ECDSA over SHA-256).
 * @param {RewardCallback} callback The callback.
 * @param {Record<string, string>} keys AdMob's keys, see parseVerifierKeys.
 * @return {boolean} True only for a signature one of those keys made.
 */
export function callbackSignedByAdMob(
  callback: RewardCallback,
  keys: Record<string, string>
): boolean {
  const pem = keys[callback.keyId];
  if (!pem) return false;
  try {
    return createVerify("SHA256")
      .update(callback.signedContent)
      .verify(pem, callback.signature);
  } catch (_) {
    // A malformed key or signature is not a valid one.
    return false;
  }
}

/**
 * Whether an ad unit is one of this app's.
 *
 * The signature only proves AdMob sent the callback, not for whom: anyone
 * with an AdMob account can point their own ad unit's callback at this
 * endpoint and have AdMob sign it. With no units configured nothing is
 * paid at all.
 * @param {string} adUnit The callback's `ad_unit`.
 * @param {string} configured This app's rewarded ad units, comma-separated.
 *   Either form is accepted: the bare number AdMob sends, or the full
 *   `ca-app-pub-…/number` id as the AdMob console shows it.
 * @return {boolean} True when the ad unit is listed.
 */
export function adUnitIsOurs(adUnit: string, configured: string): boolean {
  if (!adUnit) return false;
  return configured.split(",")
    .map((entry) => entry.trim().split("/").pop() || "")
    .filter((entry) => entry)
    .includes(adUnit);
}

/** How many rewards of each kind a player has had on a given day. */
export interface AdRewardCounts {
  /** The day the counts are for (the server's date id). */
  date: string;
  lives: number;
  coins: number;
}

/**
 * A player's counts for [today], from the fields kept on their user doc.
 * Counts from another day are that day's, so today starts at zero.
 * @param {Record<string, unknown>} userData The user doc.
 * @param {string} today The server's date id.
 * @return {AdRewardCounts} Today's counts.
 */
export function adRewardCounts(
  userData: Record<string, unknown>,
  today: string
): AdRewardCounts {
  const sameDay = userData.adRewardsDate === today;
  const count = (value: unknown) => {
    const n = Math.floor(Number(value));
    return sameDay && Number.isFinite(n) && n > 0 ? n : 0;
  };
  return {
    date: today,
    lives: count(userData.adLivesToday),
    coins: count(userData.adCoinsToday),
  };
}

/**
 * Counts one more reward of [kind], or says the day's allowance is spent.
 * @param {AdRewardCounts} counts Today's counts so far.
 * @param {AdRewardKind} kind The reward being paid.
 * @return {AdRewardCounts | null} The counts after it; null when today's
 *   cap for that reward was already reached.
 */
export function countAdReward(
  counts: AdRewardCounts,
  kind: AdRewardKind
): AdRewardCounts | null {
  if (counts[kind] >= AD_REWARDS[kind].dailyCap) return null;
  return {...counts, [kind]: counts[kind] + 1};
}
