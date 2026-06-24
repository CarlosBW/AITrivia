import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/daily_challenge_service.dart';
import '../../services/player_level_service.dart';
import '../../services/league_service.dart';
import '../../services/weekly_league_service.dart';
import '../../services/pvp_league_service.dart';
import '../../services/frame_service.dart';
import '../../services/avatar_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with WidgetsBindingObserver {
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

    final newUsername = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        String draftUsername = currentUsername;

        return AlertDialog(
          title: const Text('Edit username'),
          content: TextFormField(
            initialValue: currentUsername,
            autofocus: true,
            maxLength: 20,
            decoration: const InputDecoration(
              hintText: 'Enter username',
              helperText: 'Debe ser único. Usa 3 a 20 caracteres.',
            ),
            onChanged: (value) {
              draftUsername = value.trim();
            },
            onFieldSubmitted: (_) {
              Navigator.pop(dialogContext, draftUsername);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogContext, draftUsername);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (!mounted) return;
    if (newUsername == null) return;

    final username = newUsername.trim();

    if (username.isEmpty) return;
    if (username == currentUsername) return;

    if (username.length < 3 || username.length > 20) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('El username debe tener entre 3 y 20 caracteres.'),
        ),
      );
      return;
    }

    final validUsernameRegex = RegExp(r'^[a-zA-Z0-9_]+$');

    if (!validUsernameRegex.hasMatch(username)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Usa solo letras, números y guion bajo.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      final db = FirebaseFirestore.instance;
      final usernameLower = username.toLowerCase();

      final existingUsersSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('usernameLower', isEqualTo: usernameLower)
          .limit(2)
          .get();

      final usedByAnotherUser = existingUsersSnap.docs.any(
        (doc) => doc.id != uid,
      );

      if (usedByAnotherUser) {
        throw Exception('Username already in use.');
      }

      final newUsernameRef = db.collection('usernames').doc(usernameLower);

      await db.runTransaction((tx) async {
        final currentSnap = await tx.get(userRef);
        final currentData = currentSnap.data() ?? {};

        final oldUsernameLower =
            (currentData['usernameLower'] ?? '').toString().toLowerCase();

        final oldUsernameRef = oldUsernameLower.isEmpty
            ? null
            : db.collection('usernames').doc(oldUsernameLower);

        final newUsernameSnap = await tx.get(newUsernameRef);

        DocumentSnapshot<Map<String, dynamic>>? oldUsernameSnap;

        if (oldUsernameRef != null && oldUsernameLower != usernameLower) {
          oldUsernameSnap = await tx.get(oldUsernameRef);
        }

        if (newUsernameSnap.exists) {
          final ownerUid = (newUsernameSnap.data()?['uid'] ?? '').toString();

          if (ownerUid != uid) {
            throw Exception('Username already in use.');
          }
        }

        tx.set(
          userRef,
          {
            'username': username,
            'usernameLower': usernameLower,
            'displayName': username,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        tx.set(
          newUsernameRef,
          {
            'uid': uid,
            'username': username,
            'usernameLower': usernameLower,
            'updatedAt': FieldValue.serverTimestamp(),
            if (!newUsernameSnap.exists)
              'createdAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );

        if (oldUsernameRef != null &&
            oldUsernameSnap != null &&
            oldUsernameSnap.exists &&
            (oldUsernameSnap.data()?['uid'] ?? '').toString() == uid) {
          tx.delete(oldUsernameRef);
        }
      });

      await _syncLeaderboardProfiles(
        username: username,
      );
      await _loadProfile(showLoading: false);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Perfil actualizado')),
      );
    } catch (e) {
      debugPrint('PROFILE UPDATE ERROR: $e');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().contains('Username already in use')
                ? 'Ese username ya existe.'
                : 'Error actualizando perfil: $e',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _chooseAvatar({
    required BuildContext context,
    required String currentAvatarId,
    required String bestLeagueId,
    required List<dynamic>? storedUnlockedAvatars,
  }) async {
    if (_saving) return;

    final unlockedIds = AvatarService.instance.unlockedAvatarIdsForBestLeague(
      bestLeagueId: bestLeagueId,
      storedUnlockedAvatars: storedUnlockedAvatars,
    );

    final avatars = AvatarService.instance.allAvatars;
    final currentAvatar = AvatarService.instance.avatarById(currentAvatarId);
    final unlockedCount =
        avatars.where((avatar) => unlockedIds.contains(avatar.id)).length;

    final selectedAvatarId = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.78,
          minChildSize: 0.45,
          maxChildSize: 0.92,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                const Text(
                  'Avatar Collection',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Unlocked $unlockedCount / ${avatars.length}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.deepPurple.withOpacity(0.25),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.white.withOpacity(0.75),
                        child: Text(
                          currentAvatar.emoji,
                          style: const TextStyle(fontSize: 30),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Currently equipped',
                              style: TextStyle(
                                color: Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              currentAvatar.name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            _AvatarCategoryBadge(
                              category: currentAvatar.category,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: avatars.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.82,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (context, index) {
                    final avatar = avatars[index];
                    final isSelected = avatar.id == currentAvatarId;
                    final isUnlocked = unlockedIds.contains(avatar.id);

                    return InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: () {
                        if (!isUnlocked) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(avatar.unlockLabel),
                            ),
                          );
                          return;
                        }

                        Navigator.pop(sheetContext, avatar.id);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.deepPurple.withOpacity(0.16)
                              : isUnlocked
                                  ? Colors.black12
                                  : Colors.black.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isSelected
                                ? Colors.deepPurple
                                : isUnlocked
                                    ? Colors.black12
                                    : Colors.black.withOpacity(0.08),
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Stack(
                          children: [
                            Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Opacity(
                                  opacity: isUnlocked ? 1.0 : 0.35,
                                  child: Text(
                                    avatar.emoji,
                                    style: const TextStyle(fontSize: 34),
                                  ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  avatar.name,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: isUnlocked
                                        ? Colors.black87
                                        : Colors.black45,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                if (isUnlocked)
                                  _AvatarCategoryBadge(
                                    category: avatar.category,
                                  )
                                else
                                  Text(
                                    avatar.unlockLabel,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      color: Colors.black45,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                              ],
                            ),
                            if (!isUnlocked)
                              const Positioned(
                                right: 2,
                                top: 2,
                                child: Icon(
                                  Icons.lock,
                                  size: 18,
                                  color: Colors.black54,
                                ),
                              ),
                            if (isSelected)
                              const Positioned(
                                right: 2,
                                top: 2,
                                child: Icon(
                                  Icons.check_circle,
                                  size: 20,
                                  color: Colors.deepPurple,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
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
      final selectedAvatar = AvatarService.instance.avatarById(selectedAvatarId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('${selectedAvatar.emoji} ${selectedAvatar.name} equipped'),
        ),
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
    final pvpRating = ((data['pvpRating'] ?? 1000) as num).toInt();
    final pvpRatingDelta = ((data['pvpRatingDelta'] ?? 0) as num).toInt();
    final pvpLeague = PvpLeagueService.instance.leagueForRating(pvpRating);
    final pvpLeagueProgress = pvpLeague.progressFor(pvpRating);

    final bestLeagueId = (data['bestLeagueId'] ?? pvpLeague.id).toString();

    final equippedFrame = (data['equippedFrame'] ?? bestLeagueId).toString();

    final frame = FrameService.instance.frameById(
      FrameService.instance.safestEquippedFrame(
        equippedFrame: equippedFrame,
        bestLeagueId: bestLeagueId,
      ),
    );

    final storedUnlockedAvatars = data['unlockedAvatars'] as List<dynamic>?;

    final safeAvatarId = AvatarService.instance.safestEquippedAvatar(
      avatarId: (data['avatarId'] ?? 'avatar_1').toString(),
      bestLeagueId: bestLeagueId,
      storedUnlockedAvatars: storedUnlockedAvatars,
    );

    final avatarInfo = AvatarService.instance.avatarById(safeAvatarId);
    final avatar = avatarInfo.emoji;

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
                                currentAvatarId: safeAvatarId,
                                bestLeagueId: bestLeagueId,
                                storedUnlockedAvatars: storedUnlockedAvatars,
                              ),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Color(frame.colorValue),
                            width: 4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Color(frame.colorValue).withOpacity(0.30),
                              blurRadius: 12,
                            ),
                          ],
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
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Color(frame.colorValue).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Color(frame.colorValue).withOpacity(0.40),
                        ),
                      ),
                      child: Text(
                        '${frame.emoji} ${frame.name}',
                        style: TextStyle(
                          color: Color(frame.colorValue),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Weekly Score: $leagueScore',
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Color(pvpLeague.colorValue).withOpacity(0.10),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Color(pvpLeague.colorValue).withOpacity(0.35),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          pvpLeague.emoji,
                          style: const TextStyle(fontSize: 30),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${pvpLeague.name} PvP League',
                                style: TextStyle(
                                  color: Color(pvpLeague.colorValue),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                pvpRatingDelta == 0
                                    ? '$pvpRating MMR'
                                    : '$pvpRating MMR (${pvpRatingDelta > 0 ? '+' : ''}$pvpRatingDelta)',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: pvpLeagueProgress,
                        minHeight: 10,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ranked busca primero rivales de tu liga y amplía el rango si no hay jugadores disponibles.',
                      style: TextStyle(color: Colors.black54, fontSize: 12),
                    ),
                  ],
                ),
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
                icon: Icons.leaderboard,
                label: 'Ranked MMR',
                value: pvpRatingDelta == 0
                    ? '$pvpRating'
                    : '$pvpRating (${pvpRatingDelta > 0 ? '+' : ''}$pvpRatingDelta)',
              ),
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
              const SizedBox(height: 20),
              const Text(
                'Recent PvP matches',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              _RecentMatchHistory(uid: uid),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Text(
                  'Coming soon: achievements, unlockable avatars, weekly events and AI rewards.',
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


class _AvatarCategoryBadge extends StatelessWidget {
  final String category;

  const _AvatarCategoryBadge({required this.category});

  String get _label {
    switch (category) {
      case 'base':
        return 'BASE';
      case 'pvp':
        return 'PVP';
      case 'weekly':
        return 'WEEKLY';
      case 'achievement':
        return 'ACHIEVEMENT';
      case 'ai':
        return 'AI';
      case 'ai_dynamic':
        return 'AI UNIQUE';
      default:
        return category.toUpperCase();
    }
  }

  Color get _color {
    switch (category) {
      case 'base':
        return Colors.blueGrey;
      case 'pvp':
        return Colors.deepPurple;
      case 'weekly':
        return Colors.amber.shade800;
      case 'achievement':
        return Colors.green;
      case 'ai':
      case 'ai_dynamic':
        return Colors.pinkAccent;
      default:
        return Colors.black54;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _color.withOpacity(0.35),
        ),
      ),
      child: Text(
        _label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: _color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _RecentMatchHistory extends StatelessWidget {
  final String uid;

  const _RecentMatchHistory({required this.uid});

  String _resultText(String result) {
    switch (result) {
      case 'victory':
        return 'Victory';
      case 'defeat':
        return 'Defeat';
      case 'draw':
        return 'Draw';
      default:
        return 'Match';
    }
  }

  IconData _resultIcon(String result) {
    switch (result) {
      case 'victory':
        return Icons.emoji_events;
      case 'defeat':
        return Icons.close;
      case 'draw':
        return Icons.handshake;
      default:
        return Icons.sports_esports;
    }
  }

  Color _resultColor(String result) {
    switch (result) {
      case 'victory':
        return Colors.green;
      case 'defeat':
        return Colors.redAccent;
      case 'draw':
        return Colors.blueGrey;
      default:
        return Colors.black54;
    }
  }

  String _deltaText(dynamic value) {
    final delta =
        value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
    if (delta == null) return '';
    if (delta > 0) return '+$delta MMR';
    return '$delta MMR';
  }

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('match_history')
        .orderBy('createdAt', descending: true)
        .limit(10);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Text(
            'Error loading match history:\n${snap.error}',
            textAlign: TextAlign.center,
          );
        }

        if (!snap.hasData) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'No PvP matches yet.',
              textAlign: TextAlign.center,
            ),
          );
        }

        return Column(
          children: docs.map((doc) {
            final data = doc.data();
            final result = (data['result'] ?? 'match').toString();
            final opponent = (data['opponentName'] ?? 'Rival').toString();
            final myScore = ((data['myScore'] ?? 0) as num).toInt();
            final opponentScore = ((data['opponentScore'] ?? 0) as num).toInt();
            final ranked = data['ranked'] == true;
            final deltaText = ranked ? _deltaText(data['ratingDelta']) : '';
            final color = _resultColor(result);

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color.withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: color.withOpacity(0.30),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _resultIcon(result),
                        color: color,
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _resultText(result).toUpperCase(),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      if (deltaText.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            deltaText,
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'vs $opponent',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.70),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'Score',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$myScore - $opponentScore',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.70),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          ranked ? 'Ranked' : 'Casual',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
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
