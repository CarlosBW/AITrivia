import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  DailyPoolEntry,
  matchCandidates,
  orderByAscendingDifficulty,
  recentDailyServed,
  selectDailyEntries,
} from "./daily_question_set";

/**
 * `n` entries of one difficulty, ids prefixed so they stay identifiable.
 * @param {number} difficulty Tier to stamp on every entry.
 * @param {number} n How many entries to build.
 * @param {string} prefix Id prefix.
 * @return {DailyPoolEntry[]} Generated entries.
 */
function entries(
  difficulty: number, n: number, prefix = "q"
): DailyPoolEntry[] {
  return Array.from({length: n}, (_, i) => ({
    c: "cine",
    d: difficulty,
    q: `${prefix}${difficulty}_${i}`,
  }));
}

describe("selectDailyEntries", () => {
  test("takes the requested number from the shuffled order", () => {
    const selected = selectDailyEntries(entries(1, 10), new Map(), 4);

    assert.equal(selected.length, 4);
    assert.deepEqual(selected.map((e) => e.q), [
      "q1_0", "q1_1", "q1_2", "q1_3",
    ]);
  });

  test("prefers questions not served on recent days", () => {
    const pool = entries(1, 4);
    const selected = selectDailyEntries(
      pool, new Map([["cine/1/q1_0", 1], ["cine/1/q1_1", 1]]), 2
    );

    assert.deepEqual(selected.map((e) => e.q), ["q1_2", "q1_3"]);
  });

  // A short day is worse than a repeated question, so exclusions are a
  // preference and not a filter.
  test("falls back to recent rather than serving a short day", () => {
    const pool = entries(1, 3);
    const selected = selectDailyEntries(
      pool, new Map([["cine/1/q1_0", 1], ["cine/1/q1_1", 1]]), 3
    );

    assert.equal(selected.length, 3);
    assert.deepEqual(selected.map((e) => e.q).sort(), [
      "q1_0", "q1_1", "q1_2",
    ]);
  });

  // Question ids restart at q1 in every category and difficulty, so "q3"
  // served yesterday from Cine said nothing about Historia's q3 — yet the
  // id alone was what got compared, and on a full day almost every id
  // looked used, which let real repeats back in.
  test("a served question doesn't hide another category's same id", () => {
    const pool: DailyPoolEntry[] = [
      {c: "cine", d: 1, q: "q3"},
      {c: "historia", d: 1, q: "q3"},
    ];
    const selected = selectDailyEntries(
      pool, new Map([["cine/1/q3", 1]]), 1
    );

    assert.deepEqual(selected, [{c: "historia", d: 1, q: "q3"}]);
  });

  test("when it must repeat, it repeats the longest-ago first", () => {
    const pool = entries(1, 3);
    const selected = selectDailyEntries(
      pool,
      new Map([["cine/1/q1_0", 1], ["cine/1/q1_1", 9], ["cine/1/q1_2", 4]]),
      2
    );

    assert.deepEqual(selected.map((e) => e.q), ["q1_1", "q1_2"]);
  });

  test("never returns more than the pool holds", () => {
    assert.equal(selectDailyEntries(entries(1, 3), new Map(), 60).length, 3);
  });

  test("handles an empty pool and a zero limit", () => {
    assert.deepEqual(selectDailyEntries([], new Map(), 10), []);
    assert.deepEqual(selectDailyEntries(entries(1, 5), new Map(), 0), []);
  });
});

describe("recentDailyServed", () => {
  test("keys each served question by category, tier and id", () => {
    const served = recentDailyServed([
      {daysAgo: 1, questions: [
        {sourceCategoryId: "cine", sourceDifficulty: 2, sourceQuestionId: "q7"},
      ]},
    ]);

    assert.deepEqual([...served], [["cine/2/q7", 1]]);
  });

  test("keeps the most recent day a question was served", () => {
    const q = {sourceCategoryId: "arte", sourceDifficulty: 1,
      sourceQuestionId: "q1"};
    const served = recentDailyServed([
      {daysAgo: 6, questions: [q]},
      {daysAgo: 2, questions: [q]},
    ]);

    assert.equal(served.get("arte/1/q1"), 2);
  });

  test("ignores anything that isn't a served question", () => {
    const served = recentDailyServed([
      {daysAgo: 1, questions: [null, "x", {sourceQuestionId: "q1"}]},
      {daysAgo: 2, questions: undefined},
    ]);

    assert.equal(served.size, 0);
  });
});

describe("orderByAscendingDifficulty", () => {
  test("puts the easy tier first and the hard tier last", () => {
    const mixed = [
      ...entries(3, 2),
      ...entries(1, 2),
      ...entries(2, 2),
    ];

    const ordered = orderByAscendingDifficulty(mixed);

    assert.deepEqual(ordered.map((e) => e.d), [1, 1, 2, 2, 3, 3]);
  });

  // Stability is what keeps the day-to-day mix varying: the incoming order
  // is already shuffled, and only the tiers are rearranged.
  test("keeps the incoming order within a tier", () => {
    const sameTier = [
      {c: "cine", d: 2, q: "b"},
      {c: "cine", d: 2, q: "a"},
      {c: "cine", d: 2, q: "c"},
    ];

    assert.deepEqual(
      orderByAscendingDifficulty(sameTier).map((e) => e.q),
      ["b", "a", "c"]
    );
  });

  test("does not mutate its argument", () => {
    const original = [...entries(3, 1), ...entries(1, 1)];
    const before = original.map((e) => e.q);

    orderByAscendingDifficulty(original);

    assert.deepEqual(original.map((e) => e.q), before);
  });

  test("handles an empty day", () => {
    assert.deepEqual(orderByAscendingDifficulty([]), []);
  });
});

describe("matchCandidates", () => {
  const index: DailyPoolEntry[] = [
    {c: "cine", d: 1, q: "c1"},
    {c: "cine", d: 2, q: "c2"},
    {c: "musica", d: 1, q: "m1"},
    {c: "historia", d: 1, q: "h1"},
  ];
  // The scan stopped inside "historia": its entries are real questions,
  // but not all of them.
  const complete = ["cine", "musica"];

  test("a category's questions at the match difficulty", () => {
    const picked = matchCandidates(index, complete, "cine", 1);
    assert.deepEqual(picked?.map((e) => e.q), ["c1"]);
  });

  // Picking from part of a pool would skew every match in it, so the
  // caller lists the pool itself instead.
  test("nothing for a category the index doesn't fully cover", () => {
    assert.equal(matchCandidates(index, complete, "historia", 1), null);
    assert.equal(matchCandidates(index, complete, "ciencia", 1), null);
  });

  test("nothing when the category has no questions at that difficulty", () => {
    assert.equal(matchCandidates(index, complete, "musica", 3), null);
  });

  test("random draws from every indexed category at that difficulty", () => {
    const picked = matchCandidates(index, complete, "random", 1);
    assert.deepEqual(picked?.map((e) => e.q), ["c1", "m1", "h1"]);
  });

  test("random with nothing at that difficulty", () => {
    assert.equal(matchCandidates(index, complete, "random", 3), null);
  });
});
