/// A player's standing in one fixed category, read from its
/// `progress_fixed` document.
///
/// No Firestore here, so the rules for what to offer next can be tested.
class SoloProgress {
  final int levelCount;
  final Set<int> passedLevels;

  /// The lowest level not yet passed, capped at [levelCount].
  final int nextLevel;
  final bool completedAll;

  /// The last level played and how it went, when the doc records it.
  final int? lastLevel;
  final bool lastPassed;
  final int lastCorrect;
  final int lastTotal;

  const SoloProgress._({
    required this.levelCount,
    required this.passedLevels,
    required this.nextLevel,
    required this.completedAll,
    required this.lastLevel,
    required this.lastPassed,
    required this.lastCorrect,
    required this.lastTotal,
  });

  int get passedCount => passedLevels.length;

  factory SoloProgress.fromDoc(Map<String, dynamic> data, int levelCount) {
    bool inRange(int level) => level >= 1 && level <= levelCount;

    // Docs saved before `passedLevels` existed only have `levelStats`; a
    // level counts as passed at 40%, as on the server.
    final Set<int> passed;
    final rawPassed = data['passedLevels'];
    if (rawPassed is List) {
      passed = {
        for (final e in rawPassed)
          if (e is num && inRange(e.toInt())) e.toInt(),
      };
    } else {
      final stats = data['levelStats'];
      passed = {
        if (stats is Map)
          for (final entry in stats.entries)
            if (int.tryParse('${entry.key}') case final level?)
              if (inRange(level) &&
                  entry.value is Map &&
                  ((entry.value as Map)['percent'] ?? 0) is num &&
                  (((entry.value as Map)['percent'] ?? 0) as num) >= 0.4)
                level,
      };
    }

    var next = 1;
    while (passed.contains(next)) {
      next++;
    }
    final completedAll = data['completedAllLevels'] == true ||
        (levelCount > 0 && passed.length >= levelCount);
    if (next > levelCount) next = levelCount;

    final last = data['lastScore'];
    final lastMap = last is Map ? last : const {};
    final lastLevel = lastMap['levelNumber'];

    return SoloProgress._(
      levelCount: levelCount,
      passedLevels: passed,
      nextLevel: next,
      completedAll: completedAll,
      lastLevel: lastLevel is num ? lastLevel.toInt() : null,
      lastPassed: lastMap['passed'] == true,
      lastCorrect: (lastMap['correct'] as num?)?.toInt() ?? 0,
      lastTotal: (lastMap['total'] as num?)?.toInt() ?? 0,
    );
  }

  /// The level to offer the player: the last one again when they just
  /// failed a level they had never passed, otherwise the next unpassed one.
  /// Null when every level is passed.
  ({int level, bool retry})? get resume {
    final last = lastLevel;
    if (last != null && !lastPassed && !passedLevels.contains(last)) {
      return (level: last, retry: true);
    }
    if (completedAll) return null;
    return (level: nextLevel, retry: false);
  }
}
