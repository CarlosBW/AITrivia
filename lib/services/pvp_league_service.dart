import 'dart:math' as math;

import '../l10n/generated/app_localizations.dart';

class PvpLeagueInfo {
  final String id;
  final String name;
  final String emoji;
  final int minRating;
  final int maxRating;
  final int colorValue;

  const PvpLeagueInfo({
    required this.id,
    required this.name,
    required this.emoji,
    required this.minRating,
    required this.maxRating,
    required this.colorValue,
  });

  bool contains(int rating) => rating >= minRating && rating <= maxRating;

  int get span => math.max(1, maxRating - minRating + 1);

  double progressFor(int rating) {
    final clamped = rating.clamp(minRating, maxRating).toInt();
    return ((clamped - minRating) / span).clamp(0.0, 1.0);
  }

  String get label => '$emoji $name';
}

class PvpMatchmakingWindow {
  final int searchSeconds;
  final int allowedRatingGap;

  const PvpMatchmakingWindow({
    required this.searchSeconds,
    required this.allowedRatingGap,
  });
}

class PvpLeagueService {
  PvpLeagueService._();

  static final PvpLeagueService instance = PvpLeagueService._();

  static const int defaultRating = 1000;

  static const List<PvpLeagueInfo> leagues = [
    PvpLeagueInfo(
      id: 'bronze',
      name: 'Bronze',
      emoji: '🥉',
      minRating: 0,
      maxRating: 999,
      colorValue: 0xFF8D6E63,
    ),
    PvpLeagueInfo(
      id: 'silver',
      name: 'Silver',
      emoji: '🥈',
      minRating: 1000,
      maxRating: 1199,
      colorValue: 0xFF78909C,
    ),
    PvpLeagueInfo(
      id: 'gold',
      name: 'Gold',
      emoji: '🥇',
      minRating: 1200,
      maxRating: 1399,
      colorValue: 0xFFFFA000,
    ),
    PvpLeagueInfo(
      id: 'platinum',
      name: 'Platinum',
      emoji: '💎',
      minRating: 1400,
      maxRating: 1599,
      colorValue: 0xFF00ACC1,
    ),
    PvpLeagueInfo(
      id: 'diamond',
      name: 'Diamond',
      emoji: '🔷',
      minRating: 1600,
      maxRating: 1899,
      colorValue: 0xFF5E35B1,
    ),
    PvpLeagueInfo(
      id: 'master',
      name: 'Master',
      emoji: '👑',
      minRating: 1900,
      maxRating: 5000,
      colorValue: 0xFFD81B60,
    ),
  ];

  PvpLeagueInfo leagueForRating(int rating) {
    return leagues.firstWhere(
      (league) => league.contains(rating),
      orElse: () => rating < leagues.first.minRating ? leagues.first : leagues.last,
    );
  }

  PvpLeagueInfo leagueById(String id) {
    return leagues.firstWhere(
      (league) => league.id == id,
      orElse: () => leagues.first,
    );
  }

  PvpMatchmakingWindow windowForSearchSeconds(int seconds) {
    if (seconds < 10) {
      return const PvpMatchmakingWindow(searchSeconds: 0, allowedRatingGap: 100);
    }

    if (seconds < 20) {
      return const PvpMatchmakingWindow(searchSeconds: 10, allowedRatingGap: 250);
    }

    if (seconds < 30) {
      return const PvpMatchmakingWindow(searchSeconds: 20, allowedRatingGap: 500);
    }

    return const PvpMatchmakingWindow(searchSeconds: 30, allowedRatingGap: 999999);
  }

  int allowedRatingGapForSearchSeconds(int secondsSearching) {
    return windowForSearchSeconds(secondsSearching).allowedRatingGap;
  }

  String matchmakingLabelFor(AppLocalizations l10n, int seconds) {
    if (seconds < 10) return l10n.pvpWindowSameLeagueLabel;
    if (seconds < 20) return l10n.pvpWindowNearbyLeaguesLabel;
    if (seconds < 30) return l10n.pvpWindowExpandedRangeLabel;
    return l10n.pvpWindowAnyOpponentLabel;
  }

  String matchmakingDescriptionFor(AppLocalizations l10n, int seconds) {
    if (seconds < 10) return l10n.pvpWindowSameLeagueDescription;
    if (seconds < 20) return l10n.pvpWindowNearbyLeaguesDescription;
    if (seconds < 30) return l10n.pvpWindowExpandedRangeDescription;
    return l10n.pvpWindowAnyOpponentDescription;
  }

  String leagueLabelForRating(int rating) {
    final league = leagueForRating(rating);
    return '${league.emoji} ${league.name} League';
  }

  String formatDelta(int delta) => delta > 0 ? '+$delta' : '$delta';
}
