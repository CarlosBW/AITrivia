import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {resolveWrongAnswerSpend} from "./life_costs";

// Mirrors index.ts: WRONG_ANSWER_COST_UNITS / NEW_PLAYER_GRACE_LEVELS.
const COST = 1;
const GRACE_LEVELS = 2;
const PAST_GRACE = GRACE_LEVELS;

describe("resolveWrongAnswerSpend", () => {
  test("takes the cost from a player who has it", () => {
    const spend = resolveWrongAnswerSpend(6, COST, PAST_GRACE, GRACE_LEVELS);

    assert.equal(spend.newUnits, 5);
    assert.equal(spend.lifeLost, true);
  });

  test("a player at zero loses nothing and is told so", () => {
    const spend = resolveWrongAnswerSpend(0, COST, PAST_GRACE, GRACE_LEVELS);

    assert.equal(spend.newUnits, 0);
    assert.equal(
      spend.lifeLost, false,
      "reporting a loss here charges the player for nothing"
    );
  });

  test("the last unit is a real loss", () => {
    const spend = resolveWrongAnswerSpend(1, COST, PAST_GRACE, GRACE_LEVELS);

    assert.equal(spend.newUnits, 0);
    assert.equal(spend.lifeLost, true);
  });

  test("holding less than the cost gives up what is there", () => {
    const spend = resolveWrongAnswerSpend(1, 2, PAST_GRACE, GRACE_LEVELS);

    assert.equal(spend.newUnits, 0, "never goes negative");
    assert.equal(spend.lifeLost, true);
  });

  test("nothing is taken during the new-player grace window", () => {
    const spend = resolveWrongAnswerSpend(
      6, COST, GRACE_LEVELS - 1, GRACE_LEVELS
    );

    assert.equal(spend.newUnits, 6);
    assert.equal(spend.lifeLost, false);
  });

  test("the grace window ends on the level that reaches it", () => {
    const spend = resolveWrongAnswerSpend(
      6, COST, GRACE_LEVELS, GRACE_LEVELS
    );

    assert.equal(spend.lifeLost, true);
  });

  test("a zero balance inside the grace window still reports no loss", () => {
    const spend = resolveWrongAnswerSpend(
      0, COST, GRACE_LEVELS - 1, GRACE_LEVELS
    );

    assert.equal(spend.newUnits, 0);
    assert.equal(spend.lifeLost, false);
  });

  test("a corrupt negative balance is treated as empty", () => {
    const spend = resolveWrongAnswerSpend(-3, COST, PAST_GRACE, GRACE_LEVELS);

    assert.equal(spend.newUnits, 0);
    assert.equal(spend.lifeLost, false);
  });

  test("a free wrong answer takes nothing", () => {
    const spend = resolveWrongAnswerSpend(6, 0, PAST_GRACE, GRACE_LEVELS);

    assert.equal(spend.newUnits, 6);
    assert.equal(spend.lifeLost, false);
  });
});
