/// How much longer a wrong answer stays on screen than a right one.
///
/// A right answer needs no reading: the player already knows it. A wrong
/// one shows which option was the right one, and with the same short pause
/// the next question arrived before that could be taken in.
const Duration wrongAnswerExtraReveal = Duration(milliseconds: 1500);

/// How long a judged answer stays on screen before the next question, for
/// a screen whose usual pause is [base].
///
/// Only for screens whose clock stops while the answer is shown. Where the
/// server keeps counting (the daily challenge, PvP), a longer pause would
/// be paid for out of the player's own time.
Duration answerRevealPause({required bool correct, required Duration base}) =>
    correct ? base : base + wrongAnswerExtraReveal;
