/**
 * Blocking, reporting and the username policy against the Firestore and
 * Auth emulators (see the `test:emulator` script). Runs the compiled
 * functions' handlers (`.run`) with the Admin SDK the emulators point it
 * at, so nothing here reaches a real project.
 */
// eslint-disable-next-line @typescript-eslint/no-var-requires
const {test, before, describe} = require("node:test");
// eslint-disable-next-line @typescript-eslint/no-var-requires
const assert = require("node:assert/strict");

// Loaded first: it's what initializes the Admin SDK.
const {
  blockPlayer, unblockPlayer, reportPlayer, sendFriendRequest,
  checkUsername, enforceUsernamePolicy,
// eslint-disable-next-line @typescript-eslint/no-var-requires
} = require("../lib/index.js");
// eslint-disable-next-line @typescript-eslint/no-var-requires
const admin = require("firebase-admin");

const db = admin.firestore();

const ME = "safety_me_001";
const THEM = "safety_them_01";

/**
 * Doc data, or undefined if it doesn't exist.
 * @param {string} path Document path.
 * @return {Promise<object|undefined>} Its data.
 */
async function read(path) {
  return (await db.doc(path).get()).data();
}

/**
 * Calls a callable as [uid].
 * @param {object} fn The callable.
 * @param {string} uid The caller.
 * @param {object} data Its input.
 * @return {Promise<object>} Its result.
 */
function call(fn, uid, data) {
  return fn.run({data, auth: {uid}});
}

describe("blocking a player", () => {
  before(async () => {
    const batch = db.batch();
    batch.set(db.doc(`users/${ME}`), {username: "carlos", languageCode: "es"});
    batch.set(db.doc(`users/${THEM}`), {username: "troll", languageCode: "es"});
    batch.set(db.doc(`users/${ME}/friends/${THEM}`), {uid: THEM});
    batch.set(db.doc(`users/${THEM}/friends/${ME}`), {uid: ME});
    batch.set(db.doc("realtime_invites/inv1"),
      {fromUid: THEM, toUid: ME, status: "pending"});
    await batch.commit();

    await call(blockPlayer, ME, {targetUid: THEM});
  });

  test("records it under the blocker, with the name", async () => {
    const block = await read(`users/${ME}/blocked/${THEM}`);
    assert.equal(block.uid, THEM);
    assert.equal(block.username, "troll");
  });

  test("ends the friendship on both sides", async () => {
    assert.equal(await read(`users/${ME}/friends/${THEM}`), undefined);
    assert.equal(await read(`users/${THEM}/friends/${ME}`), undefined);
  });

  test("declines a pending invite between them", async () => {
    assert.equal((await read("realtime_invites/inv1")).status, "declined");
  });

  test("refuses friend requests either way", async () => {
    await assert.rejects(
      call(sendFriendRequest, THEM, {targetUid: ME}),
      {code: "permission-denied"}
    );
    await assert.rejects(
      call(sendFriendRequest, ME, {targetUid: THEM}),
      {code: "permission-denied"}
    );
  });

  test("can be lifted", async () => {
    await call(unblockPlayer, ME, {targetUid: THEM});
    assert.equal(await read(`users/${ME}/blocked/${THEM}`), undefined);
  });
});

describe("reporting a player", () => {
  before(async () => {
    await db.doc(`users/${ME}`).set({username: "carlos", languageCode: "es"});
    await db.doc(`users/${THEM}`).set({username: "troll", languageCode: "es"});
  });

  test("files one report per reporter and player", async () => {
    await call(reportPlayer, ME,
      {targetUid: THEM, reason: "offensive_name", details: "  feo  "});
    await call(reportPlayer, ME, {targetUid: THEM, reason: "cheating"});

    const report = await read(`player_reports/${ME}__${THEM}`);
    assert.equal(report.targetUsername, "troll");
    assert.equal(report.reason, "cheating");
    assert.equal(report.reportCount, 2);
    assert.equal(report.status, "open");
    assert.ok(report.createdAt);
  });

  test("refuses an unknown reason", async () => {
    await assert.rejects(
      call(reportPlayer, ME, {targetUid: THEM, reason: "lol"}),
      {code: "invalid-argument"}
    );
  });
});

describe("username policy", () => {
  test("the picker hears why a name can't be taken", async () => {
    assert.deepEqual(
      await call(checkUsername, ME, {username: "pendejo"}),
      {allowed: false, reason: "offensive"}
    );
    assert.deepEqual(
      await call(checkUsername, ME, {username: "ana_2026"}),
      {allowed: true, reason: null}
    );
  });

  test("a refused name taken anyway goes back to the default", async () => {
    const uid = "badname_user1";
    await db.doc(`users/${uid}`).set({
      username: "pendejo", usernameLower: "pendejo", displayName: "pendejo",
    });
    await db.doc("usernames/pendejo").set({uid, username: "pendejo"});

    const snap = await db.doc("usernames/pendejo").get();
    await enforceUsernamePolicy.run({
      data: snap, params: {usernameLower: "pendejo"},
    });

    const user = await read(`users/${uid}`);
    assert.equal(user.username, "Playerbadname_");
    assert.equal(user.usernameLower, "playerbadname_");
    assert.equal(user.displayName, "Playerbadname_");
    assert.equal(await read("usernames/pendejo"), undefined);
  });
});
