import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  TIMED_OUT_ANSWER,
  mergeRecordedAnswers,
  resumeIndexFromBanked,
  isCorrectAnswer,
  openWeeklyRound,
  isSoloRunSubmittable,
  maxAnswersForElapsed,
  scoreNewAnswers,
} from "./quiz_answers";

describe("mergeRecordedAnswers", () => {
  test("uses the submitted answers when nothing was banked", () => {
    const merged = mergeRecordedAnswers(undefined, [
      {questionIndex: 1, selectedIndex: 3},
      {questionIndex: 0, selectedIndex: 2},
    ]);

    assert.deepEqual(merged, [
      {questionIndex: 0, selectedIndex: 2},
      {questionIndex: 1, selectedIndex: 3},
    ]);
  });

  // Regression: this is the whole point of banking answers. Leaving a
  // level mid-run and re-entering used to serve the same questions with a
  // clean slate, so a player could look the answers up in between.
  test("banked answers beat a submission that contradicts them", () => {
    const merged = mergeRecordedAnswers({"0": 1}, [
      {questionIndex: 0, selectedIndex: 3},
    ]);

    assert.deepEqual(merged, [{questionIndex: 0, selectedIndex: 1}]);
  });

  test("submitted answers fill in questions that were never banked", () => {
    const merged = mergeRecordedAnswers({"0": 1}, [
      {questionIndex: 0, selectedIndex: 3},
      {questionIndex: 1, selectedIndex: 2},
    ]);

    assert.deepEqual(merged, [
      {questionIndex: 0, selectedIndex: 1},
      {questionIndex: 1, selectedIndex: 2},
    ]);
  });

  test("keeps a banked timeout instead of a later real answer", () => {
    const merged = mergeRecordedAnswers({"2": TIMED_OUT_ANSWER}, [
      {questionIndex: 2, selectedIndex: 0},
    ]);

    assert.deepEqual(merged, [
      {questionIndex: 2, selectedIndex: TIMED_OUT_ANSWER},
    ]);
  });

  test("keeps the first submitted answer for a repeated index", () => {
    const merged = mergeRecordedAnswers(undefined, [
      {questionIndex: 0, selectedIndex: 1},
      {questionIndex: 0, selectedIndex: 2},
    ]);

    assert.deepEqual(merged, [{questionIndex: 0, selectedIndex: 1}]);
  });

  test("ignores malformed banked entries and negative indices", () => {
    const merged = mergeRecordedAnswers(
      {"x": 1, "-1": 2, "1": "3" as unknown as number, "0": 4},
      [{questionIndex: -2, selectedIndex: 1}]
    );

    assert.deepEqual(merged, [{questionIndex: 0, selectedIndex: 4}]);
  });

  test("returns nothing when there is nothing to score", () => {
    assert.deepEqual(mergeRecordedAnswers(undefined, []), []);
    assert.deepEqual(mergeRecordedAnswers({}, []), []);
  });
});

describe("resumeIndexFromBanked", () => {
  test("starts a fresh run at the first question", () => {
    assert.equal(resumeIndexFromBanked(undefined), 0);
    assert.equal(resumeIndexFromBanked({}), 0);
  });

  test("resumes after the deepest banked question", () => {
    assert.equal(resumeIndexFromBanked({"0": 1, "1": 2}), 2);
  });

  test("does not replay earlier questions when a write was lost", () => {
    assert.equal(resumeIndexFromBanked({"0": 1, "3": 2}), 4);
  });

  test("ignores malformed keys", () => {
    assert.equal(resumeIndexFromBanked({"x": 1, "2": 0}), 3);
  });
});

describe("isSoloRunSubmittable", () => {
  const start = 1_000_000;

  test("a run played at human speed can be submitted", () => {
    const banked = {"0": 1, "1": 0, "2": 3};
    assert.equal(isSoloRunSubmittable(banked, start, start + 9_000), true);
  });

  // The hole: a fixed-category session outlives its submission, so a
  // script could submit the same level over and over, filling the answers
  // in from the readable answer key, and collect XP and stats every call.
  test("a run with nothing banked is not a run", () => {
    assert.equal(isSoloRunSubmittable(undefined, undefined, start), false);
    assert.equal(isSoloRunSubmittable({}, start, start + 60_000), false);
  });

  test("answers banked faster than anyone can read are refused", () => {
    const banked: Record<string, unknown> = {};
    for (let i = 0; i < 10; i++) banked[String(i)] = 0;
    assert.equal(isSoloRunSubmittable(banked, start, start + 2_000), false);
    assert.equal(isSoloRunSubmittable(banked, start, start + 9_000), true);
  });

  test("a single banked answer needs no time at all", () => {
    assert.equal(isSoloRunSubmittable({"0": 2}, start, start), true);
  });

  // Sessions banked before the run clock existed have no start time. Only
  // the server writes it, on a run's first banked answer, so a missing one
  // can't be something a client arranged.
  test("a run banked before the clock existed is accepted", () => {
    assert.equal(
      isSoloRunSubmittable({"0": 1, "1": 1}, undefined, start), true
    );
  });
});

describe("scoreNewAnswers", () => {
  test("scores answers to questions not used before", () => {
    assert.deepEqual(
      scoreNewAnswers(
        [{questionId: "a", correct: true}, {questionId: "b", correct: false}],
        new Set()
      ),
      {correct: 1, answered: 2, questionIds: ["a", "b"]}
    );
  });

  // The hole: usedQuestionIds was recorded and never checked, so the same
  // known question submitted again and again reached the completion reward.
  test("ignores questions already used this week", () => {
    assert.deepEqual(
      scoreNewAnswers(
        [{questionId: "a", correct: true}, {questionId: "c", correct: true}],
        new Set(["a"])
      ),
      {correct: 1, answered: 1, questionIds: ["c"]}
    );
  });

  test("counts a question once even if sent twice in one round", () => {
    assert.deepEqual(
      scoreNewAnswers(
        [{questionId: "a", correct: true}, {questionId: "a", correct: true}],
        new Set()
      ),
      {correct: 1, answered: 1, questionIds: ["a"]}
    );
  });
});

describe("maxAnswersForElapsed", () => {
  // The daily round is timed by the client only, and the answer key is
  // readable, so a script could submit all 60 correct the moment it began.
  test("allows about one answer per reading time", () => {
    assert.equal(maxAnswersForElapsed(0, 60), 1);
    assert.equal(maxAnswersForElapsed(8_000, 60), 11);
  });

  test("never more than the round holds", () => {
    assert.equal(maxAnswersForElapsed(10 * 60_000, 60), 60);
  });

  test("a clock going backwards still allows one", () => {
    assert.equal(maxAnswersForElapsed(-5_000, 60), 1);
  });
});

describe("openWeeklyRound", () => {
  const round = {
    weekId: "2026-11-09",
    categoryId: "cine",
    questions: [{q: "a", options: ["x", "y"]}, {q: "b", options: ["x", "y"]}],
    answers: {"0": 1},
    results: {"0": {correct: false, correctIndex: 0}},
  };

  // Regression: every draw paid a life and replaced the round in progress,
  // so leaving at question 7 (or a retried call) lost the answers and the
  // life with them.
  test("a round left open for this topic is handed back", () => {
    assert.deepEqual(openWeeklyRound(round, "2026-11-09", "cine"), {
      questions: round.questions,
      answers: round.answers,
      results: round.results,
    });
  });

  test("a round nobody answered yet is handed back too", () => {
    const fresh = {...round, answers: {}, results: {}};
    assert.deepEqual(
      openWeeklyRound(fresh, "2026-11-09", "cine")?.answers, {}
    );
  });

  test("no round, no resume", () => {
    assert.equal(openWeeklyRound(undefined, "2026-11-09", "cine"), null);
  });

  test("last week's round is not this week's", () => {
    assert.equal(openWeeklyRound(round, "2026-11-16", "cine"), null);
    assert.equal(openWeeklyRound(round, "2026-11-09", "arte"), null);
  });

  test("a round without questions is drawn again", () => {
    assert.equal(
      openWeeklyRound({...round, questions: []}, "2026-11-09", "cine"), null
    );
  });

  // The questions go back to the app as they are, so a round that still
  // carries its key inline must never be the one returned.
  test("a round holding its own answer key is not handed back", () => {
    const keyed = {
      ...round,
      questions: [{q: "a", options: ["x", "y"], answerIndex: 1}],
    };
    assert.equal(openWeeklyRound(keyed, "2026-11-09", "cine"), null);
  });
});

describe("isCorrectAnswer", () => {
  test("the right option is right, another is wrong", () => {
    assert.equal(isCorrectAnswer(2, 2), true);
    assert.equal(isCorrectAnswer(1, 2), false);
  });

  test("running out of time is never right", () => {
    assert.equal(isCorrectAnswer(TIMED_OUT_ANSWER, 2), false);
  });

  // Regression: a missing key reads as -1, the same value a timeout is
  // banked as, so the two matched and the timeout scored.
  test("a timeout on a question with no key is not a point", () => {
    assert.equal(isCorrectAnswer(TIMED_OUT_ANSWER, -1), false);
  });
});
