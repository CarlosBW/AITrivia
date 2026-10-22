/**
 * Pure helpers for keeping a PvP match's answers away from its players.
 *
 * Both match collections (`matches`, `async_matches`) are readable by the
 * two players, and they used to carry every question's `answerIndex`. The
 * server judged answers against a clock, but a modified client could read
 * the right one before tapping. The key now lives in a `secret` doc the
 * rules never let a client read, the server returns each answer's verdict
 * as it is given, and the key is published on the match once it is over.
 *
 * Also decides when a live opponent counts as gone, from the deadlines the
 * server itself stamped rather than from the opponent's own heartbeat.
 *
 * Kept free of firebase-admin (like async_pvp_turns.ts) so it can be
 * unit-tested; "now" is always an argument.
 */

import {resumeIndexFromBanked} from "./quiz_answers";

/** A question as it travels: the text and options, maybe its answer. */
export type MatchQuestion = Record<string, unknown>;

/**
 * Splits a match's questions into what the players may read and the key.
 * @param {MatchQuestion[]} questions Questions as selected, with answers.
 * @return {{publicQuestions: MatchQuestion[], answerIndices: number[]}}
 * The questions without `answerIndex`, and the answers in the same order
 * (-1 where a question has none).
 */
export function splitAnswerKey(questions: MatchQuestion[]): {
  publicQuestions: MatchQuestion[];
  answerIndices: number[];
} {
  const publicQuestions: MatchQuestion[] = [];
  const answerIndices: number[] = [];

  for (const question of questions) {
    const rest = {...question};
    const raw = rest.answerIndex;
    delete rest.answerIndex;
    publicQuestions.push(rest);
    answerIndices.push(
      typeof raw === "number" && Number.isInteger(raw) && raw >= 0 ? raw : -1
    );
  }

  return {publicQuestions, answerIndices};
}

/**
 * Puts the key back on the questions, for scoring.
 *
 * A match created before the key moved out still has `answerIndex` inline
 * and no key doc; it is returned unchanged.
 * @param {unknown} questions The match's stored questions.
 * @param {unknown} answerIndices The secret key, if there is one.
 * @return {MatchQuestion[]} Questions each carrying `answerIndex`.
 */
export function mergeAnswerKey(
  questions: unknown,
  answerIndices: unknown
): MatchQuestion[] {
  if (!Array.isArray(questions)) return [];
  const key = Array.isArray(answerIndices) ? answerIndices : null;

  return questions.map((raw, i) => {
    const question = (raw && typeof raw === "object") ?
      {...(raw as MatchQuestion)} : {};
    if (key) {
      const value = key[i];
      question.answerIndex = typeof value === "number" ? value : -1;
    } else if (typeof question.answerIndex !== "number") {
      question.answerIndex = -1;
    }
    return question;
  });
}

/**
 * How long past an expired question a live opponent may go silent before
 * the other player can claim the match.
 *
 * Covers a reconnect, a backgrounded app brought back, a slow call — the
 * question itself already timed out, so waiting gives the stalled player
 * nothing but a chance to come back.
 */
export const OPPONENT_STALL_GRACE_MS = 30_000;

/** One live player's progress, as the server stored it. */
export interface LiveProgress {
  answers: Record<string, unknown> | undefined;
  deadlines: Record<string, unknown> | undefined;
  finished: boolean;
  questionCount: number;
  timePerQuestionSec: number;
  /** When the match started, epoch millis; null before it did. */
  startAtMs: number | null;
  nowMs: number;
}

/**
 * Whether a live opponent has stopped playing: the question they should be
 * on expired more than [OPPONENT_STALL_GRACE_MS] ago and nothing came in.
 *
 * Judged from the deadlines the server stamped on each question, which
 * only move when the player actually opens or answers one — unlike the
 * presence heartbeat this used to read, which the opponent's own client
 * writes and a script could keep fresh forever.
 * @param {LiveProgress} p The opponent's stored progress plus now.
 * @return {boolean} True if the match can be claimed.
 */
export function isOpponentUnresponsive(p: LiveProgress): boolean {
  if (p.finished || p.startAtMs === null) return false;

  const index = resumeIndexFromBanked(p.answers);
  if (index >= p.questionCount) return false;

  const stored = p.deadlines?.[String(index)];
  const deadlineMs = typeof stored === "number" ?
    stored :
    // Never opened: they had until the first question's time ran out.
    index === 0 ? p.startAtMs + Math.max(p.timePerQuestionSec, 1) * 1000 :
      null;

  // Answered the previous one but never opened this: its deadline was
  // stamped with that answer, so a missing one means nothing to judge yet.
  if (deadlineMs === null) return false;

  return p.nowMs > deadlineMs + OPPONENT_STALL_GRACE_MS;
}
