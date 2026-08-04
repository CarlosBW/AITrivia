import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  AI_METER_CAPS,
  AiMeterCaps,
  checkAiBudget,
} from "./ai_budget";

const caps: AiMeterCaps = {global: 100, perUser: 10};

/**
 * Shorthand for one budget decision against the fixture caps above.
 * @param {number} globalUsed Units already spent project-wide.
 * @param {number} userUsed Units already spent by this account.
 * @param {number} units Units being requested.
 * @return {object} The verdict.
 */
function check(globalUsed: number, userUsed: number, units = 1) {
  return checkAiBudget({globalUsed, userUsed, units, caps});
}

describe("checkAiBudget", () => {
  test("allows a request that fits under both ceilings", () => {
    assert.deepEqual(check(0, 0), {allowed: true});
    assert.deepEqual(check(50, 5), {allowed: true});
  });

  test("allows a request that lands exactly on a ceiling", () => {
    // The cap is what you may spend, not what you must stay below.
    assert.deepEqual(check(99, 9), {allowed: true});
    assert.deepEqual(check(90, 0, 10), {allowed: true});
  });

  test("blocks the unit that would cross the per-user ceiling", () => {
    assert.deepEqual(check(0, 10), {allowed: false, limit: "user"});
  });

  test("blocks the unit that would cross the global ceiling", () => {
    assert.deepEqual(check(100, 0), {allowed: false, limit: "global"});
  });

  test("blocks a multi-unit request that would overshoot", () => {
    // The whole request is refused rather than partially granted —
    // a half-generated topic is worse than a refused one.
    assert.deepEqual(check(0, 8, 3), {allowed: false, limit: "user"});
    assert.deepEqual(check(98, 0, 3), {allowed: false, limit: "global"});
  });

  test("reports the global limit when both are exhausted", () => {
    // Decides what the player is told: an outage they didn't cause, not
    // an accusation that they overused the feature.
    assert.deepEqual(check(100, 10), {allowed: false, limit: "global"});
  });

  test("never blocks a zero-unit request", () => {
    // Callers that turn out to have nothing to generate (a level already
    // at the bank cap) must not be told they're out of budget.
    assert.deepEqual(check(100, 10, 0), {allowed: true});
    assert.deepEqual(check(100, 10, -1), {allowed: true});
  });

  test("stays blocked if a counter somehow overshot its cap", () => {
    assert.deepEqual(check(250, 0), {allowed: false, limit: "global"});
    assert.deepEqual(check(0, 25), {allowed: false, limit: "user"});
  });
});

describe("AI_METER_CAPS", () => {
  test("gives every account a per-user cap well below the global one", () => {
    // The per-user cap exists so one scripted account can't drain the
    // day's budget and take everyone else down with it; that only works
    // if it's a small fraction of the whole.
    for (const [meter, meterCaps] of Object.entries(AI_METER_CAPS)) {
      assert.ok(
        meterCaps.perUser * 10 <= meterCaps.global,
        `${meter}: one account can take more than a tenth of the budget`
      );
    }
  });

  test("keeps both meters positive", () => {
    for (const [meter, meterCaps] of Object.entries(AI_METER_CAPS)) {
      assert.ok(meterCaps.global > 0, `${meter} global cap must be positive`);
      assert.ok(meterCaps.perUser > 0, `${meter} per-user cap must be > 0`);
    }
  });

  test("budgets a full topic's worth of levels per account", () => {
    // A topic is ten levels; a player who can't finish one they paid for
    // would be a worse bug than the abuse this guards against.
    assert.ok(AI_METER_CAPS.levels.perUser >= 10);
  });
});
