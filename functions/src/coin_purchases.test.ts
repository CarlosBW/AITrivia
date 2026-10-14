import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  decideCoinCredit,
  judgePlayProductPurchase,
  playProductPurchaseUrl,
  purchaseLedgerId,
} from "./coin_purchases";

// A Play ProductPurchase as purchases.products.get returns it for a
// completed, not yet consumed purchase.
const purchased = {
  kind: "androidpublisher#productPurchase",
  purchaseTimeMillis: "1760400000000",
  purchaseState: 0,
  consumptionState: 0,
  orderId: "GPA.1234-5678-9012-34567",
  acknowledgementState: 0,
};

describe("judgePlayProductPurchase", () => {
  test("accepts a completed purchase and keeps what support needs", () => {
    const verdict = judgePlayProductPurchase(purchased);

    assert.equal(verdict.ok, true);
    if (!verdict.ok) return;
    assert.equal(verdict.orderId, "GPA.1234-5678-9012-34567");
    assert.equal(verdict.purchaseTimeMillis, 1760400000000);
    assert.equal(verdict.consumed, false);
    assert.equal(verdict.test, false, "no purchaseType means real money");
  });

  test("a cancelled purchase is not paid for", () => {
    const verdict = judgePlayProductPurchase({...purchased, purchaseState: 1});

    assert.deepEqual(verdict, {ok: false, reason: "not-purchased"});
  });

  test("a pending purchase has not been paid yet", () => {
    // Cash payment methods leave a purchase pending for days. Crediting it
    // now would hand out coins for money that may never arrive.
    const verdict = judgePlayProductPurchase({...purchased, purchaseState: 2});

    assert.deepEqual(verdict, {ok: false, reason: "pending"});
  });

  test("a missing or odd purchaseState is not taken as paid", () => {
    const {purchaseState: _dropped, ...noState} = purchased;
    void _dropped;

    assert.deepEqual(
      judgePlayProductPurchase(noState),
      {ok: false, reason: "not-purchased"}
    );
    assert.deepEqual(
      judgePlayProductPurchase({...purchased, purchaseState: "0"}),
      {ok: false, reason: "not-purchased"},
      "only the number 0 means purchased"
    );
    assert.deepEqual(
      judgePlayProductPurchase(null),
      {ok: false, reason: "not-purchased"}
    );
  });

  test("reports a token that was already consumed", () => {
    const verdict = judgePlayProductPurchase({
      ...purchased,
      consumptionState: 1,
    });

    assert.equal(verdict.ok, true);
    if (!verdict.ok) return;
    assert.equal(verdict.consumed, true);
  });

  test("marks license-tester purchases as test", () => {
    const verdict = judgePlayProductPurchase({...purchased, purchaseType: 0});

    assert.equal(verdict.ok, true);
    if (!verdict.ok) return;
    assert.equal(verdict.test, true);
  });

  test("survives a purchase without orderId or time", () => {
    const {orderId: _o, purchaseTimeMillis: _t, ...bare} = purchased;
    void _o;
    void _t;
    const verdict = judgePlayProductPurchase(bare);

    assert.equal(verdict.ok, true);
    if (!verdict.ok) return;
    assert.equal(verdict.orderId, null);
    assert.equal(verdict.purchaseTimeMillis, null);
  });
});

describe("decideCoinCredit", () => {
  test("a new, unconsumed purchase is credited", () => {
    assert.equal(decideCoinCredit(null, "uid-a", false), "credit");
  });

  test("the same account asking again gets its coins acknowledged", () => {
    // The response to the first call can be lost after the coins were
    // credited. The client then asks again, and has to hear "done" or it
    // keeps the purchase pending forever.
    assert.equal(decideCoinCredit("uid-a", "uid-a", false), "already-credited");
    assert.equal(decideCoinCredit("uid-a", "uid-a", true), "already-credited");
  });

  test("a token already credited to another account is refused", () => {
    assert.equal(
      decideCoinCredit("uid-a", "uid-b", false),
      "claimed-by-another-account"
    );
  });

  test("a consumed token nobody here credited is refused", () => {
    // Only this flow consumes, and only after crediting: a consumed token
    // with no ledger entry was never paid out by us, and replaying it must
    // not start now.
    assert.equal(decideCoinCredit(null, "uid-a", true), "consumed-elsewhere");
  });
});

describe("purchaseLedgerId", () => {
  test("is stable for a token and differs between tokens", () => {
    assert.equal(purchaseLedgerId("token-1"), purchaseLedgerId("token-1"));
    assert.notEqual(purchaseLedgerId("token-1"), purchaseLedgerId("token-2"));
  });

  test("is a safe Firestore document id, not the token itself", () => {
    const id = purchaseLedgerId("abc/def.ghi-jkl");

    assert.match(id, /^[0-9a-f]{64}$/);
    assert.ok(!id.includes("abc"));
  });
});

describe("playProductPurchaseUrl", () => {
  test("escapes every path segment", () => {
    assert.equal(
      playProductPurchaseUrl(
        "pe.massivedynamics.triviaia",
        "coins_pack_small",
        "a/b+c"
      ),
      "https://androidpublisher.googleapis.com/androidpublisher/v3/" +
        "applications/pe.massivedynamics.triviaia/purchases/products/" +
        "coins_pack_small/tokens/a%2Fb%2Bc"
    );
  });
});
