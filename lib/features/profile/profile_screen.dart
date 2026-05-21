import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/daily_challenge_service.dart';
import '../../services/player_level_service.dart';
import '../../services/league_service.dart';
import '../../services/weekly_league_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
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

  late final String uid;
  late final DocumentReference<Map<String, dynamic>> userRef;

  Map<String, dynamic>? _userData;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    uid = FirebaseAuth.instance.currentUser!.uid;
    userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    _loadProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadProfile(showLoading: false);
    }
  }

  Future<void> _loadProfile({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final snap = await userRef.get();
      if (!mounted) return;

      setState(() {
        _userData = snap.data() ?? {};
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _syncTodayLeaderboardProfile({
    required String uid,
    String? username,
    String? avatarId,
  }) async {
    final dateId = DailyChallengeService.instance.todayDateId();

    final leaderboardRef = FirebaseFirestore.instance
        .collection('daily_leaderboards')
        .doc(dateId)
        .collection('players')
        .doc(uid);

    final leaderboardSnap = await leaderboardRef.get();
    if (!leaderboardSnap.exists) return;

    final update = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (username != null) {
      update['username'] = username;
      update['displayName'] = username;
    }

    if (avatarId != null) {
      update['avatarId'] = avatarId;
    }

    await leaderboardRef.set(update, SetOptions(merge: true));
  }

  Future<void> _syncCurrentWeeklyLeaderboardProfile({
    required String uid,
    required Map<String, dynamic> latestUserData,
    String? username,
    String? avatarId,
  }) async {
    final leagueScore = ((latestUserData['leagueScore'] ?? 0) as num).toInt();
    final league = LeagueService.instance.getLeagueFromScore(leagueScore);
    final weekId = WeeklyLeagueService.instance.currentWeekId();

    final weeklyRef = WeeklyLeagueService.instance.weeklyPlayerRef(
      uid: uid,
      weekId: weekId,
      leagueId: league.id,
    );

    final weeklySnap = await weeklyRef.get();
    if (!weeklySnap.exists) return;

    final update = <String, dynamic>{
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (username != null) {
      update['username'] = username;
      update['displayName'] = username;
    }

    if (avatarId != null) {
      update['avatarId'] = avatarId;
    }

    await weeklyRef.set(update, SetOptions(merge: true));
  }

  Future<void> _syncLeaderboardProfiles({
    String? username,
    String? avatarId,
  }) async {
    final latestUserSnap = await userRef.get();
    final latestUserData = latestUserSnap.data() ?? {};

    await Future.wait([
      _syncTodayLeaderboardProfile(
        uid: uid,
        username: username,
        avatarId: avatarId,
      ),
      _syncCurrentWeeklyLeaderboardProfile(
        uid: uid,
        latestUserData: latestUserData,
        username: username,
        avatarId: avatarId,
      ),
    ]);
  }

  Future<void> _editUsername({
    required BuildContext context,
    required String currentUsername,
  }) async {
    if (_saving) return;

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

    controller.dispose();

    if (newUsername == null || newUsername.trim().isEmpty) return;

    final username = newUsername.trim();
    if (username == currentUsername) return;

    setState(() => _saving = true);

    try {
      await userRef.set({
        'username': username,
        'usernameLower': username.toLowerCase(),
        'displayName': username,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _syncLeaderboardProfiles(username: username);
      await _loadProfile(showLoading: false);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil actualizado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error actualizando perfil: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseAvatar({
    required BuildContext context,
    required String currentAvatarId,
  }) async {
    if (_saving) return;

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

    if (selectedAvatarId == null || selectedAvatarId == currentAvatarId) return;

    setState(() => _saving = true);

    try {
      await userRef.set({
        'avatarId': selectedAvatarId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await _syncLeaderboardProfiles(avatarId: selectedAvatarId);
      await _loadProfile(showLoading: false);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Avatar actualizado')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error actualizando avatar: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        appBar: _ProfileAppBar(),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: const _ProfileAppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 42),
                const SizedBox(height: 12),
                Text(
                  'Error loading profile:\n$_error',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => _loadProfile(),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final data = _userData ?? {};

    final username = (data['username'] ??
            data['displayName'] ??
            'Player${uid.substring(0, 4)}')
        .toString();

    final avatarId = (data['avatarId'] ?? 'avatar_1').toString();
    final avatar = avatars[avatarId] ?? '🙂';

    final xp = ((data['xp'] ?? 0) as num).toInt();
    final coins = ((data['coins'] ?? 0) as num).toInt();
    final freeTopicPasses = ((data['freeTopicPasses'] ?? 0) as num).toInt();

    final gamesPlayed = ((data['gamesPlayed'] ?? 0) as num).toInt();
    final correctAnswers = ((data['correctAnswers'] ?? 0) as num).toInt();
    final wrongAnswers = ((data['wrongAnswers'] ?? 0) as num).toInt();

    final totalAnswers = correctAnswers + wrongAnswers;
    final accuracy =
        totalAnswers == 0 ? 0 : ((correctAnswers / totalAnswers) * 100).round();

    final dailyStreak = ((data['dailyStreak'] ?? 0) as num).toInt();
    final maxDailyStreak =
        ((data['maxDailyStreak'] ?? dailyStreak) as num).toInt();
    final bestDailyScore = ((data['bestDailyScore'] ?? 0) as num).toInt();
    final wins1v1 = ((data['wins1v1'] ?? 0) as num).toInt();
    final losses1v1 = ((data['losses1v1'] ?? 0) as num).toInt();
    final draws1v1 = ((data['draws1v1'] ?? 0) as num).toInt();
    final matches1v1 = ((data['matches1v1'] ?? 0) as num).toInt();

    final currentWinStreak1v1 =
        ((data['currentWinStreak1v1'] ?? 0) as num).toInt();

    final bestWinStreak1v1 = ((data['bestWinStreak1v1'] ?? 0) as num).toInt();

    final winrate1v1 =
        matches1v1 == 0 ? 0 : ((wins1v1 / matches1v1) * 100).round();

    final levelInfo = PlayerLevelService.instance.getLevelInfo(xp);
    final level = levelInfo.level;
    final leagueScore = ((data['leagueScore'] ?? 0) as num).toInt();

    final league = LeagueService.instance.getLeagueFromScore(
      leagueScore,
    );
    final levelXp = levelInfo.currentLevelXp;
    final xpRequired = levelInfo.xpRequired;
    final progress = levelInfo.progress;

    return Scaffold(
      appBar: const _ProfileAppBar(),
      body: Stack(
        children: [
          ListView(
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
                      onTap: _saving
                          ? null
                          : () => _chooseAvatar(
                                context: context,
                                currentAvatarId: avatarId,
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
                          onPressed: _saving
                              ? null
                              : () => _editUsername(
                                    context: context,
                                    currentUsername: username,
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
              const SizedBox(height: 20),
              const Text(
                '1 vs 1 Stats',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              _WideStatTile(
                icon: Icons.emoji_events,
                label: 'Victories',
                value: '$wins1v1',
              ),
              _WideStatTile(
                icon: Icons.close,
                label: 'Defeats',
                value: '$losses1v1',
              ),
              _WideStatTile(
                icon: Icons.handshake,
                label: 'Draws',
                value: '$draws1v1',
              ),
              _WideStatTile(
                icon: Icons.sports_martial_arts,
                label: 'Matches played',
                value: '$matches1v1',
              ),
              _WideStatTile(
                icon: Icons.percent,
                label: 'Winrate',
                value: '$winrate1v1%',
              ),
              _WideStatTile(
                icon: Icons.local_fire_department,
                label: 'Current streak',
                value: '$currentWinStreak1v1',
              ),
              _WideStatTile(
                icon: Icons.whatshot,
                label: 'Best streak',
                value: '$bestWinStreak1v1',
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
          ),
          if (_saving)
            Container(
              color: Colors.black.withOpacity(0.35),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text(
                      'Guardando...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ProfileAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ProfileAppBar();

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('Player Profile'),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
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
