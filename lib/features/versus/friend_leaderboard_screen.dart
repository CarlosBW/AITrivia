import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class FriendLeaderboardScreen extends StatefulWidget {
  const FriendLeaderboardScreen({super.key});

  @override
  State<FriendLeaderboardScreen> createState() =>
      _FriendLeaderboardScreenState();
}

class _FriendLeaderboardScreenState extends State<FriendLeaderboardScreen> {
  bool _loading = true;
  String? _error;
  List<_PvpFriendRankItem> _items = [];

  static const int _maxFriendsToLoad = 30;

  @override
  void initState() {
    super.initState();
    _loadLeaderboard();
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

  int _safeInt(dynamic value, int fallback) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  Future<void> _loadLeaderboard() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final db = FirebaseFirestore.instance;

      final friendsSnap = await db
          .collection('users')
          .doc(uid)
          .collection('friends')
          .orderBy('createdAt', descending: true)
          .limit(_maxFriendsToLoad)
          .get();

      final friendIds = friendsSnap.docs
          .map((d) => (d.data()['uid'] ?? d.id).toString())
          .where((id) => id.isNotEmpty && id != uid)
          .toList();

      final userRefs = [
        db.collection('users').doc(uid),
        ...friendIds.map((id) => db.collection('users').doc(id)),
      ];

      final userSnaps = await Future.wait(userRefs.map((ref) => ref.get()));

      final items = <_PvpFriendRankItem>[];

      for (final snap in userSnaps) {
        final data = snap.data() ?? {};
        final isMe = snap.id == uid;

        final displayName = (data['displayName'] ??
                data['username'] ??
                (isMe ? 'You' : 'Player'))
            .toString();

        final avatarId = (data['avatarId'] ?? 'avatar_1').toString();

        final rating = _safeInt(data['pvpRating'], 1000);
        final leagueName = (data['pvpLeagueName'] ?? 'Bronze').toString();

        items.add(
          _PvpFriendRankItem(
            uid: snap.id,
            displayName: displayName,
            avatar: _avatarEmoji(avatarId),
            rating: rating,
            leagueName: leagueName,
            isMe: isMe,
          ),
        );
      }

      items.sort((a, b) => b.rating.compareTo(a.rating));

      if (!mounted) return;

      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String _medalForRank(int rank) {
    if (rank == 1) return '🥇';
    if (rank == 2) return '🥈';
    if (rank == 3) return '🥉';
    return '#$rank';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends Leaderboard'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _loadLeaderboard,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadLeaderboard,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 120),
          const Icon(Icons.error_outline, size: 42),
          const SizedBox(height: 12),
          Text(
            'Error loading leaderboard:\n$_error',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loadLeaderboard,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      );
    }

    if (_items.length <= 1) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: const [
          SizedBox(height: 120),
          Icon(Icons.group_outlined, size: 48),
          SizedBox(height: 12),
          Text(
            'Add friends to compare your PvP rating.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _items.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.10),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.25),
              ),
            ),
            child: const Column(
              children: [
                Icon(Icons.leaderboard, size: 42),
                SizedBox(height: 8),
                Text(
                  'PvP Ranking with Friends',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Ranked by current PvP rating.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        final rank = index;
        final item = _items[index - 1];

        return _LeaderboardTile(
          rankLabel: _medalForRank(rank),
          item: item,
        );
      },
    );
  }
}

class _PvpFriendRankItem {
  final String uid;
  final String displayName;
  final String avatar;
  final int rating;
  final String leagueName;
  final bool isMe;

  const _PvpFriendRankItem({
    required this.uid,
    required this.displayName,
    required this.avatar,
    required this.rating,
    required this.leagueName,
    required this.isMe,
  });
}

class _LeaderboardTile extends StatelessWidget {
  final String rankLabel;
  final _PvpFriendRankItem item;

  const _LeaderboardTile({
    required this.rankLabel,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: item.isMe
            ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
            : Colors.black12,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.isMe ? Theme.of(context).colorScheme.primary : Colors.transparent,
          width: item.isMe ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.white.withOpacity(0.85),
            child: Text(
              rankLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          CircleAvatar(
            child: Text(item.avatar),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.displayName}${item.isMe ? ' (You)' : ''}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.leagueName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text(
                'MMR',
                style: TextStyle(fontSize: 12),
              ),
              Text(
                '${item.rating}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}