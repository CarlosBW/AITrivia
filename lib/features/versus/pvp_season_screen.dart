import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/pvp_league_service.dart';
import '../../services/pvp_season_service.dart';

class PvpSeasonScreen extends StatefulWidget {
  const PvpSeasonScreen({super.key});

  @override
  State<PvpSeasonScreen> createState() => _PvpSeasonScreenState();
}

class _PvpSeasonScreenState extends State<PvpSeasonScreen>
    with SingleTickerProviderStateMixin {
  final _seasonService = PvpSeasonService.instance;
  final _leagueService = PvpLeagueService.instance;

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: PvpLeagueService.leagues.length + 1,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _avatarEmoji(String avatarId) {
    const avatars = {
      'avatar_1': '🧠',
      'avatar_2': '🚀',
      'avatar_3': '🎮',
      'avatar_4': '🔥',
      'avatar_5': '⭐',
      'avatar_6': '🐱',
      'avatar_7': '🤖',
      'avatar_8': '🏆',
    };

    return avatars[avatarId] ?? '🙂';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    final season = _seasonService.currentSeason();

    return Scaffold(
      appBar: AppBar(
        title: const Text('PvP Season'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            const Tab(text: 'Global'),
            ...PvpLeagueService.leagues.map(
              (league) => Tab(text: '${league.emoji} ${league.name}'),
            ),
          ],
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userRef.snapshots(),
        builder: (context, userSnap) {
          final userData = userSnap.data?.data() ?? {};
          final rating = ((userData['pvpRating'] ?? PvpLeagueService.defaultRating) as num).toInt();
          final league = _leagueService.leagueForRating(rating);
          final reward = _seasonService.rewardForLeague(league);
          final color = Color(league.colorValue);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: color.withOpacity(0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${league.emoji} ${league.name} League',
                        style: TextStyle(
                          color: color,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$rating MMR',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: league.progressFor(rating),
                          minHeight: 10,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('Season: ${season.id}'),
                      Text('Ends in: ${_seasonService.formatTimeLeft(season.timeLeft)}'),
                      const SizedBox(height: 10),
                      Text(
                        'Projected reward: +${reward.coins} coins',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Reward claiming will be connected after the first PvP season closes. This screen already prepares the ranking and reward preview.',
                        style: TextStyle(color: Colors.black54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _LeaderboardList(
                      query: _seasonService.globalLeaderboardQuery(limit: 100),
                      currentUid: uid,
                      avatarBuilder: _avatarEmoji,
                    ),
                    ...PvpLeagueService.leagues.map(
                      (league) => _LeaderboardList(
                        query: _seasonService.leagueLeaderboardQuery(
                          league: league,
                          limit: 100,
                        ),
                        currentUid: uid,
                        avatarBuilder: _avatarEmoji,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LeaderboardList extends StatelessWidget {
  final Query<Map<String, dynamic>> query;
  final String currentUid;
  final String Function(String avatarId) avatarBuilder;

  const _LeaderboardList({
    required this.query,
    required this.currentUid,
    required this.avatarBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: query.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Error loading leaderboard:\n${snap.error}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'No ranked players yet.\nPlay Ranked Match to enter this leaderboard.',
              textAlign: TextAlign.center,
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data();
            final isMe = doc.id == currentUid;
            final rating = ((data['pvpRating'] ?? PvpLeagueService.defaultRating) as num).toInt();
            final username = (data['username'] ?? data['displayName'] ?? 'Player').toString();
            final avatarId = (data['avatarId'] ?? 'avatar_1').toString();
            final wins = ((data['wins1v1'] ?? 0) as num).toInt();
            final losses = ((data['losses1v1'] ?? 0) as num).toInt();
            final draws = ((data['draws1v1'] ?? 0) as num).toInt();
            final matches = wins + losses + draws;

            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isMe ? Colors.deepPurple.withOpacity(0.14) : Colors.black12,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isMe ? Colors.deepPurple : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    child: Text(
                      '#${i + 1}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  CircleAvatar(
                    backgroundColor: Colors.white70,
                    child: Text(avatarBuilder(avatarId)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$matches matches • $wins W / $losses L / $draws D',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '$rating MMR',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
