import 'generated/app_localizations.dart';

/// League names in the player's language.
///
/// The services and the server name leagues in English ('Silver', and
/// 'Master II' for the upper Master tiers), and that is also what match
/// results and season rewards store — so every place that shows one goes
/// through here instead of printing it as it came.
extension LeagueNames on AppLocalizations {
  /// The league named by [idOrName]: an id ('silver') or a stored English
  /// name ('Silver', 'Master III'). Anything else is returned unchanged.
  String leagueName(String idOrName) {
    final parts = idOrName.trim().split(' ');
    final base = switch (parts.first.toLowerCase()) {
      'bronze' => leagueBronze,
      'silver' => leagueSilver,
      'gold' => leagueGold,
      'platinum' => leaguePlatinum,
      'diamond' => leagueDiamond,
      'master' => leagueMaster,
      _ => parts.first,
    };
    return [base, ...parts.skip(1)].join(' ');
  }
}
