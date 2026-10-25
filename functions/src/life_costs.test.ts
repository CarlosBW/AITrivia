import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {answerCharge, resolveWrongAnswerSpend} from "./life_costs";

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

describe("answerCharge", () => {
  const base = {
    chargeEntry: true,
    lifeUnits: 10,
    entryCost: 2,
    wrongCost: 1,
    gamesPlayed: PAST_GRACE,
    graceLevels: GRACE_LEVELS,
  };

  test("the first answer of a run pays the entry", () => {
    const out = answerCharge({...base, correct: true});
    assert.deepEqual(out, {
      refused: false, newUnits: 8, entryCharged: true, lifeLost: false,
    });
  });

  test("a wrong first answer pays the entry and the half life", () => {
    const out = answerCharge({...base, correct: false});
    assert.equal(out.newUnits, 7);
    assert.equal(out.entryCharged, true);
    assert.equal(out.lifeLost, true);
  });

  test("a free replay pays no entry", () => {
    const out = answerCharge({...base, chargeEntry: false, correct: true});
    assert.equal(out.newUnits, 10);
    assert.equal(out.entryCharged, false);
  });

  // Answering is where lives are enforced now: a client that skipped the
  // old separate charge calls played for free.
  test("no answer without enough life for the entry", () => {
    const out = answerCharge({...base, lifeUnits: 1, correct: true});
    assert.equal(out.refused, true);
    assert.equal(out.newUnits, 1);
  });

  test("no answer at all once out of lives", () => {
    const out = answerCharge({
      ...base, chargeEntry: false, lifeUnits: 0, correct: true,
    });
    assert.equal(out.refused, true);
  });

  test("the new-player grace still makes a wrong answer free", () => {
    const out = answerCharge({
      ...base, chargeEntry: false, gamesPlayed: 0, correct: false,
    });
    assert.equal(out.newUnits, 10);
    assert.equal(out.lifeLost, false);
  });
});
