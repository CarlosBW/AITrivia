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
