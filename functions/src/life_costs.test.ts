import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  answerCharge, lastBankedAnswerWrong, resolveWrongAnswerSpend,
  tickAfterLifeGain,
} from "./life_costs";

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
    lastAnswerWrong: false,
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

  test("no answer once a miss has left the player out of lives", () => {
    const out = answerCharge({
      ...base, chargeEntry: false, lifeUnits: 0, lastAnswerWrong: true,
      correct: true,
    });
    assert.equal(out.refused, true);
  });

  // Regression: the entry costs a whole life, so a player holding exactly
  // one paid it and was left at zero — and "at zero" refused every answer
  // after the first. One life bought one question (and none at all in the
  // Weekly Topic, where the entry is paid on the draw).
  test("an entry that took the last life still buys the run", () => {
    const first = answerCharge({...base, lifeUnits: 2, correct: true});
    assert.equal(first.refused, false);
    assert.equal(first.newUnits, 0);

    const second = answerCharge({
      ...base, chargeEntry: false, lifeUnits: first.newUnits, correct: true,
    });
    assert.equal(second.refused, false);
    assert.equal(second.newUnits, 0);
  });

  test("at zero, the first miss is banked and costs nothing more", () => {
    const out = answerCharge({
      ...base, chargeEntry: false, lifeUnits: 0, correct: false,
    });
    assert.equal(out.refused, false);
    assert.equal(out.newUnits, 0);
    assert.equal(out.lifeLost, false);
  });

  test("life bought after a miss lets the run go on", () => {
    const out = answerCharge({
      ...base, chargeEntry: false, lifeUnits: 2, lastAnswerWrong: true,
      correct: true,
    });
    assert.equal(out.refused, false);
  });

  test("the new-player grace still makes a wrong answer free", () => {
    const out = answerCharge({
      ...base, chargeEntry: false, gamesPlayed: 0, correct: false,
    });
    assert.equal(out.newUnits, 10);
    assert.equal(out.lifeLost, false);
  });
});

describe("lastBankedAnswerWrong", () => {
  test("nothing banked is not a miss", () => {
    assert.equal(lastBankedAnswerWrong(undefined), false);
    assert.equal(lastBankedAnswerWrong({}), false);
  });

  test("reads the verdict of the highest question answered", () => {
    assert.equal(lastBankedAnswerWrong({
      "0": {correct: false}, "1": {correct: true},
    }), false);
    assert.equal(lastBankedAnswerWrong({
      "0": {correct: true}, "1": {correct: false},
    }), true);
  });

  // Map keys are strings: "10" sorts before "9" unless compared as numbers.
  test("orders questions by number, not by text", () => {
    assert.equal(lastBankedAnswerWrong({
      "9": {correct: false}, "10": {correct: true},
    }), false);
  });

  test("a verdict that isn't a clear yes counts as a miss", () => {
    assert.equal(lastBankedAnswerWrong({"0": {}}), true);
    assert.equal(lastBankedAnswerWrong({"0": null}), true);
  });
});

describe("tickAfterLifeGain", () => {
  const NOW = 1_700_000_000_000;

  // Regression: buying a life restarted the clock, throwing away the time
  // already waited towards the next half life.
  test("a bought life leaves the clock where it was", () => {
    assert.equal(tickAfterLifeGain({
      lastTickMs: NOW - 80_000, newUnits: 6, maxUnits: 20, nowMs: NOW,
    }), NOW - 80_000);
  });

  test("reaching the maximum resets it", () => {
    assert.equal(tickAfterLifeGain({
      lastTickMs: NOW - 80_000, newUnits: 20, maxUnits: 20, nowMs: NOW,
    }), NOW);
  });
});
