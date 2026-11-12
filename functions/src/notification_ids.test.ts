import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  answeredNotification,
  crossUserNotificationId,
  realtimeInviteNotification,
  staleAsyncMatchNotifications,
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

describe("staleAsyncMatchNotifications", () => {
  test("covers both turns and the invitation", () => {
    assert.deepEqual(staleAsyncMatchNotifications("alice", "bob", "m1"), [
      {recipientUid: "alice", id: "match_turn__bob__m1"},
      {recipientUid: "bob", id: "match_turn__alice__m1"},
      {recipientUid: "bob", id: "match_invite__alice__m1"},
    ]);
  });

  // The id it is cleared by has to be the id it is written under.
  test("the invitation is found under the id it was sent with", () => {
    const invite = staleAsyncMatchNotifications("alice", "bob", "m1")[2];
    assert.equal(
      invite.id, crossUserNotificationId("match_invite", "alice", "m1")
    );
  });
});

describe("realtimeInviteNotification", () => {
  test("is in the invited player's inbox, under the sender", () => {
    assert.deepEqual(realtimeInviteNotification("alice", "bob", "i1"), {
      recipientUid: "bob",
      id: crossUserNotificationId("realtime_invite", "alice", "i1"),
    });
  });
});
