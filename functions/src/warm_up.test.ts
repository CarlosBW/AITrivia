import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {isWarmUpRequest} from "./warm_up";

describe("isWarmUpRequest", () => {
  test("a call that carries warm: true is a warm-up", () => {
    assert.equal(isWarmUpRequest({warm: true}), true);
  });

  // A real answer must never be swallowed: the player would see no
  // verdict and the clock would keep running.
  test("a real request is not", () => {
    assert.equal(
      isWarmUpRequest({dateId: "2026-11-15", questionIndex: 0}), false
    );
    assert.equal(isWarmUpRequest({}), false);
  });

  test("only the literal true counts", () => {
    assert.equal(isWarmUpRequest({warm: "true"}), false);
    assert.equal(isWarmUpRequest({warm: 1}), false);
    assert.equal(isWarmUpRequest({warm: false}), false);
  });

  test("no data at all is not a warm-up", () => {
    assert.equal(isWarmUpRequest(null), false);
    assert.equal(isWarmUpRequest(undefined), false);
    assert.equal(isWarmUpRequest("warm"), false);
  });
});
