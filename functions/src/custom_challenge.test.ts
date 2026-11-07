import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  customChallengeBudgetUnits,
  customChallengeLevel,
} from "./custom_challenge";

describe("customChallengeBudgetUnits", () => {
  // One unit of the daily limit is one level: ten generated questions.
  test("up to ten questions cost one level", () => {
    assert.equal(customChallengeBudgetUnits(5), 1);
    assert.equal(customChallengeBudgetUnits(10), 1);
  });

  test("fifteen questions cost two levels", () => {
    assert.equal(customChallengeBudgetUnits(15), 2);
  });

  test("a nonsense count still costs one level", () => {
    assert.equal(customChallengeBudgetUnits(0), 1);
    assert.equal(customChallengeBudgetUnits(-3), 1);
  });
});

describe("customChallengeLevel", () => {
  // Generation scales difficulty by level number: 1-3 easy, 4-7 medium,
  // 8-10 hard.
  test("each challenge difficulty lands in its level band", () => {
    assert.equal(customChallengeLevel(1), 2);
    assert.equal(customChallengeLevel(2), 5);
    assert.equal(customChallengeLevel(3), 9);
  });

  test("an out-of-range difficulty falls back to medium", () => {
    assert.equal(customChallengeLevel(0), 5);
    assert.equal(customChallengeLevel(7), 5);
  });
});
