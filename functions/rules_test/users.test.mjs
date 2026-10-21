import {after, before, beforeEach, describe, test} from "node:test";
import {assertFails, assertSucceeds} from "@firebase/rules-unit-testing";
import {doc, runTransaction, setDoc, updateDoc} from "firebase/firestore";
import {newUserDoc, rulesEnv} from "./helpers.mjs";

const ALICE = "aliceUid0123456789";
const BOB = "bobUid0123456789ab";

let env;
before(async () => { env = await rulesEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

const db = (uid) => env.authenticatedContext(uid).firestore();

/** Seeds docs bypassing the rules. */
async function seed(path, data) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), path), data);
  });
}

describe("freeTopicPasses", () => {
  test("a new account starts with exactly one", async () => {
    await assertSucceeds(setDoc(doc(db(ALICE), "users", ALICE), newUserDoc(ALICE)));
    await assertFails(setDoc(doc(db(BOB), "users", BOB),
      newUserDoc(BOB, {freeTopicPasses: 50})));
  });

  test("a client cannot grant itself more", async () => {
    await seed(`users/${ALICE}`, newUserDoc(ALICE));
    await assertFails(updateDoc(doc(db(ALICE), "users", ALICE), {freeTopicPasses: 9999}));
  });
});

describe("usernames", () => {
  test("a new account keeps its default name", async () => {
    await assertSucceeds(setDoc(doc(db(ALICE), "users", ALICE), newUserDoc(ALICE)));
  });

  test("a chosen name is reserved together with the account", async () => {
    const d = db(ALICE);
    await assertSucceeds(runTransaction(d, async (tx) => {
      tx.set(doc(d, "users", ALICE), newUserDoc(ALICE, {
        username: "Alice", usernameLower: "alice", displayName: "Alice",
      }));
      tx.set(doc(d, "usernames", "alice"), {
        uid: ALICE, username: "Alice", usernameLower: "alice",
      });
    }));
  });

  // Impersonation: the user doc's name was not tied to any reservation, so
  // anyone could show up in search under someone else's name.
  test("an account cannot take a name reserved by someone else", async () => {
    await seed("usernames/alice", {uid: ALICE, username: "Alice", usernameLower: "alice"});
    await assertFails(setDoc(doc(db(BOB), "users", BOB), newUserDoc(BOB, {
      username: "Alice", usernameLower: "alice", displayName: "Alice",
    })));
  });

  test("an account cannot claim an unreserved name without reserving it", async () => {
    await assertFails(setDoc(doc(db(BOB), "users", BOB), newUserDoc(BOB, {
      username: "Carol", usernameLower: "carol", displayName: "Carol",
    })));
  });

  test("an account cannot pose as another player's default name", async () => {
    await assertFails(setDoc(doc(db(BOB), "users", BOB), newUserDoc(BOB, {
      username: `Player${ALICE.substring(0, 8)}`,
      usernameLower: `player${ALICE.substring(0, 8)}`.toLowerCase(),
      displayName: `Player${ALICE.substring(0, 8)}`,
    })));
  });

  test("displayName must be the username", async () => {
    await assertFails(setDoc(doc(db(ALICE), "users", ALICE),
      newUserDoc(ALICE, {displayName: "Official TriviaIA Support"})));
  });

  // Squatting: one account could reserve any number of names.
  test("an account cannot reserve names it does not use", async () => {
    await seed(`users/${ALICE}`, newUserDoc(ALICE));
    await assertFails(setDoc(doc(db(ALICE), "usernames", "admin"),
      {uid: ALICE, username: "admin", usernameLower: "admin"}));
  });

  test("a chosen name cannot be changed later", async () => {
    await seed(`users/${ALICE}`, newUserDoc(ALICE, {
      username: "Alice", usernameLower: "alice", displayName: "Alice",
    }));
    await seed("usernames/alice", {uid: ALICE, username: "Alice", usernameLower: "alice"});
    const d = db(ALICE);
    await assertFails(runTransaction(d, async (tx) => {
      tx.update(doc(d, "users", ALICE),
        {username: "Zed", usernameLower: "zed", displayName: "Zed"});
      tx.set(doc(d, "usernames", "zed"), {uid: ALICE, username: "Zed", usernameLower: "zed"});
    }));
  });

  test("a reservation cannot be released to someone else", async () => {
    await seed("usernames/alice", {uid: ALICE, username: "Alice", usernameLower: "alice"});
    const {deleteDoc} = await import("firebase/firestore");
    await assertFails(deleteDoc(doc(db(ALICE), "usernames", "alice")));
  });

  test("an unrelated profile update still works", async () => {
    await seed(`users/${ALICE}`, newUserDoc(ALICE, {
      username: "Alice", usernameLower: "alice", displayName: "Alice",
    }));
    await assertSucceeds(updateDoc(doc(db(ALICE), "users", ALICE), {avatarId: "avatar_2"}));
  });
});
