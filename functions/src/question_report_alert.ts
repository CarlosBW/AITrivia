/**
 * The email the team gets when a player reports a question (see
 * `emailQuestionReport` in index.ts).
 *
 * Reports used to be collected silently, then as an in-app notification
 * that showed neither the options nor what the player had picked, and
 * landed on whichever account happened to be listed. Kept out of index.ts
 * so the wording can be tested without firebase-admin.
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

/**
 * Emails sent per day at most. The Resend account is shared with another
 * product (100 a day between both), so a burst of reports can't use it up;
 * past this, reports are still stored, just not emailed.
 */
export const MAX_REPORT_EMAILS_PER_DAY = 20;

const CONSOLE_DATA_URL =
  "https://console.firebase.google.com/u/1/project/trivia-ia-app/" +
  "firestore/data/";

/** The fields of a stored report the email reads; all optional. */
export interface StoredReport {
  reason?: unknown;
  details?: unknown;
  categoryId?: unknown;
  difficulty?: unknown;
  levelNumber?: unknown;
  mode?: unknown;
  docId?: unknown;
  /** AI-topic reports keep the text even when the question is gone. */
  questionText?: unknown;
  question?: {q?: unknown; options?: unknown; answerIndex?: unknown} | null;
  /** null: no answer; missing: the app predates sending it. */
  selectedIndex?: unknown;
}

/**
 * Escapes text for an HTML body.
 * @param {string} text Plain text.
 * @return {string} Safe HTML.
 */
function escapeHtml(text: string): string {
  return text.replace(/&/g, "&amp;").replace(/</g, "&lt;")
    .replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

/**
 * The email for one new report.
 * @param {"fixed" | "ai"} kind Which collection the report landed in.
 * @param {string} reportId The report document's id.
 * @param {StoredReport} report The report document's data.
 * @return {{subject: string, text: string, html: string}} The email.
 */
export function questionReportEmail(
  kind: "fixed" | "ai",
  reportId: string,
  report: StoredReport
): {subject: string; text: string; html: string} {
  const reason = REASON_LABELS[String(report.reason ?? "")] ??
    REASON_LABELS.other;

  const where = kind === "ai" ?
    `Tema IA${
      typeof report.levelNumber === "number" ?
        `, nivel ${report.levelNumber}` : ""
    }` :
    `${String(report.categoryId || "Tema fijo")}${
      typeof report.difficulty === "number" ?
        `, dificultad ${report.difficulty}` : ""
    }`;

  const question = String(
    report.question?.q || report.questionText || ""
  ).trim() || "(sin texto)";
  const options = Array.isArray(report.question?.options) ?
    report.question.options.map((o) => String(o)) : [];
  const answerIndex = Number(report.question?.answerIndex);
  const selected = report.selectedIndex;
  const details = String(report.details || "").trim();

  const optionLines = options.map((option, i) => {
    const marks: string[] = [];
    if (i === answerIndex) marks.push("correcta");
    if (i === selected) marks.push("eligió el jugador");
    const letter = String.fromCharCode(65 + i);
    const note = marks.length ? `  ← ${marks.join(", ")}` : "";
    return `${letter}. ${option}${note}`;
  });

  let answered = "";
  if (selected === undefined) {
    answered = "Respuesta del jugador: no registrada (versión anterior " +
      "de la app)";
  } else if (selected === null) {
    answered = "Respuesta del jugador: no respondió (se acabó el tiempo)";
  }

  const collection = kind === "ai" ? "ai_question_reports" :
    "question_reports";
  const link = `${CONSOLE_DATA_URL}~2F${collection}~2F${
    encodeURIComponent(reportId)
  }`;

  const lines = [
    `Motivo: ${reason}`,
    `Dónde: ${where}${report.mode ? ` (modo ${String(report.mode)})` : ""}`,
    "",
    question,
    ...optionLines,
    ...(answered ? ["", answered] : []),
    ...(details ? ["", `Comentario: ${details}`] : []),
    "",
    ...(report.docId ? [`Pregunta en el banco: ${String(report.docId)}`] : []),
    `Reporte: ${link}`,
  ];

  const text = lines.join("\n");
  const html = `<div style="font-family:sans-serif;line-height:1.5">${
    lines.map((line) => line === `Reporte: ${link}` ?
      `Reporte: <a href="${escapeHtml(link)}">abrir en Firestore</a>` :
      escapeHtml(line) || "&nbsp;"
    ).map((line) => `<div>${line}</div>`).join("")
  }</div>`;

  return {
    subject: `[TriviaIA] Pregunta reportada (${reason}): ${where}`,
    text,
    html,
  };
}
