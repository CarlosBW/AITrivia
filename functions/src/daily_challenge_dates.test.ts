import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  MAX_CLIENT_DATE_SKEW_DAYS,
  dateIdInTimeZone,
  isPlausibleDateId,
  isWeekClaimable,
  dailySubmissionCheck,
  isStreakAtRisk,
  loginStreakStep,
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

describe("loginStreakStep", () => {
  const server = "2026-10-21";

  test("advances the streak on the day after the last login", () => {
    assert.deepEqual(
      loginStreakStep("2026-10-20", 4, "2026-10-21", server),
      {status: "advance", streak: 5}
    );
  });

  test("restarts at 1 after a missed day or on a first login", () => {
    assert.deepEqual(
      loginStreakStep("2026-10-18", 4, "2026-10-21", server),
      {status: "advance", streak: 1}
    );
    assert.deepEqual(
      loginStreakStep(null, 0, "2026-10-21", server),
      {status: "advance", streak: 1}
    );
  });

  test("does nothing twice on the same day", () => {
    assert.deepEqual(
      loginStreakStep("2026-10-21", 4, "2026-10-21", server),
      {status: "already"}
    );
  });

  // The hole: the date came from the client and was only shape-checked, so
  // a script could claim tomorrow, the day after, and so on, collecting a
  // streak bonus per call.
  test("refuses a date far from the server's own", () => {
    for (const forged of ["2026-10-23", "2027-01-01", "2026-10-19"]) {
      assert.deepEqual(
        loginStreakStep("2026-10-20", 4, forged, server),
        {status: "invalid"},
        forged
      );
    }
  });

  test("never moves backwards", () => {
    // A device a day ahead claimed tomorrow already; today is not new.
    assert.deepEqual(
      loginStreakStep("2026-10-22", 5, "2026-10-21", server),
      {status: "already"}
    );
  });

  test("refuses malformed dates", () => {
    assert.deepEqual(
      loginStreakStep(null, 0, "2026-02-30", server),
      {status: "invalid"}
    );
  });
});

describe("dateIdInTimeZone", () => {
  // 19:00 in Lima is already midnight in UTC: the reminder job runs then,
  // and reading the date in UTC put it a day ahead of the players it was for.
  test("reads the calendar date in the given zone, not UTC", () => {
    const limaSevenPm = Date.parse("2026-10-22T00:00:00Z");
    assert.equal(dateIdInTimeZone(limaSevenPm, "America/Lima"), "2026-10-21");
    assert.equal(dateIdInTimeZone(limaSevenPm, "UTC"), "2026-10-22");
  });
});

describe("isStreakAtRisk", () => {
  const today = "2026-10-21";

  test("only when the last play was yesterday", () => {
    assert.equal(isStreakAtRisk("2026-10-20", today), true);
  });

  test("not when the player already played today", () => {
    assert.equal(isStreakAtRisk("2026-10-21", today), false);
  });

  // Two days back the streak is already gone: there is nothing to save.
  test("not when the streak is already lost", () => {
    assert.equal(isStreakAtRisk("2026-10-18", today), false);
    assert.equal(isStreakAtRisk(undefined, today), false);
  });
});

describe("isWeekClaimable", () => {
  // Week of Monday 2026-10-19, which runs to Sunday 2026-10-25.
  const week = "2026-10-19";

  test("not while the week is still running", () => {
    assert.equal(isWeekClaimable(week, "2026-10-22"), false);
  });

  // Monday (UTC) the week is still Sunday somewhere, and the server accepts
  // a date one day off: a daily for that Sunday can still come in.
  test("not on the Monday after, either", () => {
    assert.equal(isWeekClaimable(week, "2026-10-26"), false);
  });

  test("from the Tuesday after on", () => {
    assert.equal(isWeekClaimable(week, "2026-10-27"), true);
    assert.equal(isWeekClaimable(week, "2026-11-30"), true);
  });

  test("never a week that hasn't started", () => {
    assert.equal(isWeekClaimable("2026-10-26", "2026-10-22"), false);
  });
});

describe("dailySubmissionCheck", () => {
  const H = 3600000;
  const now = Date.UTC(2026, 9, 22, 12);

  test("the first daily ever is fine", () => {
    const check = dailySubmissionCheck(undefined, [], "2026-10-22", now);
    assert.equal(check.ok, true);
    assert.deepEqual(check.recentMs, [now]);
  });

  test("a later date after the last one is fine", () => {
    const check = dailySubmissionCheck(
      "2026-10-21", [now - 20 * H], "2026-10-22", now
    );
    assert.equal(check.ok, true);
  });

  // Playing yesterday's date after today's was a way to get an extra one.
  test("not a date before or equal to the last one played", () => {
    assert.equal(
      dailySubmissionCheck("2026-10-22", [], "2026-10-21", now).ok, false
    );
    assert.equal(
      dailySubmissionCheck("2026-10-22", [], "2026-10-22", now).ok, false
    );
  });

  // Just before and just after midnight is two in a few minutes: fine.
  test("two in 24 hours is fine", () => {
    const check = dailySubmissionCheck(
      "2026-10-21", [now - 10 * 60000], "2026-10-22", now
    );
    assert.equal(check.ok, true);
    assert.deepEqual(check.recentMs, [now - 10 * 60000, now]);
  });

  // Yesterday, today and tomorrow in one sitting.
  test("a third in 24 hours is refused", () => {
    const check = dailySubmissionCheck(
      "2026-10-22", [now - 2 * H, now - H], "2026-10-23", now
    );
    assert.equal(check.ok, false);
  });

  test("older plays fall out of the window", () => {
    const check = dailySubmissionCheck(
      "2026-10-21", [now - 30 * H, now - 25 * H], "2026-10-22", now
    );
    assert.equal(check.ok, true);
    assert.deepEqual(check.recentMs, [now]);
  });
});
