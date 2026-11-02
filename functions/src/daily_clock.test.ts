import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {dailyAnswerTooLate, dailyRemainingMs} from "./daily_clock";

const START = Date.parse("2026-11-02T14:00:00Z");
const DURATION_MS = 120_000;
const GRACE_MS = 30_000;

describe("dailyRemainingMs", () => {
  test("counts down from the start the server stamped", () => {
    assert.equal(dailyRemainingMs(START, DURATION_MS, START), 120_000);
    assert.equal(dailyRemainingMs(START, DURATION_MS, START + 99_500), 20_500);
  });

  test("never goes below zero once the clock is out", () => {
    assert.equal(dailyRemainingMs(START, DURATION_MS, START + 500_000), 0);
  });

  test("is unknown without a start", () => {
    assert.equal(dailyRemainingMs(undefined, DURATION_MS, START), null);
  });
});

describe("dailyAnswerTooLate", () => {
  test("accepts answers until the clock plus the grace runs out", () => {
    assert.equal(
      dailyAnswerTooLate(START, DURATION_MS, START + 150_000, GRACE_MS),
      false
    );
    assert.equal(
      dailyAnswerTooLate(START, DURATION_MS, START + 150_001, GRACE_MS),
      true
    );
  });

  test("never refuses a session without a start", () => {
    assert.equal(
      dailyAnswerTooLate(undefined, DURATION_MS, START + 10_000_000, GRACE_MS),
      false
    );
  });
});
