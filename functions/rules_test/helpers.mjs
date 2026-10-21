// Shared setup for the firestore.rules tests. They run against the local
// Firestore emulator (`npm run test:rules`), never against the real project.
import {readFileSync} from "node:fs";
import {initializeTestEnvironment} from "@firebase/rules-unit-testing";

export async function rulesEnv() {
  return initializeTestEnvironment({
    projectId: "demo-triviaia",
    firestore: {
      rules: readFileSync(new URL("../../firestore.rules", import.meta.url), "utf8"),
    },
  });
}

/** The fields bootstrapUserDoc writes for a brand-new account. */
export function newUserDoc(uid, overrides = {}) {
  const username = `Player${uid.substring(0, 8)}`;
  return {
    coins: 0,
    xp: 0,
    freeTopicPasses: 1,
    username,
    usernameLower: username.toLowerCase(),
    displayName: username,
    avatarId: "avatar_1",
    unlockedAvatars: [
      "avatar_1", "avatar_2", "avatar_3", "avatar_4",
      "avatar_5", "avatar_6", "avatar_7", "avatar_8",
    ],
    ...overrides,
  };
}
