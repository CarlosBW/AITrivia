import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  LIVE_LOBBY_MAX_AGE_MS,
  LIVE_SEARCH_ABANDONED_MS,
  REMATCH_REQUEST_TTL_MS,
  liveMatchIsOverdue,
  liveSearchIsAbandoned,
  overdueLiveMatchOutcome,
  pvpCooldownActive,
  rematchRequestIsFresh,
} from "./live_match_rules";

const NOW = 1_700_000_000_000;
const MINUTE = 60 * 1000;

describe("rematchRequestIsFresh", () => {
  test("a request just made stands", () => {
    assert.equal(rematchRequestIsFresh(NOW - 10_000, NOW), true);
    assert.equal(
      rematchRequestIsFresh(NOW - REMATCH_REQUEST_TTL_MS, NOW), true
    );
  });

  // Regression: accepted hours later, a request started the rematch against
  // a player who was gone, and the match was claimed as a win.
  test("a request from hours ago doesn't", () => {
    assert.equal(rematchRequestIsFresh(NOW - 3 * 60 * MINUTE, NOW), false);
    assert.equal(
      rematchRequestIsFresh(NOW - REMATCH_REQUEST_TTL_MS - 1, NOW), false
    );
  });

  test("a request with no usable stamp doesn't", () => {
    assert.equal(rematchRequestIsFresh(undefined, NOW), false);
    assert.equal(rematchRequestIsFresh(true, NOW), false);
    assert.equal(rematchRequestIsFresh(NaN, NOW), false);
    assert.equal(rematchRequestIsFresh(NOW + MINUTE, NOW), false);
  });
});

describe("pvpCooldownActive", () => {
  test("runs until its end", () => {
    assert.equal(pvpCooldownActive(NOW + 1, NOW), true);
    assert.equal(pvpCooldownActive(NOW, NOW), false);
    assert.equal(pvpCooldownActive(NOW - MINUTE, NOW), false);
  });

  test("a player never penalised has none", () => {
    assert.equal(pvpCooldownActive(null, NOW), false);
  });
});

describe("liveMatchIsOverdue", () => {
  const playing = {
    status: "playing",
    createdAtMs: NOW - 20 * MINUTE,
    startAtMs: NOW,
    questionCount: 10,
    timePerQuestionSec: 15,
  };

  /**
   * Whether a match is overdue some minutes after it started.
   * @param {object} match The match.
   * @param {number} minutes Minutes since NOW.
   * @return {boolean} The verdict.
   */
  const after = (match: typeof playing, minutes: number) =>
    liveMatchIsOverdue({...match, nowMs: NOW + minutes * MINUTE});

  test("a match still inside its questions is left alone", () => {
    assert.equal(after(playing, 2), false);
    // 10 questions x (15 s + 10 s) + 2 min of grace = 6 min 10 s.
    assert.equal(after(playing, 6), false);
  });

  // Regression: nothing closed a match both players had walked away from,
  // or one whose finisher left before the other stalled.
  test("a match long past its last question is closed", () => {
    assert.equal(after(playing, 7), true);
  });

  test("a longer match gets proportionally longer", () => {
    const long = {...playing, questionCount: 20, timePerQuestionSec: 30};
    assert.equal(after(long, 12), false);
    assert.equal(after(long, 16), true);
  });

  test("a lobby is given half an hour", () => {
    const lobby = {
      ...playing, status: "waiting", createdAtMs: NOW, startAtMs: null,
    };
    assert.equal(
      liveMatchIsOverdue({...lobby, nowMs: NOW + LIVE_LOBBY_MAX_AGE_MS}), false
    );
    assert.equal(
      liveMatchIsOverdue({...lobby, nowMs: NOW + LIVE_LOBBY_MAX_AGE_MS + 1}),
      true
    );
  });

  test("a match already closed is never touched", () => {
    for (const status of ["finished", "cancelled"]) {
      assert.equal(
        liveMatchIsOverdue({...playing, status, nowMs: NOW + 60 * MINUTE}),
        false
      );
    }
  });

  test("a match with no dates can't be judged", () => {
    assert.equal(liveMatchIsOverdue({
      ...playing, createdAtMs: null, startAtMs: null, nowMs: NOW + 60 * MINUTE,
    }), false);
  });
});

describe("overdueLiveMatchOutcome", () => {
  test("whoever finished beats whoever walked away", () => {
    assert.equal(overdueLiveMatchOutcome(true, false), "host-wins");
    assert.equal(overdueLiveMatchOutcome(false, true), "guest-wins");
  });

  test("a match nobody finished has no result", () => {
    assert.equal(overdueLiveMatchOutcome(false, false), "cancel");
  });

  test("two closed rounds only need settling", () => {
    assert.equal(overdueLiveMatchOutcome(true, true), "settle");
  });
});

describe("liveSearchIsAbandoned", () => {
  test("an entry with a recent heartbeat is a real search", () => {
    assert.equal(liveSearchIsAbandoned(NOW - 5_000, NOW), false);
    assert.equal(
      liveSearchIsAbandoned(NOW - LIVE_SEARCH_ABANDONED_MS, NOW), false
    );
  });

  test("one silent for minutes is stopped", () => {
    assert.equal(
      liveSearchIsAbandoned(NOW - LIVE_SEARCH_ABANDONED_MS - 1, NOW), true
    );
  });

  test("one that never had a heartbeat is stopped", () => {
    assert.equal(liveSearchIsAbandoned(null, NOW), true);
  });
});
