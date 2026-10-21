import {after, before, beforeEach, describe, test} from "node:test";
import {assertFails, assertSucceeds} from "@firebase/rules-unit-testing";
import {doc, setDoc, updateDoc} from "firebase/firestore";
import {newUserDoc, rulesEnv} from "./helpers.mjs";

const ALICE = "aliceUid0123456789";
const ROW = `weekly_leagues/2026-10-19/silver/${ALICE}`;

let env;
before(async () => { env = await rulesEnv(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), "users", ALICE), newUserDoc(ALICE, {
      avatarId: "avatar_2", equippedFrame: "silver",
    }));
    await setDoc(doc(ctx.firestore(), ROW), {
      uid: ALICE, avatarId: "avatar_1", equippedFrame: "bronze", weeklyScore: 10,
    });
  });
});

const db = () => env.authenticatedContext(ALICE).firestore();

describe("weekly league row cosmetics", () => {
  test("can be brought in line with the profile", async () => {
    await assertSucceeds(updateDoc(doc(db(), ROW),
      {avatarId: "avatar_2", equippedFrame: "silver"}));
  });

  // Anything was accepted: a master frame or a locked avatar could be
  // shown on the board without owning it.
  test("cannot show a frame or avatar the profile doesn't wear", async () => {
    await assertFails(updateDoc(doc(db(), ROW), {equippedFrame: "master"}));
    await assertFails(updateDoc(doc(db(), ROW), {avatarId: "avatar_pvp_master"}));
  });

  test("cannot touch the score", async () => {
    await assertFails(updateDoc(doc(db(), ROW), {weeklyScore: 9999}));
  });
});
