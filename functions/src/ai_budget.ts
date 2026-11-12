/**
 * Daily ceilings on how much Claude work the project will pay for, and the
 * pure decision behind them. Kept out of index.ts (like ai_question_bank.ts)
 * so the limit arithmetic can be unit-tested without firebase-admin.
 *
 * Why this exists: sign-in is anonymous and unlimited, and every new
 * account gets one free topic pass, so there is a path from "anyone with
 * the app" to real Anthropic spend that costs the player nothing. App
 * Check would gate that properly, but it can't be enforced until the real
 * store bundle ids exist. Until then these caps are the backstop — they
 * bound the worst case rather than preventing abuse, and are deliberately
 * set well above honest usage.
 */

/**
 * Metered kinds of Claude spend. Separate meters because their unit costs
 * differ by an order of magnitude: a `levels` unit generates ten full
 * questions, a `suggestions` unit is one short list of candidate titles.
 * Charging them against one counter would either let cheap calls starve
 * real generation or let expensive calls hide behind a generous cap.
 */
export type AiMeter = "levels" | "suggestions";

export interface AiMeterCaps {
  /** Ceiling for the whole project, per UTC day. */
  global: number;
  /** Ceiling for a single account, per UTC day. */
  perUser: number;
}

/**
 * One `levels` unit is one level of ten generated questions — the real
 * cost driver, and the reason this meter isn't "topics created". A topic
 * only generates two levels up front; the other eight arrive as the
 * player advances, and regeneration adds more on top. Metering topics
 * would leave those paths uncapped.
 *
 * 5000 levels/day is 500 full ten-level topics, roughly $25/day at Haiku
 * 4.5 pricing. Suggestions are capped separately at a level that keeps
 * their worst case a fraction of that.
 */
export const AI_METER_CAPS: Record<AiMeter, AiMeterCaps> = {
  // 75 levels a day per account: 50 stopped a player partway through a
  // topic on a long session of new AI levels, and nothing about that is
  // abuse. Still seven full ten-level topics' worth.
  levels: {global: 5000, perUser: 75},
  suggestions: {global: 2000, perUser: 30},
};

export type AiBudgetVerdict =
  | {allowed: true}
  | {allowed: false; limit: "global" | "user"};

/**
 * Decides whether [units] more of a meter may be spent today.
 *
 * The global limit is reported first when both are exhausted: it's the one
 * that isn't the player's fault, and it changes what they should be told
 * ("try tomorrow" vs. "you've hit your own limit").
 * @param {object} params Current usage, the request size, and the caps.
 * @param {number} params.globalUsed Units already spent project-wide today.
 * @param {number} params.userUsed Units already spent by this account today.
 * @param {number} params.units Units this request wants to spend.
 * @param {AiMeterCaps} params.caps Ceilings to apply.
 * @return {AiBudgetVerdict} Whether to allow, and which limit blocked it.
 */
export function checkAiBudget(params: {
  globalUsed: number;
  userUsed: number;
  units: number;
  caps: AiMeterCaps;
}): AiBudgetVerdict {
  const {globalUsed, userUsed, units, caps} = params;

  // A zero/negative request is never blocked — callers that turn out to
  // have nothing to generate shouldn't be told they're out of budget.
  if (units <= 0) return {allowed: true};

  if (globalUsed + units > caps.global) {
    return {allowed: false, limit: "global"};
  }
  if (userUsed + units > caps.perUser) {
    return {allowed: false, limit: "user"};
  }
  return {allowed: true};
}

/**
 * How long one account's topic creation holds its lock: a little over the
 * function's own time limit, so a call that died releases it by itself.
 */
export const AI_TOPIC_CREATION_LOCK_MS = 6 * 60 * 1000;

/**
 * Whether this account is already creating a topic.
 *
 * Creation generates first and charges after, so several calls sent at
 * once each generated their levels and only one of them could pay: the
 * rest were model calls nobody was charged for. One creation at a time.
 * @param {number} lockedUntilMs When the lock in place expires; 0 if none.
 * @param {number} nowMs Now.
 * @return {boolean} True if a new creation has to wait.
 */
export function creationLockHeld(
  lockedUntilMs: number,
  nowMs: number
): boolean {
  return Number.isFinite(lockedUntilMs) && lockedUntilMs > nowMs;
}
