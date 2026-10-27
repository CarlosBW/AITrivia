/**
 * Pure rules for keeping players safe from each other: which usernames are
 * refused, and the shape of a report about another player (see
 * `enforceUsernamePolicy`, `checkUsername` and `reportPlayer` in
 * index.ts).
 *
 * Kept out of index.ts so they can be unit-tested without firebase-admin.
 */

/**
 * Insults and hate or sexual terms that are refused anywhere in a name.
 * Only words that are rarely part of an ordinary word: the short ones go
 * in [BLOCKED_WORDS] instead.
 */
const BLOCKED_ANYWHERE = [
  // Spanish (Peru and the rest of Latin America)
  "pendejo", "pendeja", "hijodeputa", "hijueputa", "maricon", "cabron",
  "mierda", "conchatumadre", "conchesumare", "malparido", "mamaguevo",
  "culero", "culiao", "culiado", "cojudo", "cojuda", "chupamela",
  "violador", "violacion", "pedofil", "terrorista",
  // English
  "fuck", "shit", "bitch", "asshole", "pussy", "whore", "slut", "nigger",
  "nigga", "faggot", "motherf", "pedophil",
  // Hate and sexual
  "hitler", "nazi", "porno", "porn", "hentai",
];

/**
 * Short terms refused only as a whole word of the name (split on "_",
 * digits and capitals): "puta" but not "computadora", "dick" but not
 * "Dickens".
 */
const BLOCKED_WORDS = [
  "puta", "putas", "puto", "putos", "culo", "verga", "pene", "perra",
  "zorra", "marica", "huevon", "weon", "ctm", "hdp", "csm", "gonorrea",
  "cunt", "dick", "cock", "fag", "rape", "retard", "sex", "sexo", "sexy",
  "xxx", "kkk", "heil",
];

/** Names that would pass for the game's own staff or company. */
const RESERVED = [
  "admin", "administrador", "administrator", "moderador", "moderator",
  "soporte", "support", "staff", "oficial", "official", "triviaia",
  "massivedynamics",
];

const LEET: Record<string, string> = {
  "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b",
};

/**
 * @param {string} text Lowercase letters.
 * @return {string} [text] with each run of a repeated letter as one.
 */
function collapseRepeats(text: string): string {
  return text.replace(/(.)\1+/g, "$1");
}

/**
 * @param {string} text Lowercase text.
 * @return {string} Digits used as letters ("p3nd3j0") read as letters.
 */
function readLeet(text: string): string {
  return text.replace(/[0-9]/g, (d) => LEET[d] ?? "");
}

/**
 * Whether [text] contains [term]. A term with no doubled letter also
 * matches with repeats collapsed ("peeendejo"); one that has them
 * ("nigger") only as written, or collapsing would match innocent words
 * ("niger").
 * @param {string} text Normalized name.
 * @param {string} term Lowercase term.
 * @return {boolean} Whether it's there.
 */
function containsTerm(text: string, term: string): boolean {
  if (text.includes(term)) return true;
  if (collapseRepeats(term) !== term) return false;
  return collapseRepeats(text).includes(term);
}

/**
 * The words of a name: split on "_", on a lowercase-to-capital change and
 * around digits at either end, then read as lowercase letters.
 * @param {string} username The name as typed.
 * @return {string[]} Its words.
 */
function wordsOf(username: string): string[] {
  return username
    .replace(/([a-z])([A-Z])/g, "$1_$2")
    .split("_")
    .map((part) => part.toLowerCase().replace(/^\d+|\d+$/g, ""))
    .map(readLeet)
    .filter((word) => word.length > 0);
}

/**
 * Why a username can't be taken, or null if it can. A first line of
 * defence, not a complete one: what gets past it is what reportPlayer is
 * for.
 * @param {string} username The name, already in the app's format
 *   (3-20 letters, digits and "_").
 * @return {"offensive"|"reserved"|null} The reason, or null.
 */
export function usernameViolation(
  username: string
): "offensive" | "reserved" | null {
  const plain = readLeet(username.toLowerCase()).replace(/[^a-z]/g, "");
  const words = wordsOf(username);

  if (BLOCKED_ANYWHERE.some((term) => containsTerm(plain, term))) {
    return "offensive";
  }
  if (words.some((word) => BLOCKED_WORDS.includes(collapseRepeats(word)) ||
      BLOCKED_WORDS.includes(word))) {
    return "offensive";
  }
  if (RESERVED.some((term) => plain.includes(term))) return "reserved";
  return null;
}

/** Reasons a player can give when reporting another one. */
export const PLAYER_REPORT_REASONS = new Set([
  "offensive_name",
  "cheating",
  "spam_or_harassment",
  "other",
]);

/** Reports one player can file about others per day. */
export const MAX_PLAYER_REPORTS_PER_DAY = 20;

/**
 * One report per reporter and reported player: reporting again updates
 * the first one instead of piling up.
 * @param {string} reporterUid Who reports.
 * @param {string} targetUid Who is reported.
 * @return {string} Firestore doc id.
 */
export function playerReportDocId(
  reporterUid: string, targetUid: string
): string {
  return `${reporterUid}__${targetUid}`;
}
