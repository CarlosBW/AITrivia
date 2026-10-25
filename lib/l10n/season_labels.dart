import 'package:intl/intl.dart';

import 'generated/app_localizations.dart';

/// Names for the ids the game stores — a PvP season, a weekly league's
/// week, a difficulty tier — in the player's language, instead of the id.
extension SeasonLabels on AppLocalizations {
  /// 'pvp_2026_10' → "Octubre de 2026" / "October 2026". An id it doesn't
  /// recognize is returned unchanged.
  String pvpSeasonName(String seasonId) {
    final match = RegExp(r'^pvp_(\d{4})_(\d{2})$').firstMatch(seasonId);
    if (match == null) return seasonId;
    final month = DateTime(int.parse(match[1]!), int.parse(match[2]!));
    final text = DateFormat.yMMMM(localeName).format(month);
    return text[0].toUpperCase() + text.substring(1);
  }

  /// A week, stored as its Monday ('2026-10-19') → "Semana del 19 oct
  /// 2026". An id it doesn't recognize is returned unchanged.
  String weekLabel(String weekId) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(weekId)) return weekId;
    final monday = DateTime.tryParse(weekId);
    if (monday == null) return weekId;
    return weekOfLabel(DateFormat.yMMMd(localeName).format(monday));
  }

  /// A difficulty tier (1-3) by name.
  String difficultyLabel(int difficulty) {
    if (difficulty >= 3) return friendChallengeDiffHard;
    if (difficulty == 2) return friendChallengeDiffMedium;
    return friendChallengeDiffEasy;
  }
}
