import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  OPPONENT_STALL_GRACE_MS,
  isOpponentUnresponsive,
  mergeAnswerKey,
  splitAnswerKey,
} from "./pvp_answer_key";

const questions = [
  {q: "¿2+2?", options: ["3", "4", "5", "6"], answerIndex: 1},
  {q: "¿Capital de Perú?", options: ["Lima", "Quito"], answerIndex: 0},
];

describe("splitAnswerKey", () => {
  // The hole: a match doc both players can read carried every question's
  // answerIndex, so a modified client could answer everything right.
  test("strips the answers from what the players can read", () => {
    const {publicQuestions} = splitAnswerKey(questions);
    for (const q of publicQuestions) {
      assert.equal("answerIndex" in q, false);
    }
    assert.deepEqual(publicQuestions[0], {
      q: "¿2+2?", options: ["3", "4", "5", "6"],
    });
  });

  test("keeps the answers, in order, for the server", () => {
    assert.deepEqual(splitAnswerKey(questions).answerIndices, [1, 0]);
  });

  test("a question without a usable answer keeps -1, never a guess", () => {
    const {answerIndices} = splitAnswerKey([{q: "x", options: ["a"]}]);
    assert.deepEqual(answerIndices, [-1]);
  });
});

describe("mergeAnswerKey", () => {
  test("puts the answers back for scoring", () => {
    const {publicQuestions, answerIndices} = splitAnswerKey(questions);
    assert.deepEqual(mergeAnswerKey(publicQuestions, answerIndices), questions);
  });

  // Matches created before the key moved out still carry it inline.
  test("a match that still holds its answers inline is left as it is", () => {
    assert.deepEqual(mergeAnswerKey(questions, undefined), questions);
  });

  test("a missing key leaves every question unanswerable", () => {
    const {publicQuestions} = splitAnswerKey(questions);
    const merged = mergeAnswerKey(publicQuestions, undefined);
    assert.deepEqual(merged.map((q) => q.answerIndex), [-1, -1]);
  });
});

describe("isOpponentUnresponsive", () => {
  const base = {
    questionCount: 10,
    timePerQuestionSec: 15,
    startAtMs: 1_000_000,
  };

  // The claim used to trust the opponent's own presence heartbeat, which a
  // script could keep writing so an honest player could never claim, and a
  // flaky connection could lose a player the match while still answering.
  // The server's own deadlines can't be faked either way.
  test("an opponent whose current question expired long ago is gone", () => {
    const deadline = base.startAtMs + 15_000;
    assert.equal(isOpponentUnresponsive({
      ...base,
      answers: {},
      deadlines: {"0": deadline},
      finished: false,
      nowMs: deadline + OPPONENT_STALL_GRACE_MS + 1,
    }), true);
  });

  test("an opponent still inside the grace is not", () => {
    const deadline = base.startAtMs + 15_000;
    assert.equal(isOpponentUnresponsive({
      ...base,
      answers: {},
      deadlines: {"0": deadline},
      finished: false,
      nowMs: deadline + OPPONENT_STALL_GRACE_MS - 1,
    }), false);
  });

  test("one who never opened a question is gone after the first", () => {
    const firstQuestionEnds = base.startAtMs + 15_000;
    assert.equal(isOpponentUnresponsive({
      ...base,
      answers: {},
      deadlines: {},
      finished: false,
      nowMs: firstQuestionEnds + OPPONENT_STALL_GRACE_MS + 1,
    }), true);
    assert.equal(isOpponentUnresponsive({
      ...base,
      answers: {},
      deadlines: {},
      finished: false,
      nowMs: firstQuestionEnds,
    }), false);
  });

  test("an opponent who already finished is never gone", () => {
    assert.equal(isOpponentUnresponsive({
      ...base,
      answers: {},
      deadlines: {},
      finished: true,
      nowMs: base.startAtMs + 10 * 60_000,
    }), false);
  });

  test("the question to watch is the one after the last banked answer", () => {
    // Answered 0 and 1; question 2's deadline is still ahead.
    assert.equal(isOpponentUnresponsive({
      ...base,
      answers: {"0": 1, "1": 2},
      deadlines: {"0": 1, "1": 2, "2": 5_000_000},
      finished: false,
      nowMs: 4_000_000,
    }), false);
  });

  test("a match that never started can't be claimed", () => {
    assert.equal(isOpponentUnresponsive({
      ...base,
      startAtMs: null,
      answers: {},
      deadlines: {},
      finished: false,
      nowMs: 99_000_000,
    }), false);
  });
});
