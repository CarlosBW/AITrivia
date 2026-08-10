import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  ANSWER_GRACE_MS,
  REVEAL_DELAY_MS,
  TurnState,
  openTurn,
  resolveAnswer,
} from "./async_pvp_turns";
import {TIMED_OUT_ANSWER} from "./quiz_answers";

const NOW = 1_700_000_000_000;
const TIME_PER_QUESTION_SEC = 15;
const DURATION_MS = TIME_PER_QUESTION_SEC * 1000;

/**
 * A player's clock state, with the match defaults filled in.
 * @param {Partial<TurnState>} overrides Fields to change.
 * @return {TurnState} State to hand to openTurn/resolveAnswer.
 */
function state(overrides: Partial<TurnState> = {}): TurnState {
  return {
    questionCount: 10,
    timePerQuestionSec: TIME_PER_QUESTION_SEC,
    nowMs: NOW,
    ...overrides,
  };
}

describe("openTurn", () => {
  test("a fresh match starts at question 0 with a full clock", () => {
    const turn = openTurn(state());

    assert.equal(turn.index, 0);
    assert.equal(turn.finished, false);
    assert.deepEqual(turn.timedOutIndices, []);
    assert.equal(turn.deadlineMs, NOW + DURATION_MS);
    assert.equal(turn.deadlineIsNew, true);
    assert.equal(turn.remainingMs, DURATION_MS);
  });

  test("re-entering a live question keeps the deadline it already had", () => {
    const deadline = NOW + 4000;
    const turn = openTurn(state({deadlines: {"0": deadline}}));

    assert.equal(turn.index, 0);
    assert.equal(turn.deadlineMs, deadline);
    assert.equal(turn.deadlineIsNew, false, "must not be re-stamped");
    assert.equal(turn.remainingMs, 4000);
  });

  test("coming back after the clock ran out banks that question as a " +
    "timeout and moves on", () => {
    const turn = openTurn(state({
      answers: {"0": 2},
      deadlines: {"1": NOW - 60_000},
    }));

    assert.deepEqual(turn.timedOutIndices, [1]);
    assert.equal(turn.index, 2);
    assert.equal(turn.finished, false);
    assert.equal(turn.deadlineMs, NOW + DURATION_MS);
    assert.equal(turn.deadlineIsNew, true);
    assert.equal(turn.remainingMs, DURATION_MS,
      "the question after the lost one starts on a full clock");
  });

  test("only the question in flight expires, however long the player " +
    "was away", () => {
    const turn = openTurn(state({
      questionCount: 10,
      deadlines: {"0": NOW - 86_400_000},
    }));

    assert.deepEqual(turn.timedOutIndices, [0],
      "a day away must not forfeit the whole match");
    assert.equal(turn.index, 1);
  });

  test("a deadline just inside the grace window is still live", () => {
    const deadline = NOW - ANSWER_GRACE_MS;
    const turn = openTurn(state({deadlines: {"0": deadline}}));

    assert.deepEqual(turn.timedOutIndices, []);
    assert.equal(turn.index, 0);
    assert.equal(turn.remainingMs, 0);
  });

  test("the last question expiring finishes the run", () => {
    const turn = openTurn(state({
      questionCount: 2,
      answers: {"0": 1},
      deadlines: {"1": NOW - 60_000},
    }));

    assert.deepEqual(turn.timedOutIndices, [1]);
    assert.equal(turn.finished, true);
    assert.equal(turn.index, 2);
    assert.equal(turn.deadlineMs, null);
  });

  test("every question answered is a finished run", () => {
    const turn = openTurn(state({
      questionCount: 2,
      answers: {"0": 1, "1": TIMED_OUT_ANSWER},
    }));

    assert.equal(turn.finished, true);
    assert.equal(turn.index, 2);
    assert.equal(turn.deadlineMs, null);
    assert.equal(turn.remainingMs, 0);
  });

  test("a gap left by a failed write does not drop the player back", () => {
    const turn = openTurn(state({answers: {"0": 1, "2": 3}}));

    assert.equal(turn.index, 3);
  });

  test("a garbage deadline is treated as unstamped", () => {
    const turn = openTurn(state({deadlines: {"0": "soon"}}));

    assert.equal(turn.deadlineMs, NOW + DURATION_MS);
    assert.equal(turn.deadlineIsNew, true);
  });

  test("a match with no configured time still gets a real clock", () => {
    const turn = openTurn(state({timePerQuestionSec: 0}));

    assert.equal(turn.remainingMs, 1000);
  });
});

describe("resolveAnswer", () => {
  const live = state({deadlines: {"0": NOW + 5000}});

  test("an answer inside the deadline is banked as tapped", () => {
    const result = resolveAnswer(live, 0, 2);

    assert.equal(result.kind, "accepted");
    if (result.kind !== "accepted") return;
    assert.equal(result.storedIndex, 2);
    assert.equal(result.timedOut, false);
    assert.equal(result.nextIndex, 1);
    assert.equal(result.finished, false);
  });

  test("the next question's clock covers the reveal pause", () => {
    const result = resolveAnswer(live, 0, 2);

    assert.equal(result.kind, "accepted");
    if (result.kind !== "accepted") return;
    assert.equal(result.nextRemainingMs, REVEAL_DELAY_MS + DURATION_MS);
    assert.equal(
      result.nextDeadlineMs, NOW + REVEAL_DELAY_MS + DURATION_MS
    );
  });

  test("an answer past the deadline is banked as a timeout", () => {
    const result = resolveAnswer(
      state({deadlines: {"0": NOW - ANSWER_GRACE_MS - 1}}), 0, 2
    );

    assert.equal(result.kind, "accepted");
    if (result.kind !== "accepted") return;
    assert.equal(result.storedIndex, TIMED_OUT_ANSWER);
    assert.equal(result.timedOut, true);
  });

  test("a late tap inside the grace window still counts", () => {
    const result = resolveAnswer(
      state({deadlines: {"0": NOW - ANSWER_GRACE_MS}}), 0, 2
    );

    assert.equal(result.kind, "accepted");
    if (result.kind !== "accepted") return;
    assert.equal(result.storedIndex, 2);
    assert.equal(result.timedOut, false);
  });

  test("the client's own timeout (-1) is banked as one", () => {
    const result = resolveAnswer(live, 0, TIMED_OUT_ANSWER);

    assert.equal(result.kind, "accepted");
    if (result.kind !== "accepted") return;
    assert.equal(result.storedIndex, TIMED_OUT_ANSWER);
    assert.equal(result.timedOut, false, "the clock had not run out");
  });

  test("a nonsense option index banks as a timeout", () => {
    for (const selected of [-7, 1.5, Number.NaN]) {
      const result = resolveAnswer(live, 0, selected);

      assert.equal(result.kind, "accepted");
      if (result.kind !== "accepted") continue;
      assert.equal(result.storedIndex, TIMED_OUT_ANSWER);
    }
  });

  test("answering the last question finishes the run", () => {
    const result = resolveAnswer(
      state({
        questionCount: 2,
        answers: {"0": 1},
        deadlines: {"1": NOW + 5000},
      }),
      1, 3
    );

    assert.equal(result.kind, "accepted");
    if (result.kind !== "accepted") return;
    assert.equal(result.finished, true);
    assert.equal(result.nextDeadlineMs, null);
    assert.equal(result.nextRemainingMs, 0);
  });

  test("the first answer for a question is final", () => {
    const result = resolveAnswer(
      state({answers: {"0": 1}, deadlines: {"0": NOW + 5000}}), 0, 2
    );

    assert.equal(result.kind, "already-answered");
  });

  test("a question the player was never served is refused", () => {
    const result = resolveAnswer(
      state({deadlines: {"0": NOW + 5000}}), 4, 2
    );

    assert.equal(result.kind, "not-current");
    if (result.kind !== "not-current") return;
    assert.equal(result.expected, 0);
  });

  test("an unstamped question is refused rather than opened", () => {
    const result = resolveAnswer(state(), 0, 2);

    assert.equal(result.kind, "not-started",
      "answering must never be what starts the clock");
  });

  test("indices outside the match are refused", () => {
    assert.equal(resolveAnswer(live, -1, 2).kind, "out-of-range");
    assert.equal(resolveAnswer(live, 10, 2).kind, "out-of-range");
    assert.equal(resolveAnswer(live, 1.5, 2).kind, "out-of-range");
  });
});
