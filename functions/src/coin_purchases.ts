/**
 * Pure policy for crediting a coin pack bought through a store.
 *
 * Kept out of index.ts so the rules that decide whether real money turns
 * into coins — what counts as paid, and what counts as a replay — can be
 * unit-tested without firebase-admin, the network or a store account.
 */

import {createHash} from "node:crypto";

/** What Play says about one purchase token, reduced to what we act on. */
export type PlayPurchaseVerdict =
  | {
      ok: true;
      /** Play's order id, for matching a support request to a payment. */
      orderId: string | null;
      purchaseTimeMillis: number | null;
      /** Already consumed: Play considers the item delivered. */
      consumed: boolean;
      /** Bought by a license tester, so no money moved. */
      test: boolean;
    }
  | {ok: false; reason: "not-purchased" | "pending"};

/**
 * Reads a Play `ProductPurchase` (androidpublisher v3,
 * `purchases.products.get`).
 *
 * Only `purchaseState === 0` is a payment. 1 is cancelled, and 2 is
 * pending — a cash or bank method that can take days to clear, or never
 * does. Anything else, including a missing field, is treated as unpaid:
 * a payment check that defaults to yes is not a payment check.
 * @param {unknown} body The JSON Play returned.
 * @return {PlayPurchaseVerdict} Whether it was paid, and the details kept.
 */
export function judgePlayProductPurchase(body: unknown): PlayPurchaseVerdict {
  if (body === null || typeof body !== "object") {
    return {ok: false, reason: "not-purchased"};
  }

  const purchase = body as Record<string, unknown>;

  if (purchase.purchaseState === 2) return {ok: false, reason: "pending"};
  if (purchase.purchaseState !== 0) {
    return {ok: false, reason: "not-purchased"};
  }

  const orderId = typeof purchase.orderId === "string" &&
    purchase.orderId !== "" ? purchase.orderId : null;

  const time = Number(purchase.purchaseTimeMillis);

  return {
    ok: true,
    orderId,
    purchaseTimeMillis: purchase.purchaseTimeMillis !== undefined &&
      Number.isFinite(time) ? time : null,
    consumed: purchase.consumptionState === 1,
    // purchaseType is absent for a real purchase; 0 is a license tester.
    test: purchase.purchaseType === 0,
  };
}

/** What to do with a paid purchase, given what the ledger already holds. */
export type CoinCreditDecision =
  | "credit"
  | "already-credited"
  | "claimed-by-another-account"
  | "consumed-elsewhere";

/**
 * Decides whether a paid purchase may be turned into coins now.
 *
 * The ledger is the only memory of what has been paid out, keyed by the
 * purchase token, so one token credits one account once:
 *
 * - The same account asking again is told it is done. The first response
 *   can be lost after the coins were credited, and the client only lets
 *   the store finish the purchase once it hears success.
 * - Another account presenting the same token is refused: that is the
 *   replay the ledger exists to stop.
 * - A token Play reports as consumed, with no ledger entry, is refused.
 *   Only this flow consumes, and only after crediting, so nothing here
 *   ever paid it out — and it must not start paying now.
 * @param {string | null} ledgerUid Account the token was credited to, or
 *   null if it never was.
 * @param {string} uid Account asking for the coins.
 * @param {boolean} consumed Whether Play reports the token as consumed.
 * @return {CoinCreditDecision} What to do.
 */
export function decideCoinCredit(
  ledgerUid: string | null,
  uid: string,
  consumed: boolean
): CoinCreditDecision {
  if (ledgerUid !== null) {
    return ledgerUid === uid ?
      "already-credited" :
      "claimed-by-another-account";
  }
  return consumed ? "consumed-elsewhere" : "credit";
}

/**
 * Ledger document id for a purchase token.
 *
 * A hash rather than the token: tokens can contain characters a document
 * id can't, and the ledger has no reason to hold a credential the store
 * would accept.
 * @param {string} purchaseToken Token from the store.
 * @return {string} 64 hex characters.
 */
export function purchaseLedgerId(purchaseToken: string): string {
  return createHash("sha256").update(purchaseToken).digest("hex");
}

/**
 * Play Developer API URL for one product purchase.
 * @param {string} packageName Android application id.
 * @param {string} productId In-app product id.
 * @param {string} purchaseToken Token from the purchase.
 * @return {string} The `purchases.products.get` URL.
 */
export function playProductPurchaseUrl(
  packageName: string,
  productId: string,
  purchaseToken: string
): string {
  return "https://androidpublisher.googleapis.com/androidpublisher/v3/" +
    `applications/${encodeURIComponent(packageName)}/purchases/products/` +
    `${encodeURIComponent(productId)}/tokens/` +
    `${encodeURIComponent(purchaseToken)}`;
}
