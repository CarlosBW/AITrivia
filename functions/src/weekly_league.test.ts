import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  MIN_DAILIES_FOR_LEAGUE_REWARD,
  decayedLeagueScore,
  laterWeekId,
  rewardLeagueFor,
  weeksBetween,
} from "./weekly_league";

// Mondays.
const W1 = "2026-11-09";
const W2 = "2026-11-16";
const W3 = "2026-11-23";

describe("weeksBetween", () => {
  test("counts whole weeks forward", () => {
    assert.equal(weeksBetween(W1, W1), 0);
    assert.equal(weeksBetween(W1, W2), 1);
    assert.equal(weeksBetween(W1, W3), 2);
  });

  test("crosses a year", () => {
    assert.equal(weeksBetween("2026-12-28", "2027-01-04"), 1);
  });

  test("an earlier week, or an unreadable one, is no time at all", () => {
    assert.equal(weeksBetween(W2, W1), 0);
    assert.equal(weeksBetween("", W1), 0);
    assert.equal(weeksBetween(W1, "soon"), 0);
  });
});

describe("decayedLeagueScore", () => {
  test("the same week takes nothing", () => {
    assert.equal(decayedLeagueScore(2000, W1, W1), 2000);
  });

  // Regression: the score only ever grew, so Master was permanent.
  test("each week gone by takes a quarter", () => {
    assert.equal(decayedLeagueScore(2000, W1, W2), 1500);
    assert.equal(decayedLeagueScore(2000, W1, W3), 1125);
  });

  test("rounds down, and never below zero", () => {
    assert.equal(decayedLeagueScore(5, W1, W2), 3);
    assert.equal(decayedLeagueScore(0, W1, W3), 0);
    assert.equal(decayedLeagueScore(-40, W1, W2), 0);
  });

  test("a long absence leaves next to nothing", () => {
    assert.equal(decayedLeagueScore(2000, "2026-01-05", W1) < 10, true);
  });

  // An account from before the rule has no week on record.
  test("a score with no week on record keeps everything, once", () => {
    assert.equal(decayedLeagueScore(2000, "", W2), 2000);
  });

  test("a result filed late for last week takes nothing", () => {
    assert.equal(decayedLeagueScore(2000, W2, W1), 2000);
  });

  // The numbers the rule was chosen for: a steady player settles at four
  // times a week's gain.
  test("a steady week's gain settles at four times itself", () => {
    let score = 0;
    let week = Date.parse(`${W1}T00:00:00Z`);
    let weekId = W1;
    for (let i = 0; i < 60; i++) {
      const next = new Date(week + 7 * 86400000).toISOString().slice(0, 10);
      score = decayedLeagueScore(score, weekId, next) + 600;
      week += 7 * 86400000;
      weekId = next;
    }
    assert.ok(score > 2390 && score <= 2400, String(score));
  });
});

describe("laterWeekId", () => {
  test("keeps the later week", () => {
    assert.equal(laterWeekId(W1, W2), W2);
    assert.equal(laterWeekId(W2, W1), W2);
    assert.equal(laterWeekId("", W1), W1);
  });
});

describe("rewardLeagueFor", () => {
  test("enough Daily Challenges earn the league's own reward", () => {
    assert.equal(
      rewardLeagueFor("master", MIN_DAILIES_FOR_LEAGUE_REWARD), "master"
    );
    assert.equal(rewardLeagueFor("master", 7), "master");
  });

  // Regression: one Daily Challenge a week collected Master's reward.
  test("too few are paid at Bronze", () => {
    assert.equal(rewardLeagueFor("master", 1), "bronze");
    assert.equal(
      rewardLeagueFor("gold", MIN_DAILIES_FOR_LEAGUE_REWARD - 1), "bronze"
    );
  });

  test("a week from before the count is paid in full", () => {
    assert.equal(rewardLeagueFor("master", undefined), "master");
  });
});
