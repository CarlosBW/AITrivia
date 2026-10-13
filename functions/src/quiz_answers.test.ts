import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  TIMED_OUT_ANSWER,
  mergeRecordedAnswers,
  resumeIndexFromBanked,
  sessionAfterSubmit,
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

describe("sessionAfterSubmit", () => {
  const questions = [
    {q: "a", options: ["x", "y"], answerIndex: 0},
    {q: "b", options: ["x", "y"], answerIndex: 1},
  ];

  // Regression: a fixed-category session outlives its submission, and it
  // used to keep every banked answer. Reopening the level resumed past the
  // last question, so the client submitted the same run again without
  // showing a single question — a fresh XP grant per reopen, and a failed
  // level that could never be replayed.
  test("a submitted session reopens at the first question", () => {
    const session = {
      categoryId: "cine",
      levelNumber: 1,
      questions,
      answers: {"0": 1, "1": 1},
    };
    assert.equal(resumeIndexFromBanked(session.answers), 2);

    const reopened = sessionAfterSubmit(session);

    assert.equal(
      resumeIndexFromBanked(
        reopened.answers as Record<string, unknown> | undefined
      ),
      0
    );
  });

  test("keeps the slate and everything else about the session", () => {
    const reopened = sessionAfterSubmit({
      categoryId: "cine",
      levelNumber: 1,
      seed: 42,
      questions,
      answers: {"0": 1},
    });

    assert.deepEqual(reopened, {
      categoryId: "cine",
      levelNumber: 1,
      seed: 42,
      questions,
    });
  });

  test("leaves a session with nothing banked as it was", () => {
    const session = {categoryId: "cine", questions};

    assert.deepEqual(sessionAfterSubmit(session), session);
  });

  test("does not modify the session it was given", () => {
    const session = {questions, answers: {"0": 1}};

    sessionAfterSubmit(session);

    assert.deepEqual(session.answers, {"0": 1});
  });
});
