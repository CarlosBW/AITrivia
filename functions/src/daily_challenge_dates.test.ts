import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  MAX_CLIENT_DATE_SKEW_DAYS,
  isPlausibleDateId,
  parseDateId,
  weekIdForDateId,
} from "./daily_challenge_dates";

describe("parseDateId", () => {
  test("parses a real date to its UTC midnight", () => {
    assert.equal(
      parseDateId("2026-07-30"),
      Date.parse("2026-07-30T00:00:00Z")
    );
  });

  test("rejects anything that isn't YYYY-MM-DD", () => {
    for (const bad of ["", "2026-7-30", "30-07-2026", "not-a-date", "2026"]) {
      assert.ok(Number.isNaN(parseDateId(bad)), `expected NaN for "${bad}"`);
    }
  });

  test("rejects well-shaped dates that don't exist", () => {
    // The shape regex alone would let these through.
    assert.ok(Number.isNaN(parseDateId("2026-02-30")));
    assert.ok(Number.isNaN(parseDateId("2026-13-01")));
    assert.ok(Number.isNaN(parseDateId("2025-02-29")));
  });

  test("accepts a real leap day", () => {
    assert.ok(!Number.isNaN(parseDateId("2028-02-29")));
  });
});

describe("isPlausibleDateId", () => {
  const serverToday = "2026-07-30";

  test("accepts the server's own date", () => {
    assert.equal(isPlausibleDateId("2026-07-30", serverToday), true);
  });

  test("accepts one day either side, covering every UTC offset", () => {
    // A device in UTC+14 is already on the 31st while the server (UTC) is
    // on the 30th; one in UTC-12 is still on the 29th.
    assert.equal(isPlausibleDateId("2026-07-31", serverToday), true);
    assert.equal(isPlausibleDateId("2026-07-29", serverToday), true);
  });

  test("rejects dates beyond the skew window", () => {
    assert.equal(isPlausibleDateId("2026-08-01", serverToday), false);
    assert.equal(isPlausibleDateId("2026-07-28", serverToday), false);
  });

  test("rejects the far past and far future", () => {
    assert.equal(isPlausibleDateId("2020-01-01", serverToday), false);
    assert.equal(isPlausibleDateId("2099-12-31", serverToday), false);
  });

  test("rejects malformed ids outright", () => {
    assert.equal(isPlausibleDateId("2026-02-30", serverToday), false);
    assert.equal(isPlausibleDateId("", serverToday), false);
  });

  test("holds across a month boundary", () => {
    assert.equal(isPlausibleDateId("2026-08-01", "2026-07-31"), true);
    assert.equal(isPlausibleDateId("2026-07-31", "2026-08-01"), true);
    assert.equal(isPlausibleDateId("2026-07-30", "2026-08-01"), false);
  });

  test("holds across a year boundary", () => {
    assert.equal(isPlausibleDateId("2027-01-01", "2026-12-31"), true);
    assert.equal(isPlausibleDateId("2026-12-31", "2027-01-01"), true);
  });

  // The regression this guard exists for: walking `dailyStreak` upward
  // with consecutive forged dates, one submission per day, without ever
  // opening a session. Only the days inside the window are reachable.
  test("blocks a forged consecutive-date streak walk", () => {
    const walk = [
      "2026-07-31", "2026-08-01", "2026-08-02", "2026-08-03", "2026-08-04",
    ];
    const accepted = walk.filter((d) => isPlausibleDateId(d, serverToday));
    assert.deepEqual(accepted, ["2026-07-31"]);
  });

  test("the window is exactly MAX_CLIENT_DATE_SKEW_DAYS wide", () => {
    assert.equal(MAX_CLIENT_DATE_SKEW_DAYS, 1);
  });
});

describe("weekIdForDateId", () => {
  test("maps every day of a week to that week's Monday", () => {
    // 2026-07-27 is a Monday.
    const monday = "2026-07-27";
    for (const day of [
      "2026-07-27", "2026-07-28", "2026-07-29", "2026-07-30",
      "2026-07-31", "2026-08-01", "2026-08-02",
    ]) {
      assert.equal(weekIdForDateId(day), monday, `for ${day}`);
    }
  });

  test("rolls to the next Monday on the following day", () => {
    assert.equal(weekIdForDateId("2026-08-03"), "2026-08-03");
  });

  test("treats Sunday as the end of its week, not the start", () => {
    // 2026-08-02 is a Sunday — ISO weeks end there.
    assert.equal(weekIdForDateId("2026-08-02"), "2026-07-27");
  });

  test("is stable across a month boundary", () => {
    assert.equal(weekIdForDateId("2026-08-01"), "2026-07-27");
  });
});
