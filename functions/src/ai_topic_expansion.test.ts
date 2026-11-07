import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {expansionTarget} from "./ai_topic_expansion";

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
