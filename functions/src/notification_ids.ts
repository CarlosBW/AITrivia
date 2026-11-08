/**
 * Ids of the notifications one player sends another (`notifyOnce` and
 * `sendUserNotification` in index.ts).
 *
 * The id is fixed by sender, type and match so the same event can't be
 * announced twice — and so the server can find a notification again once
 * it has gone stale: a friend request answered from the Friends screen, or
 * a "your turn" whose match is already over.
 */

/**
 * @param {string} type Notification type, e.g. "match_turn".
 * @param {string} senderUid Who sent it.
 * @param {string} refId The match or invite it is about, if any.
 * @return {string} The notification's document id.
 */
export function crossUserNotificationId(
  type: string, senderUid: string, refId = ""
): string {
  return [type, senderUid, refId].join("__");
}

/**
 * The "your turn" notifications a finished async match leaves behind: each
 * player may have one, sent by the other when they finished first.
 * @param {string} challengerUid One player.
 * @param {string} challengedUid The other.
 * @param {string} matchId The match.
 * @return {Array<{recipientUid: string, id: string}>} Where each one is.
 */
export function staleTurnNotifications(
  challengerUid: string, challengedUid: string, matchId: string
): {recipientUid: string; id: string}[] {
  return [
    {
      recipientUid: challengerUid,
      id: crossUserNotificationId("match_turn", challengedUid, matchId),
    },
    {
      recipientUid: challengedUid,
      id: crossUserNotificationId("match_turn", challengerUid, matchId),
    },
  ];
}
