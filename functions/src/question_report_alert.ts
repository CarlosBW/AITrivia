/**
 * What the team is told when a player reports a question (see
 * `notifyQuestionReport*` in index.ts).
 *
 * Reports used to be collected silently: nothing told anyone one had come
 * in, so a wrong answer in a fixed category kept being served until
 * somebody thought to open Firestore. Kept out of index.ts so the wording
 * and the recipient list can be tested without firebase-admin.
 *
 * Spanish only: these go to the team, not to players.
 */

/** The reason codes `reportQuestion` accepts, in words. */
const REASON_LABELS: Record<string, string> = {
  wrong_answer: "respuesta mal marcada",
  confusing: "confusa",
  typo: "ortografía/traducción",
  inappropriate: "inapropiada",
  other: "otro",
};

/** Longest push body: phones cut a notification off around here anyway. */
const BODY_MAX_LENGTH = 240;

/**
 * The accounts to notify, from the comma- or space-separated setting.
 * Anything that couldn't be a Firestore document id is dropped, so a typo
 * in the setting can't make the trigger write somewhere unexpected.
 * @param {string} raw The setting's value.
 * @return {string[]} Distinct uids, in the order given.
 */
export function parseNotifyUids(raw: string): string[] {
  const uids = raw.split(/[\s,]+/)
    .map((uid) => uid.trim())
    .filter((uid) => /^[A-Za-z0-9_-]{1,128}$/.test(uid));
  return Array.from(new Set(uids));
}

/** The fields of a stored report the alert reads; all optional. */
export interface StoredReport {
  reason?: unknown;
  details?: unknown;
  categoryId?: unknown;
  levelNumber?: unknown;
  /** AI-topic reports keep the text directly. */
  questionText?: unknown;
  /** Fixed-bank reports keep the whole question. */
  question?: {q?: unknown} | null;
}

/**
 * The notification for one new report.
 * @param {"fixed" | "ai"} kind Which collection the report landed in.
 * @param {StoredReport} report The report document's data.
 * @return {{title: string, body: string}} The notification text.
 */
export function questionReportAlert(
  kind: "fixed" | "ai",
  report: StoredReport
): {title: string; body: string} {
  const reason = REASON_LABELS[String(report.reason ?? "")] ??
    REASON_LABELS.other;

  const where = kind === "ai" ?
    `Tema IA${
      typeof report.levelNumber === "number" ?
        `, nivel ${report.levelNumber}` : ""
    }` :
    String(report.categoryId || "Tema fijo");

  const question = String(
    (kind === "ai" ? report.questionText : report.question?.q) || ""
  ).trim();
  const details = String(report.details || "").trim();

  const parts = [where];
  if (question) parts.push(`«${question}»`);
  if (details) parts.push(`Comentario: ${details}`);

  let body = parts.join(" · ");
  if (body.length > BODY_MAX_LENGTH) {
    body = `${body.slice(0, BODY_MAX_LENGTH - 1)}…`;
  }

  return {title: `Pregunta reportada: ${reason}`, body};
}
