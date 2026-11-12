/**
 * The level ceiling an `expandAiTopic` call moves a topic to.
 *
 * Kept out of index.ts so it can be tested without firebase-admin.
 */

/**
 * Decides an expansion against the topic as it is now.
 *
 * `seenTarget` is the ceiling the player saw when they tapped. Two
 * requests for one tap — a double tap opened two confirmations — both saw
 * the same ceiling, so once the first lands the second no longer matches
 * and is refused instead of charging again. Older apps don't send it.
 * @param {object} params The topic's ceiling now, the batch size and what
 *     the player saw.
 * @param {number} params.currentTarget The topic's level ceiling now.
 * @param {number} params.perExpansion Levels one expansion adds.
 * @param {number} [params.seenTarget] The ceiling the player saw.
 * @return {{ok: true, newTarget: number} | {ok: false}} The new ceiling, or
 *     a refusal when the request is stale.
 */
export function expansionTarget(params: {
  currentTarget: number;
  perExpansion: number;
  seenTarget?: number;
}): {ok: true; newTarget: number} | {ok: false} {
  const {currentTarget, perExpansion, seenTarget} = params;
  if (seenTarget !== undefined && seenTarget !== currentTarget) {
    return {ok: false};
  }
  return {ok: true, newTarget: currentTarget + perExpansion};
}

/**
 * The level a look-ahead generation may be asked from.
 *
 * The app reports the level being played and the server generates a few
 * past it. The number was taken as sent, so a modified client reporting a
 * high one had every remaining level generated at once — real model calls
 * for levels the player was nowhere near. It can't be past the level after
 * the last one actually passed, which is the deepest one they can open.
 * @param {number} reportedLevel The level the app says is being played.
 * @param {number[]} passedLevels Levels this player has passed.
 * @return {number} The level to generate ahead of.
 */
export function trustedBufferLevel(
  reportedLevel: number,
  passedLevels: number[]
): number {
  const deepestPlayable = Math.max(0, ...passedLevels) + 1;
  return Math.max(0, Math.min(Math.floor(reportedLevel), deepestPlayable));
}

/**
 * Coins to give back from an "add more questions" purchase.
 *
 * The price is per level, paid up front. A level counts as delivered only
 * if it actually gained questions: one whose whole batch was discarded as
 * repeats used to be charged like any other, for nothing.
 * @param {number} cost What was charged.
 * @param {number} costPerLevel The price of one level.
 * @param {number} levelsDelivered Levels that gained at least a question.
 * @return {number} The refund, never negative.
 */
export function undeliveredRefund(
  cost: number,
  costPerLevel: number,
  levelsDelivered: number
): number {
  return Math.max(0, cost - Math.max(0, levelsDelivered) * costPerLevel);
}
