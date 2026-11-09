import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  answeredNotification,
  crossUserNotificationId,
  staleTurnNotifications,
} from "./notification_ids";

describe("crossUserNotificationId", () => {
  test("one per sender, type and match", () => {
    assert.equal(
      crossUserNotificationId("match_turn", "alice", "m1"),
      "match_turn__alice__m1"
    );
  });

  test("a friend request has no match, so one per sender", () => {
    assert.equal(
      crossUserNotificationId("friend_request", "alice"),
      "friend_request__alice__"
    );
  });
});

describe("staleTurnNotifications", () => {
  test("each player's 'your turn' came from the other one", () => {
    assert.deepEqual(staleTurnNotifications("alice", "bob", "m1"), [
      {recipientUid: "alice", id: "match_turn__bob__m1"},
      {recipientUid: "bob", id: "match_turn__alice__m1"},
    ]);
  });
});

describe("answeredNotification", () => {
  test("a request answered from the list or the Friends screen", () => {
    assert.equal(answeredNotification({data: {resolution: "rejected"}}), true);
    assert.equal(answeredNotification({data: {resolution: "accepted"}}), true);
  });

  test("one still waiting, or none at all", () => {
    assert.equal(answeredNotification({data: {fromUid: "a"}}), false);
    assert.equal(answeredNotification({}), false);
    assert.equal(answeredNotification(undefined), false);
  });
});
