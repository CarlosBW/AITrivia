/**
 * deleteMyAccount against the Firestore and Auth emulators (see the
 * `test:emulator` script): seeds a player and the data they share with an
 * opponent, deletes the player, and checks what's left.
 *
 * Runs the compiled callable's handler (`.run`) with the Admin SDK the
 * emulators point it at, so nothing here reaches a real project. The
 * emulator doesn't enforce indexes, so this can't catch a missing
 * fieldOverride.
 */
// eslint-disable-next-line @typescript-eslint/no-var-requires
const {test, before, describe} = require("node:test");
// eslint-disable-next-line @typescript-eslint/no-var-requires
const assert = require("node:assert/strict");

// Loaded first: it's what initializes the Admin SDK.
// eslint-disable-next-line @typescript-eslint/no-var-requires
const {deleteMyAccount} = require("../lib/index.js");
// eslint-disable-next-line @typescript-eslint/no-var-requires
const admin = require("firebase-admin");

const db = admin.firestore();

const GONE = "gone_player_01";
const OPP = "opponent_0001";
const THIRD = "third_player1";
const DAY = "2026-10-19"; // A Monday, so also the week id.

/**
 * Doc data, or undefined if it doesn't exist.
 * @param {string} path Document path.
 * @return {Promise<object|undefined>} Its data.
 */
async function read(path) {
  return (await db.doc(path).get()).data();
}

/** Seeds both players and everything they share. */
async function seed() {
  const finishedLive = {
    hostUid: GONE, guestUid: OPP, status: "finished", rewarded: true,
    winnerUid: OPP,
    players: {
      [GONE]: {displayName: "carlos", avatarId: "avatar_7",
        equippedFrame: "gold", bestLeagueId: "gold", score: 3,
        finished: true},
      [OPP]: {displayName: "ana", avatarId: "avatar_2", score: 5,
        finished: true},
    },
  };
  const writes = {
    [`users/${GONE}`]: {username: "carlos", usernameLower: "carlos",
      languageCode: "es"},
    [`users/${OPP}`]: {username: "ana", languageCode: "en"},
    [`users/${THIRD}`]: {username: "beto", languageCode: "es"},
    "usernames/carlos": {uid: GONE},

    // A friendship both sides know about, and a one-sided entry the
    // deleted player's own list doesn't have.
    [`users/${GONE}/friends/${OPP}`]: {uid: OPP, displayName: "ana"},
    [`users/${OPP}/friends/${GONE}`]: {uid: GONE, displayName: "carlos"},
    [`users/${THIRD}/friends/${GONE}`]: {uid: GONE, displayName: "carlos"},

    "matches/live_done": finishedLive,
    "matches/live_open": {
      ...finishedLive, status: "playing", rewarded: false, winnerUid: null,
    },
    // The match the accepted invite started.
    "matches/live_invited": {
      ...finishedLive, hostUid: THIRD, guestUid: GONE, winnerUid: THIRD,
      players: {
        [THIRD]: {displayName: "beto", avatarId: "avatar_3", score: 4,
          finished: true},
        [GONE]: {displayName: "carlos", avatarId: "avatar_7", score: 1,
          finished: true},
      },
    },
    "async_matches/async_done": {
      challengerUid: GONE, challengedUid: OPP,
      challengerDisplayName: "carlos", challengedDisplayName: "ana",
      challengerStatus: "finished", challengedStatus: "finished",
      status: "finished", rewarded: true, winnerUid: OPP,
      challenger: {score: 2}, challenged: {score: 4},
    },
    "async_matches/async_open": {
      challengerUid: GONE, challengedUid: OPP,
      challengerDisplayName: "carlos", challengedDisplayName: "ana",
      challengerStatus: "finished", challengedStatus: "pending",
      status: "waiting_challenged", rewarded: false,
    },
    // Not theirs: must come through untouched.
    "async_matches/others": {
      challengerUid: OPP, challengedUid: THIRD,
      challengerDisplayName: "ana", challengedDisplayName: "beto",
      status: "waiting_challenged", rewarded: false,
    },

    [`users/${OPP}/match_history/live_done`]: {matchId: "live_done",
      opponentUid: GONE, opponentName: "carlos", result: "victory",
      myScore: 5, opponentScore: 3},
    [`users/${OPP}/match_history/async_done`]: {matchId: "async_done",
      opponentUid: GONE, opponentName: "carlos", result: "victory",
      myScore: 4, opponentScore: 2},

    "realtime_invites/inv_sent": {fromUid: GONE, fromName: "carlos",
      toUid: OPP, toName: "ana", status: "pending"},
    "realtime_invites/inv_got": {fromUid: THIRD, fromName: "beto",
      toUid: GONE, toName: "carlos", status: "accepted"},

    [`users/${OPP}/notifications/realtime_invite__${GONE}__inv_sent`]: {
      type: "realtime_invite", body: "carlos invited you",
      data: {inviteId: "inv_sent", fromUid: GONE}},
    // notifyOnce keys "accepted your invite" by the match it started.
    [`users/${THIRD}/notifications/` +
      `realtime_invite_accepted__${GONE}__live_invited`]: {
      type: "realtime_invite_accepted", body: "carlos accepted",
      data: {inviteId: "inv_got", matchId: "live_invited", fromUid: GONE}},
    [`users/${OPP}/notifications/friend_request__${GONE}__`]: {
      type: "friend_request", body: "carlos wants to add you", data: {}},
    [`users/${OPP}/notifications/result_auto_id`]: {
      type: "match_result", body: "You won against carlos",
      data: {matchId: "async_done"}},
    [`users/${OPP}/notifications/turn_auto_id`]: {
      type: "match_turn", body: "carlos finished, your turn",
      data: {matchId: "async_open"}},
    [`users/${OPP}/notifications/streak_auto_id`]: {
      type: "streak_at_risk", body: "Your streak is at risk", data: {}},

    [`users/${GONE}/daily_challenges/${DAY}`]: {dateId: DAY, played: true},
    [`daily_leaderboards/${DAY}/players/${GONE}`]: {uid: GONE,
      username: "carlos", score: 80},
    [`daily_leaderboards/${DAY}/players/${OPP}`]: {uid: OPP,
      username: "ana", score: 90},
    [`weekly_leagues/${DAY}/silver/${GONE}`]: {uid: GONE,
      username: "carlos", weeklyScore: 80},
    [`weekly_leagues/${DAY}/silver/${OPP}`]: {uid: OPP,
      username: "ana", weeklyScore: 90},

    [`ai_question_reports/${GONE}__pool1__1__q1`]: {uid: GONE,
      reason: "wrong_answer"},
    [`question_reports/${GONE}__fixed_q1`]: {uid: GONE, reason: "typo"},
    [`question_report_quotas/${GONE}`]: {count: 1},
  };

  const batch = db.batch();
  for (const [path, data] of Object.entries(writes)) {
    batch.set(db.doc(path), data);
  }
  await batch.commit();
  await admin.auth().createUser({uid: GONE});
}

describe("deleteMyAccount", () => {
  before(async () => {
    await seed();
    await deleteMyAccount.run({data: {}, auth: {uid: GONE}});
  });

  test("removes the account itself", async () => {
    assert.equal(await read(`users/${GONE}`), undefined);
    assert.equal(
      await read(`users/${GONE}/daily_challenges/${DAY}`), undefined
    );
    assert.equal(await read("usernames/carlos"), undefined);
    await assert.rejects(
      admin.auth().getUser(GONE), {code: "auth/user-not-found"}
    );
  });

  test("keeps a settled live match, under a neutral name", async () => {
    const match = await read("matches/live_done");
    assert.equal(match.status, "finished");
    assert.equal(match.winnerUid, OPP);
    // The opponent reads English.
    assert.equal(match.players[GONE].displayName, "Deleted player");
    assert.equal(match.players[GONE].avatarId, "avatar_1");
    assert.equal(match.players[GONE].equippedFrame, "");
    assert.equal(match.players[GONE].score, 3);
    assert.equal(match.players[OPP].displayName, "ana");
  });

  test("cancels a live match still in play", async () => {
    const match = await read("matches/live_open");
    assert.equal(match.status, "cancelled");
    assert.equal(match.rewarded, true);
    assert.equal(match.players[GONE].displayName, "Deleted player");
  });

  test("keeps a settled async match, under a neutral name", async () => {
    const match = await read("async_matches/async_done");
    assert.equal(match.status, "finished");
    assert.equal(match.challengerDisplayName, "Deleted player");
    assert.equal(match.challengedDisplayName, "ana");
    assert.equal(match.challenger.score, 2);
  });

  test("declines an async match still in play", async () => {
    const match = await read("async_matches/async_open");
    assert.equal(match.status, "declined");
    assert.equal(match.declinedByUid, GONE);
    assert.equal(match.rewarded, true);
    assert.ok(match.declinedAt);
  });

  test("leaves other players' matches alone", async () => {
    const match = await read("async_matches/others");
    assert.equal(match.status, "waiting_challenged");
    assert.equal(match.challengerDisplayName, "ana");
  });

  test("renames them in the opponent's history, keeping the result",
    async () => {
      for (const id of ["live_done", "async_done"]) {
        const entry = await read(`users/${OPP}/match_history/${id}`);
        assert.equal(entry.opponentName, "Deleted player", id);
        assert.equal(entry.result, "victory", id);
      }
    });

  test("drops them from every friend list", async () => {
    assert.equal(await read(`users/${OPP}/friends/${GONE}`), undefined);
    assert.equal(await read(`users/${THIRD}/friends/${GONE}`), undefined);
  });

  test("deletes their invites", async () => {
    assert.equal(await read("realtime_invites/inv_sent"), undefined);
    assert.equal(await read("realtime_invites/inv_got"), undefined);
  });

  test("deletes the notifications that name them, and only those",
    async () => {
      const left = await db.collection(`users/${OPP}/notifications`).get();
      assert.deepEqual(left.docs.map((d) => d.id), ["streak_auto_id"]);
      assert.equal(
        (await db.collection(`users/${THIRD}/notifications`).get()).size, 0
      );
    });

  test("deletes their leaderboard rows and keeps the others'", async () => {
    assert.equal(
      await read(`daily_leaderboards/${DAY}/players/${GONE}`), undefined
    );
    assert.equal(
      await read(`weekly_leagues/${DAY}/silver/${GONE}`), undefined
    );
    assert.ok(await read(`daily_leaderboards/${DAY}/players/${OPP}`));
    assert.ok(await read(`weekly_leagues/${DAY}/silver/${OPP}`));
  });

  test("deletes their question reports", async () => {
    assert.equal(
      await read(`ai_question_reports/${GONE}__pool1__1__q1`), undefined
    );
    assert.equal(
      await read(`question_reports/${GONE}__fixed_q1`), undefined
    );
    assert.equal(await read(`question_report_quotas/${GONE}`), undefined);
  });
});
