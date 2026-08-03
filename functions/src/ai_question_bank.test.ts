import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  AI_QUESTIONS_PER_SESSION,
  AI_QUESTION_BANK_CAP,
  bankHeadroom,
  compareQuestionIds,
  nextQuestionId,
  nextQuestionIds,
  questionIdIndex,
  selectSessionQuestions,
} from "./ai_question_bank";

/**
 * `q_1 .. q_n`, the shape a level bank has after n generations.
 * @param {number} n How many questions the bank holds.
 * @return {string[]} Sequential question ids.
 */
function bank(n: number): string[] {
  return Array.from({length: n}, (_, i) => `q_${i + 1}`);
}

describe("questionIdIndex", () => {
  test("reads the numeric suffix", () => {
    assert.equal(questionIdIndex("q_1"), 1);
    assert.equal(questionIdIndex("q_10"), 10);
    assert.equal(questionIdIndex("q_137"), 137);
  });

  test("returns -1 for anything that isn't a q_N id", () => {
    for (const id of ["", "q_", "q_x", "question_1", "1", "q_1x"]) {
      assert.equal(questionIdIndex(id), -1, `for "${id}"`);
    }
  });
});

describe("compareQuestionIds", () => {
  // The bug this fixes: Firestore orders documents by id lexicographically,
  // which puts q_10 between q_1 and q_2.
  test("orders numerically, not lexicographically", () => {
    const lexicographic = [...bank(12)].sort();
    assert.deepEqual(
      lexicographic.slice(0, 3),
      ["q_1", "q_10", "q_11"],
      "sanity: plain sort really does interleave"
    );

    const numeric = [...bank(12)].sort(compareQuestionIds);
    assert.deepEqual(numeric, bank(12));
  });

  test("sorts unrecognized ids last, but deterministically", () => {
    const sorted = ["zzz", "q_2", "aaa", "q_1"].sort(compareQuestionIds);
    assert.deepEqual(sorted, ["q_1", "q_2", "aaa", "zzz"]);
  });
});

describe("nextQuestionId", () => {
  test("continues from the highest existing suffix", () => {
    assert.equal(nextQuestionId(bank(10)), "q_11");
  });

  test("starts at q_1 for an empty level", () => {
    assert.equal(nextQuestionId([]), "q_1");
  });

  test("does not collide after a question is deleted", () => {
    // Counting documents would hand out q_10 again and overwrite it.
    const withHole = bank(10).filter((id) => id !== "q_4");
    assert.equal(nextQuestionId(withHole), "q_11");
  });

  test("ignores ids that aren't q_N", () => {
    assert.equal(nextQuestionId(["legacy", "q_3"]), "q_4");
  });
});

describe("nextQuestionIds", () => {
  test("hands out a sequential run", () => {
    assert.deepEqual(
      nextQuestionIds(bank(10), 3),
      ["q_11", "q_12", "q_13"]
    );
  });

  test("returns nothing for a zero-length run", () => {
    assert.deepEqual(nextQuestionIds(bank(10), 0), []);
  });
});

describe("bankHeadroom", () => {
  test("reports what's left before the cap", () => {
    assert.equal(bankHeadroom(0), AI_QUESTION_BANK_CAP);
    assert.equal(bankHeadroom(10), AI_QUESTION_BANK_CAP - 10);
  });

  test("never goes negative once the cap is reached or passed", () => {
    assert.equal(bankHeadroom(AI_QUESTION_BANK_CAP), 0);
    assert.equal(bankHeadroom(AI_QUESTION_BANK_CAP + 25), 0);
  });
});

describe("selectSessionQuestions", () => {
  const seed = 12345;

  test("serves a full slate of unseen questions when the bank allows", () => {
    const draw = selectSessionQuestions(bank(30), [], seed);

    assert.equal(draw.questionIds.length, AI_QUESTIONS_PER_SESSION);
    assert.deepEqual(draw.repeatedIds, []);
    assert.equal(new Set(draw.questionIds).size, AI_QUESTIONS_PER_SESSION,
      "no duplicates within a single slate");
  });

  test("never serves a question the player has already seen while " +
    "unseen ones remain", () => {
    const seen = bank(10); // q_1..q_10 already played
    const draw = selectSessionQuestions(bank(30), seen, seed);

    assert.deepEqual(draw.repeatedIds, []);
    for (const id of draw.questionIds) {
      assert.ok(!seen.includes(id), `${id} was already seen`);
    }
  });

  test("a replay draws different questions than the first attempt", () => {
    const first = selectSessionQuestions(bank(30), [], seed);
    const second = selectSessionQuestions(bank(30), first.questionIds, seed);

    const overlap = second.questionIds
      .filter((id) => first.questionIds.includes(id));
    assert.deepEqual(overlap, [], "replay repeated a question");
  });

  test("exhausts the whole bank across successive replays", () => {
    const available = bank(30);
    const seen = new Set<string>();

    for (let attempt = 0; attempt < 3; attempt++) {
      const draw = selectSessionQuestions(available, seen, seed + attempt);
      assert.deepEqual(draw.repeatedIds, [], `attempt ${attempt} repeated`);
      draw.questionIds.forEach((id) => seen.add(id));
    }

    assert.equal(seen.size, 30, "every question should have been served once");
  });

  test("fills the slate with repeats once the bank is exhausted", () => {
    // Bank of 12, player has seen 8 — only 4 unseen left for a 10 slate.
    const seen = bank(8);
    const draw = selectSessionQuestions(bank(12), seen, seed);

    assert.equal(draw.questionIds.length, AI_QUESTIONS_PER_SESSION,
      "a short bank must not shorten the level");
    assert.equal(draw.repeatedIds.length, 6);
    assert.equal(new Set(draw.questionIds).size, AI_QUESTIONS_PER_SESSION,
      "filler must not duplicate within the slate");

    // The four unseen ones are all present.
    for (const id of ["q_9", "q_10", "q_11", "q_12"]) {
      assert.ok(draw.questionIds.includes(id), `${id} missing`);
    }
  });

  test("varies its filler between replays of an exhausted level", () => {
    const seen = bank(20);
    const a = selectSessionQuestions(bank(20), seen, 1);
    const b = selectSessionQuestions(bank(20), seen, 2);

    assert.notDeepEqual(a.questionIds, b.questionIds);
  });

  test("serves what it has when the bank is smaller than a slate", () => {
    const draw = selectSessionQuestions(bank(4), [], seed);

    assert.equal(draw.questionIds.length, 4);
    assert.deepEqual(draw.repeatedIds, []);
  });

  test("returns nothing for an empty bank rather than throwing", () => {
    const draw = selectSessionQuestions([], [], seed);

    assert.deepEqual(draw.questionIds, []);
    assert.deepEqual(draw.repeatedIds, []);
  });

  test("is deterministic for the same bank, history and seed", () => {
    const a = selectSessionQuestions(bank(30), bank(5), seed);
    const b = selectSessionQuestions(bank(30), bank(5), seed);

    assert.deepEqual(a.questionIds, b.questionIds);
  });

  test("orders a partial bank numerically", () => {
    // Fewer questions than a slate: every one is served, in bank order.
    const draw = selectSessionQuestions(
      ["q_10", "q_2", "q_1"], [], seed
    );
    assert.deepEqual(draw.questionIds, ["q_1", "q_2", "q_10"]);
  });
});
