/// What a day's count is of. The names are the keys of the `stats` map the
/// server keeps for the day.
enum MissionStat {
  correct,
  soloLevels,
  greatLevels,
  streakLevels,
  dailyPlayed,
  weeklyRounds,
}

/// One goal: reach [target] in [stat] within the day.
class Mission {
  const Mission(this.id, this.stat, this.target);

  final String id;
  final MissionStat stat;
  final int target;
}

/// Daily missions as the app shows them: three goals a day and a chest for
/// doing all three.
///
/// Everything here mirrors functions/src/daily_missions.ts, which counts
/// what the player did and pays the chest; this only works out what to
/// draw. `test/services/daily_missions_sync_test.dart` keeps the two from
/// drifting apart.
class DailyMissions {
  DailyMissions._();

  /// The three slots, each with the missions it rotates through.
  static const List<List<Mission>> slots = [
    [
      Mission('correct_15', MissionStat.correct, 15),
      Mission('correct_25', MissionStat.correct, 25),
      Mission('correct_20', MissionStat.correct, 20),
    ],
    [
      Mission('play_daily', MissionStat.dailyPlayed, 1),
      Mission('solo_levels_2', MissionStat.soloLevels, 2),
      Mission('weekly_round', MissionStat.weeklyRounds, 1),
      Mission('solo_levels_3', MissionStat.soloLevels, 3),
    ],
    [
      Mission('streak_level', MissionStat.streakLevels, 1),
      Mission('great_level', MissionStat.greatLevels, 1),
    ],
  ];

  /// A level counts as "great" from this share of right answers.
  static const int greatLevelPercent = 90;

  /// A level counts for the streak mission from this run of right answers.
  static const int streakLevelRun = 5;

  static const int chestCoins = 10;
  static const int chestXp = 20;

  /// Missions run on Lima's day for everyone, which is UTC-5 all year.
  static const Duration _limaOffset = Duration(hours: -5);

  /// The missions day at [now], as the server names it.
  static String dateId(DateTime now) {
    final lima = now.toUtc().add(_limaOffset);
    return '${lima.year}-${lima.month.toString().padLeft(2, '0')}-'
        '${lima.day.toString().padLeft(2, '0')}';
  }

  /// When the day [now] falls on ends and the next missions begin.
  static DateTime nextReset(DateTime now) {
    final lima = now.toUtc().add(_limaOffset);
    return DateTime.utc(lima.year, lima.month, lima.day + 1)
        .subtract(_limaOffset);
  }

  /// The missions of the day [dateId]: one from each slot, each slot
  /// moving on by one a day.
  static List<Mission> forDate(String dateId) {
    final date = DateTime.tryParse('${dateId}T00:00:00Z');
    if (date == null) return const [];
    final day = date.millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;
    return [for (final slot in slots) slot[day % slot.length]];
  }
}

/// A player's missions day as the server stored it.
class MissionsDay {
  const MissionsDay({
    required this.dateId,
    this.stats = const {},
    this.chestClaimed = false,
  });

  /// From the day's doc, or an untouched day when there is none yet: the
  /// doc is only written once the player does something that counts.
  factory MissionsDay.fromDoc(String dateId, Map<String, dynamic>? data) {
    final raw = data?['stats'];
    return MissionsDay(
      dateId: dateId,
      stats: {
        if (raw is Map)
          for (final stat in MissionStat.values)
            if (raw[stat.name] is num && (raw[stat.name] as num) > 0)
              stat: (raw[stat.name] as num).toInt(),
      },
      chestClaimed: data?['chestClaimed'] == true,
    );
  }

  final String dateId;
  final Map<MissionStat, int> stats;
  final bool chestClaimed;

  List<Mission> get missions => DailyMissions.forDate(dateId);

  /// How far along [mission] is, never past its target.
  int progress(Mission mission) {
    final done = stats[mission.stat] ?? 0;
    return done > mission.target ? mission.target : done;
  }

  bool isDone(Mission mission) => progress(mission) >= mission.target;

  int get doneCount => missions.where(isDone).length;

  /// Every mission done: the chest can be opened, unless it already was.
  bool get allDone => missions.isNotEmpty && missions.every(isDone);

  bool get chestReady => allDone && !chestClaimed;
}
