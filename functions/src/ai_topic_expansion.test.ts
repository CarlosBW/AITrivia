import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  expansionTarget,
  trustedBufferLevel,
  undeliveredRefund,
} from "./ai_topic_expansion";

describe("expansionTarget", () => {
  test("adds one batch of levels to the topic's current ceiling", () => {
    assert.deepEqual(
      expansionTarget({currentTarget: 10, perExpansion: 10}),
      {ok: true, newTarget: 20}
    );
  });

  test("a request that saw the same ceiling goes through", () => {
    assert.deepEqual(
      expansionTarget({currentTarget: 20, perExpansion: 10, seenTarget: 20}),
      {ok: true, newTarget: 30}
    );
  });

  // A double tap sent two requests that both saw 10 levels: the second
  // used to be charged again and expand a second time.
  test("a request that saw an older ceiling is refused", () => {
    assert.deepEqual(
      expansionTarget({currentTarget: 20, perExpansion: 10, seenTarget: 10}),
      {ok: false}
    );
  });

  test("an older app that sends nothing keeps working", () => {
    assert.deepEqual(
      expansionTarget({currentTarget: 20, perExpansion: 10,
        seenTarget: undefined}),
      {ok: true, newTarget: 30}
    );
  });
});

describe("trustedBufferLevel", () => {
  test("the level being played is the one after the last passed", () => {
    assert.equal(trustedBufferLevel(3, [1, 2]), 3);
  });

  test("a new topic buffers from its first level", () => {
    assert.equal(trustedBufferLevel(0, []), 0);
    assert.equal(trustedBufferLevel(1, []), 1);
  });

  // Regression: the number was used as sent, so reporting a high level
  // generated every remaining level of the topic in one call.
  test("a level the player can't have reached is cut back", () => {
    assert.equal(trustedBufferLevel(99, [1, 2]), 3);
    assert.equal(trustedBufferLevel(99, []), 1);
  });

  test("replaying an early level buffers from there", () => {
    assert.equal(trustedBufferLevel(2, [1, 2, 3, 4, 5]), 2);
  });

  test("nonsense is treated as nothing reported", () => {
    assert.equal(trustedBufferLevel(-5, [1]), 0);
  });
});

describe("undeliveredRefund", () => {
  test("nothing back when every level gained questions", () => {
    assert.equal(undeliveredRefund(150, 50, 3), 0);
  });

  // Regression: a level whose batch was all repeats was charged anyway.
  test("the levels that gained nothing are given back", () => {
    assert.equal(undeliveredRefund(150, 50, 2), 50);
    assert.equal(undeliveredRefund(150, 50, 0), 150);
  });

  test("never gives back more than was paid, nor less than nothing", () => {
    assert.equal(undeliveredRefund(150, 50, 9), 0);
    assert.equal(undeliveredRefund(150, 50, -1), 150);
  });
});
