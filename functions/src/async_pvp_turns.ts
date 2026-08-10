/**
 * Pure turn/clock logic for async (turn-based) PvP matches.
 *
 * The per-question countdown used to live entirely in the play screen: the
 * client decided when a question expired and then wrote the answer straight
 * into the match doc. That made the clock advisory — a modified client
 * could simply not run it — and firestore.rules could not help, because the
 * write it had to allow was the player editing their own answers map.
 *
 * Anchoring the clock means the server stamps a deadline for the question
 * the player is on and judges every submission against it. Kept in its own
 * module (like quiz_answers.ts) so it can be unit-tested without
 * firebase-admin: nothing here touches Firestore, and "now" is always an
 * argument.
 */

import {TIMED_OUT_ANSWER, resumeIndexFromBanked} from "./quiz_answers";

/**
 * How far past a deadline an answer is still taken at face value.
 *
 * The player's tap has to travel to the server, so judging against the raw
 * deadline would steal the round trip from them — and on a slow connection
 * that is most of the last second. Wide enough to cover a normal call,
 * narrow enough that it can't be played for an extra question's worth of
 * thinking time.
 */
export const ANSWER_GRACE_MS = 2500;

/**
 * The pause the play screen holds on a revealed answer before moving on.
 *
 * The next question's deadline is stamped when the previous one is
 * answered (so advancing costs no round trip), which means it has to
 * include this pause — otherwise every question after the first would
 * start already a second down. Mirrors `_revealDelay` in
 * async_match_play_screen.dart; keep both in sync.
 */
export const REVEAL_DELAY_MS = 1000;

/** One player's clock state within a match, as stored in the match doc. */
export interface TurnState {
  /** `{role}.answers`, keyed by question index. */
  answers?: Record<string, unknown>;
  /** `{role}.deadlines`, epoch millis keyed by question index. */
  deadlines?: Record<string, unknown>;
  questionCount: number;
  timePerQuestionSec: number;
  nowMs: number;
}

/** Where a player stands when they (re)open a match. */
export interface OpenTurnResult {
  /** Question to serve; equals `questionCount` when the run is over. */
  index: number;
  finished: boolean;
  /** Questions whose clock ran out while away — bank as timed out. */
  timedOutIndices: number[];
  /** Deadline for `index` (epoch millis), null once finished. */
  deadlineMs: number | null;
  /** True when `deadlineMs` was just stamped and has to be persisted. */
  deadlineIsNew: boolean;
  /** What the client should count down from, in millis. */
  remainingMs: number;
}

/** Outcome of judging one submitted answer against the stored clock. */
export type AnswerResolution =
  | {kind: "already-answered"}
  | {kind: "out-of-range"}
  | {kind: "not-current"; expected: number}
  | {kind: "not-started"}
  | {
      kind: "accepted";
      /** What to bank — the tap, or [TIMED_OUT_ANSWER] if it came late. */
      storedIndex: number;
      timedOut: boolean;
      nextIndex: number;
      /** Deadline to stamp for `nextIndex`, null on the last question. */
      nextDeadlineMs: number | null;
      nextRemainingMs: number;
      finished: boolean;
    };

/**
 * How long one question is worth, in millis.
 * @param {number} timePerQuestionSec The match's configured seconds.
 * @return {number} Duration in millis, never less than one second.
 */
function questionDurationMs(timePerQuestionSec: number): number {
  const seconds = Number.isFinite(timePerQuestionSec) ?
    Math.floor(timePerQuestionSec) : 0;
  return Math.max(seconds, 1) * 1000;
}

/**
 * The stored deadline for one question, if there is a usable one.
 * @param {Record<string, unknown>|undefined} deadlines The `deadlines` map.
 * @param {number} index Question index.
 * @return {number|null} Epoch millis, or null when none is stored.
 */
function readDeadline(
  deadlines: Record<string, unknown> | undefined, index: number
): number | null {
  if (!deadlines || typeof deadlines !== "object") return null;
  const value = deadlines[String(index)];
  if (typeof value !== "number" || !Number.isFinite(value)) return null;
  return value;
}

/**
 * The question a player should be served, and the clock it runs on.
 *
 * A deadline is stamped once per question and then left alone, so backing
 * out of the screen doesn't rewind it: come back after it passed and that
 * question is banked as timed out, exactly as if the countdown had been
 * watched. That is the point of anchoring it — leaving to look an answer
 * up used to be free, since nothing about the question was stored until it
 * was answered.
 * @param {TurnState} state The player's stored answers/deadlines plus now.
 * @return {OpenTurnResult} Question to serve and what to persist.
 */
export function openTurn(state: TurnState): OpenTurnResult {
  const {questionCount, nowMs} = state;
  const durationMs = questionDurationMs(state.timePerQuestionSec);
  const timedOutIndices: number[] = [];

  let index = resumeIndexFromBanked(state.answers);

  if (index < questionCount) {
    const stored = readDeadline(state.deadlines, index);

    if (stored !== null) {
      if (nowMs <= stored + ANSWER_GRACE_MS) {
        return {
          index,
          finished: false,
          timedOutIndices,
          deadlineMs: stored,
          deadlineIsNew: false,
          remainingMs: Math.max(stored - nowMs, 0),
        };
      }

      timedOutIndices.push(index);
      index++;
    }
  }

  if (index >= questionCount) {
    return {
      index: questionCount,
      finished: true,
      timedOutIndices,
      deadlineMs: null,
      deadlineIsNew: false,
      remainingMs: 0,
    };
  }

  return {
    index,
    finished: false,
    timedOutIndices,
    deadlineMs: nowMs + durationMs,
    deadlineIsNew: true,
    remainingMs: durationMs,
  };
}

/**
 * Judges one submitted answer against the stored clock.
 *
 * Answers are one-shot and strictly in order: the first write for a
 * question is final (so a replay can re-see it but not change it), and a
 * client can't reach ahead to a question it was never served. A late
 * submission is banked as [TIMED_OUT_ANSWER] rather than rejected — the
 * question has to close either way, or running the clock out would be a
 * way to keep it open.
 * @param {TurnState} state The player's stored answers/deadlines plus now.
 * @param {number} questionIndex Question being answered.
 * @param {number} selectedIndex Option tapped, or -1 for a local timeout.
 * @return {AnswerResolution} What to bank, and the next question's clock.
 */
export function resolveAnswer(
  state: TurnState, questionIndex: number, selectedIndex: number
): AnswerResolution {
  const {questionCount, nowMs} = state;
  const durationMs = questionDurationMs(state.timePerQuestionSec);

  if (!Number.isInteger(questionIndex) ||
      questionIndex < 0 ||
      questionIndex >= questionCount) {
    return {kind: "out-of-range"};
  }

  const answers = (state.answers && typeof state.answers === "object") ?
    state.answers : {};

  if (Object.prototype.hasOwnProperty.call(answers, String(questionIndex))) {
    return {kind: "already-answered"};
  }

  const expected = resumeIndexFromBanked(state.answers);
  if (questionIndex !== expected) {
    return {kind: "not-current", expected};
  }

  const deadlineMs = readDeadline(state.deadlines, questionIndex);
  if (deadlineMs === null) {
    return {kind: "not-started"};
  }

  const timedOut = nowMs > deadlineMs + ANSWER_GRACE_MS;

  // Anything that isn't a real option index banks as a timeout: it scores
  // as wrong either way, and it keeps junk out of the stored map.
  const sane = Number.isInteger(selectedIndex) && selectedIndex >= 0;
  const storedIndex = (timedOut || !sane) ? TIMED_OUT_ANSWER : selectedIndex;

  const nextIndex = questionIndex + 1;
  const finished = nextIndex >= questionCount;
  const nextRemainingMs = REVEAL_DELAY_MS + durationMs;

  return {
    kind: "accepted",
    storedIndex,
    timedOut,
    nextIndex,
    nextDeadlineMs: finished ? null : nowMs + nextRemainingMs,
    nextRemainingMs: finished ? 0 : nextRemainingMs,
    finished,
  };
}
