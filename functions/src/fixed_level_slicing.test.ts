import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  FIXED_LEVEL_BANDS,
  FIXED_LEVEL_QUESTION_COUNT,
  difficultyForLevel,
  fixedPoolTarget,
  nextSeenAfterDraw,
} from "./fixed_level_slicing";
import {selectSessionQuestions} from "./ai_question_bank";

/**
 * A pool of question ids, as the fixed pools name them.
 * @param {number} size How many questions the pool holds.
 * @return {string[]} q1..q{size}.
 */
function pool(size: number): string[] {
  return [...Array(size).keys()].map((i) => `q${i + 1}`);
}

describe("FIXED_LEVEL_BANDS", () => {
  test("covers levels 1-10 with no gaps and no overlap", () => {
    assert.equal(FIXED_LEVEL_BANDS[0].firstLevel, 1);
    assert.equal(
      FIXED_LEVEL_BANDS[FIXED_LEVEL_BANDS.length - 1].lastLevel,
      10
    );
    for (let i = 1; i < FIXED_LEVEL_BANDS.length; i++) {
      assert.equal(
        FIXED_LEVEL_BANDS[i].firstLevel,
        FIXED_LEVEL_BANDS[i - 1].lastLevel + 1,
        "bands must be contiguous"
      );
    }
  });

  test("each pool holds two passes through its band's levels", () => {
    // 60/80/60 is what tools/seed_fill_pools.js fills each category to:
    // twice what one run through the band asks, so a replay has fresh
    // questions to rotate in. If a band changes, the target follows it.
    assert.deepEqual([1, 2, 3].map(fixedPoolTarget), [60, 80, 60]);
    for (const band of FIXED_LEVEL_BANDS) {
      const levels = band.lastLevel - band.firstLevel + 1;
      assert.equal(
        fixedPoolTarget(band.difficulty),
        levels * FIXED_LEVEL_QUESTION_COUNT * 2
      );
    }
  });
});

describe("difficultyForLevel", () => {
  test("maps each level to its documented tier", () => {
    assert.deepEqual(
      [1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map(difficultyForLevel),
      [1, 1, 1, 2, 2, 2, 2, 3, 3, 3]
    );
  });

  test("keeps levels past the last band on the hardest tier", () => {
    // Preserves the original `else return 3` shape rather than returning
    // undefined for a level the bands don't name.
    assert.equal(difficultyForLevel(11), 3);
    assert.equal(difficultyForLevel(99), 3);
  });
});

describe("nextSeenAfterDraw", () => {
  test("adds what was just served to what was seen", () => {
    assert.deepEqual(
      nextSeenAfterDraw(pool(60), ["q1", "q2"], ["q3", "q4"]),
      ["q1", "q2", "q3", "q4"]
    );
  });

  test("once the whole pool is seen, a new round starts from this draw",
    () => {
      // Keeping only the latest draw means the next one avoids it, rather
      // than drawing at random from a pool that is all "seen".
      const ids = pool(20);
      const seen = ids.slice(0, 10);
      const drawn = ids.slice(10, 20);
      assert.deepEqual(nextSeenAfterDraw(ids, seen, drawn), drawn);
    });

  test("ignores ids that are no longer in the pool", () => {
    assert.deepEqual(
      nextSeenAfterDraw(pool(5), ["q1", "gone"], ["q2"]),
      ["q1", "q2"]
    );
  });
});

describe("replaying a band's levels", () => {
  /**
   * Plays [times] levels of a band against one pool, as
   * ensureSoloLevelSession does, and returns each slate.
   * @param {number} size Pool size.
   * @param {number} times How many levels are opened.
   * @return {Array<Array<string>>} The questions of each run.
   */
  function play(size: number, times: number): string[][] {
    const ids = pool(size);
    let seen: string[] = [];
    const runs: string[][] = [];
    for (let run = 0; run < times; run++) {
      const draw = selectSessionQuestions(
        ids, seen, 1000 + run, FIXED_LEVEL_QUESTION_COUNT
      );
      runs.push(draw.questionIds);
      seen = nextSeenAfterDraw(ids, seen, draw.questionIds);
    }
    return runs;
  }

  test("ten questions each time, never one twice in a run", () => {
    for (const run of play(60, 8)) {
      assert.equal(run.length, FIXED_LEVEL_QUESTION_COUNT);
      assert.equal(new Set(run).size, run.length);
    }
  });

  test("a 60-question pool serves six runs before any repeat", () => {
    // The first pass through levels 1-3 and their first replays.
    const firstSix = play(60, 6).flat();
    assert.equal(new Set(firstSix).size, 60);
  });

  test("the run after a full pass doesn't repeat the one before it", () => {
    const runs = play(60, 7);
    const last = new Set(runs[5]);
    assert.ok(runs[6].every((id) => !last.has(id)));
  });

  test("a pool smaller than a run serves all of it", () => {
    const [run] = play(4, 1);
    assert.deepEqual([...run].sort(), pool(4));
  });
});
