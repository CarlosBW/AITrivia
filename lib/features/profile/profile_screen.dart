import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/daily_challenge_service.dart';
import '../../services/player_level_service.dart';
import '../../services/league_service.dart';
import '../../services/weekly_league_service.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const Map<String, String> avatars = {
    'avatar_1': '🧠',
    'avatar_2': '🚀',
    'avatar_3': '🎮',
    'avatar_4': '🔥',
    'avatar_5': '⭐',
    'avatar_6': '🐱',
    'avatar_7': '🤖',
    'avatar_8': '🏆',
  };

  Future<void> _syncLeaderboardProfile({
    required String uid,
    required String username,
    required String avatarId,
  }) async {
    final db = FirebaseFirestore.instance;
    final batch = db.batch();

    final update = <String, dynamic>{
      'username': username,
      'displayName': username,
      'avatarId': avatarId,
      'updatedAt': FieldValue.serverTimestamp(),
    };

    // Daily leaderboard de hoy.
    final todayDateId = DailyChallengeService.instance.todayDateId();
    final dailyRef = db
        .collection('daily_leaderboards')
        .doc(todayDateId)
        .collection('players')
        .doc(uid);

    final dailySnap = await dailyRef.get();
    if (dailySnap.exists) {
      batch.set(dailyRef, update, SetOptions(merge: true));
    }

    // Weekly leaderboard actual. El usuario puede estar en cualquier liga
    // dependiendo de cuándo generó su score, así que revisamos las pocas ligas
    // existentes y actualizamos solo el documento que ya exista.
    final weekId = WeeklyLeagueService.instance.currentWeekId();

    for (final league in LeagueService.leagues) {
      final weeklyRef = db
          .collection('weekly_leagues')
          .doc(weekId)
          .collection(league.id)
          .doc(uid);

      final weeklySnap = await weeklyRef.get();
      if (weeklySnap.exists) {
        batch.set(weeklyRef, update, SetOptions(merge: true));
      }
    }

    await batch.commit();
  }

  Future<void> _editUsername({
    required BuildContext context,
    required DocumentReference<Map<String, dynamic>> userRef,
    required String currentUsername,
    required String currentAvatarId,
  }) async {
    final controller = TextEditingController(text: currentUsername);

    final newUsername = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit username'),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 20,
            decoration: const InputDecoration(
              hintText: 'Enter username',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, controller.text.trim());
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (newUsername == null || newUsername.trim().isEmpty) return;

    final username = newUsername.trim();
    final uid = FirebaseAuth.instance.currentUser!.uid;

    await userRef.set({
      'username': username,
      'displayName': username,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _syncLeaderboardProfile(
      uid: uid,
      username: username,
      avatarId: currentAvatarId,
    );
  }

  Future<void> _chooseAvatar({
    required BuildContext context,
    required DocumentReference<Map<String, dynamic>> userRef,
    required String currentAvatarId,
    required String currentUsername,
  }) async {
    final selectedAvatarId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Choose avatar',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 18),
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: avatars.entries.map((entry) {
                  final isSelected = entry.key == currentAvatarId;

                  return InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => Navigator.pop(sheetContext, entry.key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.deepPurple.withOpacity(0.16)
                            : Colors.black12,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: isSelected
                              ? Colors.deepPurple
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          entry.value,
                          style: const TextStyle(fontSize: 32),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );

    if (selectedAvatarId == null) return;

    final uid = FirebaseAuth.instance.currentUser!.uid;

    await userRef.set({
      'avatarId': selectedAvatarId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await _syncLeaderboardProfile(
      uid: uid,
      username: currentUsername,
      avatarId: selectedAvatarId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Player Profile'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userRef.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!.data() ?? {};

          final username = (data['username'] ??
                  data['displayName'] ??
                  'Player${uid.substring(0, 4)}')
              .toString();

          final avatarId = (data['avatarId'] ?? 'avatar_1').toString();
          final avatar = avatars[avatarId] ?? '🙂';

          final xp = ((data['xp'] ?? 0) as num).toInt();
          final coins = ((data['coins'] ?? 0) as num).toInt();
          final freeTopicPasses =
              ((data['freeTopicPasses'] ?? 0) as num).toInt();

          final gamesPlayed = ((data['gamesPlayed'] ?? 0) as num).toInt();
          final correctAnswers = ((data['correctAnswers'] ?? 0) as num).toInt();
          final wrongAnswers = ((data['wrongAnswers'] ?? 0) as num).toInt();

          final totalAnswers = correctAnswers + wrongAnswers;
          final accuracy = totalAnswers == 0
              ? 0
              : ((correctAnswers / totalAnswers) * 100).round();

          final dailyStreak = ((data['dailyStreak'] ?? 0) as num).toInt();
          final maxDailyStreak =
              ((data['maxDailyStreak'] ?? dailyStreak) as num).toInt();
          final bestDailyScore = ((data['bestDailyScore'] ?? 0) as num).toInt();
          final wins1v1 = ((data['wins1v1'] ?? 0) as num).toInt();
          final losses1v1 = ((data['losses1v1'] ?? 0) as num).toInt();

          final levelInfo = PlayerLevelService.instance.getLevelInfo(xp);
          final level = levelInfo.level;
          final leagueScore = ((data['leagueScore'] ?? 0) as num).toInt();

          final league = LeagueService.instance.getLeagueFromScore(
            leagueScore,
          );
          final levelXp = levelInfo.currentLevelXp;
          final xpRequired = levelInfo.xpRequired;
          final progress = levelInfo.progress;

          return ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.deepPurple.withOpacity(0.25),
                  ),
                ),
                child: Column(
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => _chooseAvatar(
                        context: context,
                        userRef: userRef,
                        currentAvatarId: avatarId,
                        currentUsername: username,
                      ),
                      child: CircleAvatar(
                        radius: 48,
                        backgroundColor: Colors.white.withOpacity(0.75),
                        child: Text(
                          avatar,
                          style: const TextStyle(fontSize: 44),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            username,
                            style: const TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Edit username',
                          onPressed: () => _editUsername(
                            context: context,
                            userRef: userRef,
                            currentUsername: username,
                            currentAvatarId: avatarId,
                          ),
                          icon: const Icon(Icons.edit),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Level $level',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Color(league.colorValue).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Color(league.colorValue),
                        ),
                      ),
                      child: Text(
                        '${league.emoji} ${league.name} League',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(league.colorValue),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'League Score: $leagueScore',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text('$levelXp / $xpRequired XP to next level'),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _ProfileStatCard(
                      icon: Icons.monetization_on,
                      label: 'Coins',
                      value: '$coins',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ProfileStatCard(
                      icon: Icons.style,
                      label: 'Free topics',
                      value: '$freeTopicPasses',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ProfileStatCard(
                      icon: Icons.local_fire_department,
                      label: 'Streak',
                      value: '$dailyStreak',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ProfileStatCard(
                      icon: Icons.whatshot,
                      label: 'Best streak',
                      value: '$maxDailyStreak',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const Text(
                'Stats',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              _WideStatTile(
                icon: Icons.sports_esports,
                label: 'Games played',
                value: '$gamesPlayed',
              ),
              _WideStatTile(
                icon: Icons.check_circle,
                label: 'Correct answers',
                value: '$correctAnswers',
              ),
              _WideStatTile(
                icon: Icons.cancel,
                label: 'Wrong answers',
                value: '$wrongAnswers',
              ),
              _WideStatTile(
                icon: Icons.percent,
                label: 'Accuracy',
                value: '$accuracy%',
              ),
              _WideStatTile(
                icon: Icons.emoji_events,
                label: 'Best Daily score',
                value: '$bestDailyScore',
              ),
              _WideStatTile(
                icon: Icons.groups,
                label: '1v1 record',
                value: '$wins1v1 W / $losses1v1 L',
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Text(
                  'Coming soon: achievements, profile frames, leagues, and premium avatars.',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProfileStatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ProfileStatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(icon, size: 25),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _WideStatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _WideStatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.black12,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
