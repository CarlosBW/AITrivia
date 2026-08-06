import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/friend_service.dart';
import '../../services/presence_service.dart';
import '../../services/daily_challenge_service.dart';
import '../versus/friend_challenge_setup_screen.dart';
import '../../widgets/player_avatar_widget.dart';
import '../../l10n/generated/app_localizations.dart';

enum _RelationStatus { friend, requestSent, requestReceived, none }

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _service = FriendService.instance;
  final _presenceService = PresenceService.instance;
  final _searchCtrl = TextEditingController();

  bool _searching = false;
  bool _actionLoading = false;
  String? _error;
  bool _hasSearched = false;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _searchResults = [];
  Map<String, _RelationStatus> _searchStatus = {};

  // One stream per consumer, held for the life of the screen. Built inside
  // `build()` these were re-subscribed on every rebuild — and this screen
  // rebuilds on every search keystroke, tab switch and action.
  late final _friendsStream = _service.watchFriends();
  late final _outgoingCountStream = _service.watchOutgoingRequests();
  late final _outgoingListStream = _service.watchOutgoingRequests();
  late final _incomingCountStream = _service.watchIncomingRequests();
  late final _incomingListStream = _service.watchIncomingRequests();

  // Presence is per friend, so it can't be a single field — but the stream
  // for a given uid still has to survive rebuilds. Bounded by the friends
  // list (100) plus whoever the current search turned up.
  final Map<String, Stream<DocumentSnapshot<Map<String, dynamic>>>>
      _presenceStreams = {};

  Stream<DocumentSnapshot<Map<String, dynamic>>> _presenceStreamFor(
    String userId,
  ) {
    return _presenceStreams.putIfAbsent(
      userId,
      () => _presenceService.watchUserPresence(userId: userId),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  String _offlineLabel(AppLocalizations l10n, Map<String, dynamic>? presence) {
    final updatedAt = presence?['updatedAt'];

    if (updatedAt is! Timestamp) {
      return l10n.friendsOfflineLabel;
    }

    final diff = DateTime.now().difference(
      updatedAt.toDate(),
    );

    if (diff.inMinutes < 1) {
      return l10n.friendsLastSeenJustNow;
    }

    if (diff.inMinutes < 60) {
      return l10n.friendsLastSeenMinutes(diff.inMinutes);
    }

    if (diff.inHours < 24) {
      return l10n.friendsLastSeenHours(diff.inHours);
    }

    return l10n.friendsOfflineLabel;
  }

  /// Classifies each searched user's relationship to me, reusing the same
  /// three collection reads the old exclude-list approach already made —
  /// no extra Firestore cost, just repurposed to classify instead of hide.
  Future<Map<String, _RelationStatus>> _classifySearchResults(
    List<String> ids,
  ) async {
    final db = FirebaseFirestore.instance;
    final userRef = db.collection('users').doc(_service.uid);

    final friendsSnap = await userRef.collection('friends').get();
    final sentSnap = await userRef
        .collection('sent_friend_requests')
        .where('status', isEqualTo: 'pending')
        .get();
    final incomingSnap = await userRef
        .collection('friend_requests')
        .where('status', isEqualTo: 'pending')
        .get();

    final friendIds = friendsSnap.docs
        .map((d) => (d.data()['uid'] ?? d.id).toString())
        .toSet();
    final sentIds = sentSnap.docs
        .map((d) => (d.data()['targetUid'] ?? d.id).toString())
        .toSet();
    final incomingIds = incomingSnap.docs
        .map((d) => (d.data()['requesterUid'] ?? d.id).toString())
        .toSet();

    return {
      for (final id in ids)
        id: friendIds.contains(id)
            ? _RelationStatus.friend
            : sentIds.contains(id)
                ? _RelationStatus.requestSent
                : incomingIds.contains(id)
                    ? _RelationStatus.requestReceived
                    : _RelationStatus.none,
    };
  }

  Future<void> _search() async {
    if (_searching) return;

    final query = _searchCtrl.text.trim();

    if (query.isEmpty) {
      setState(() {
        _error = AppLocalizations.of(context).friendsEnterUsername;
        _searchResults = [];
        _hasSearched = false;
      });
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
      _searchResults = [];
      _hasSearched = true;
    });

    try {
      final snap = await _service.searchUsersByUsername(query: query);
      final results =
          snap.docs.where((doc) => doc.id != _service.uid).toList();
      final classification =
          await _classifySearchResults(results.map((d) => d.id).toList());

      if (!mounted) return;

      _searchCtrl.clear();
      FocusScope.of(context).unfocus();

      setState(() {
        _searchResults = results;
        _searchStatus = classification;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _searchResults = [];
      });
    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _sendFriendRequest(String targetUid) async {
    if (_actionLoading) return;

    setState(() {
      _actionLoading = true;
      _error = null;
    });

    try {
      await _service.sendFriendRequest(targetUid: targetUid);

      if (!mounted) return;

      setState(() {
        _searchStatus[targetUid] = _RelationStatus.requestSent;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).friendsRequestSent)),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _actionLoading = false);
      }
    }
  }

  Future<void> _runAction(
    Future<void> Function() action, {
    VoidCallback? onSuccess,
  }) async {
    if (_actionLoading) return;

    setState(() {
      _actionLoading = true;
      _error = null;
    });

    try {
      await action();

      if (!mounted) return;

      onSuccess?.call();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).friendsActionCompleted)),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _actionLoading = false);
      }
    }
  }

  void _challengeFriend({
    required String friendUid,
    required String displayName,
    required bool isOnline,
  }) {
    if (_actionLoading) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FriendChallengeSetupScreen(
          friendUid: friendUid,
          friendName: displayName,
          isOnline: isOnline,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.friendsTitle),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(text: l10n.friendsSearchTab),
              Tab(text: l10n.friendsFriendsTab),
              _CountTab(
                label: l10n.friendsSentTab,
                stream: _outgoingCountStream,
              ),
              _CountTab(
                label: l10n.friendsReceivedTab,
                stream: _incomingCountStream,
              ),
            ],
          ),
        ),
        body: Stack(
          children: [
            TabBarView(
              children: [
                _buildSearchTab(l10n),
                _buildFriendsTab(l10n),
                _buildOutgoingTab(l10n),
                _buildIncomingTab(l10n),
              ],
            ),
            if (_actionLoading)
              Container(
                color: Colors.black.withValues(alpha: 0.25),
                child: const Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchTab(AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  labelText: l10n.friendsUsernameLabel,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: _searching ? null : _search,
              child: _searching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.friendsSearchTab),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            style: const TextStyle(color: Colors.red),
          ),
        ],
        if (_hasSearched) ...[
          const SizedBox(height: 18),
          if (_searchResults.isEmpty)
            _EmptyCard(
              icon: Icons.person_search,
              text: l10n.friendsNoPlayersFound,
            )
          else
            ..._searchResults.map((doc) {
              final data = doc.data();
              final username =
                  (data['username'] ?? data['displayName'] ?? 'Player')
                      .toString();
              final status = _searchStatus[doc.id] ?? _RelationStatus.none;

              return _SearchResultTile(
                uid: doc.id,
                player: data,
                username: username,
                status: status,
                presenceStream: _presenceStreamFor(doc.id),
                actionLoading: _actionLoading,
                onAdd: () => _sendFriendRequest(doc.id),
                onAccept: () => _runAction(
                  () => _service.acceptFriendRequest(requesterUid: doc.id),
                  onSuccess: () => setState(
                    () => _searchStatus[doc.id] = _RelationStatus.friend,
                  ),
                ),
                onReject: () => _runAction(
                  () => _service.rejectFriendRequest(requesterUid: doc.id),
                  onSuccess: () => setState(
                    () => _searchStatus[doc.id] = _RelationStatus.none,
                  ),
                ),
                onChallenge: (isOnline) => _challengeFriend(
                  friendUid: doc.id,
                  displayName: username,
                  isOnline: isOnline,
                ),
              );
            }),
        ],
      ],
    );
  }

  Widget _buildFriendsTab(AppLocalizations l10n) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _friendsStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text(
              l10n.friendsErrorLoadingFriends(snap.error.toString()),
              textAlign: TextAlign.center,
            ),
          );
        }

        if (!snap.hasData) {
          return Center(
            child: _LoadingCard(text: l10n.friendsLoadingFriends),
          );
        }

        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return Center(
            child: _EmptyCard(
              icon: Icons.group_outlined,
              text: l10n.friendsNoFriendsYet,
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: docs.map((doc) {
            final data = doc.data();
            final friendUid = (data['uid'] ?? doc.id).toString();
            final displayName =
                (data['displayName'] ?? data['username'] ?? 'Player')
                    .toString();

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: _presenceStreamFor(friendUid),
              builder: (context, presenceSnap) {
                final presenceData = presenceSnap.data?.data();
                final presence =
                    presenceData?['presence'] as Map<String, dynamic>?;
                final online = _presenceService.isProbablyOnline(presence);
                final statusText = _presenceService.presenceLabel(presence);
                final rawStatus = (presence?['status'] ?? '').toString();

                return _UserTile(
                  player: data,
                  title: displayName,
                  subtitle: online ? statusText : _offlineLabel(l10n, presence),
                  statusColor: online
                      ? (rawStatus == 'in_match'
                          ? Colors.orangeAccent
                          : rawStatus == 'searching_match'
                              ? Colors.blueAccent
                              : Colors.greenAccent)
                      : Colors.grey,
                  trailing: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      _DailyScoreBadge(friendUid: friendUid),
                      const SizedBox(height: 4),
                      FilledButton.icon(
                        onPressed: _actionLoading
                            ? null
                            : () => _challengeFriend(
                                  friendUid: friendUid,
                                  displayName: displayName,
                                  isOnline: online,
                                ),
                        icon: Icon(
                          online ? Icons.flash_on : Icons.schedule,
                          size: 18,
                        ),
                        label: Text(online ? l10n.asyncFindPlayersChallengeButton : l10n.friendsAsyncOnly),
                      ),
                    ],
                  ),
                );
              },
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildOutgoingTab(AppLocalizations l10n) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _outgoingListStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text(
              l10n.friendsErrorLoadingSent(snap.error.toString()),
              textAlign: TextAlign.center,
            ),
          );
        }

        if (!snap.hasData) {
          return Center(
            child: _LoadingCard(text: l10n.friendsLoadingSent),
          );
        }

        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return Center(
            child: _EmptyCard(
              icon: Icons.outbox_outlined,
              text: l10n.friendsNoSentRequests,
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: docs.map((doc) {
            final data = doc.data();

            final targetName = (data['targetDisplayName'] ??
                    data['targetUsername'] ??
                    'Player')
                .toString();

            final targetPlayer = {
              'avatarId': data['targetAvatarId'] ?? 'avatar_1',
              'equippedFrame': data['targetEquippedFrame'],
              'bestLeagueId': data['targetBestLeagueId'],
            };

            return _UserTile(
              player: targetPlayer,
              title: targetName,
              subtitle: l10n.friendsPending,
              statusColor: Colors.orange,
              trailing: FilledButton(
                onPressed: null,
                child: Text(l10n.friendsSentStatus),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildIncomingTab(AppLocalizations l10n) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _incomingListStream,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text(
              l10n.friendsErrorLoadingReceived(snap.error.toString()),
              textAlign: TextAlign.center,
            ),
          );
        }

        if (!snap.hasData) {
          return Center(
            child: _LoadingCard(text: l10n.friendsLoadingReceived),
          );
        }

        final docs = snap.data!.docs;

        if (docs.isEmpty) {
          return Center(
            child: _EmptyCard(
              icon: Icons.inbox_outlined,
              text: l10n.friendsNoReceivedRequests,
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: docs.map((doc) {
            final data = doc.data();
            final requesterUid = (data['requesterUid'] ?? doc.id).toString();

            final name = (data['requesterDisplayName'] ??
                    data['requesterUsername'] ??
                    'Player')
                .toString();

            final requesterPlayer = {
              'avatarId': data['requesterAvatarId'] ?? 'avatar_1',
              'equippedFrame': data['requesterEquippedFrame'],
              'bestLeagueId': data['requesterBestLeagueId'],
            };

            return _UserTile(
              player: requesterPlayer,
              title: name,
              subtitle: l10n.friendsWantsToAddYou,
              statusColor: Colors.orange,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: l10n.friendsReject,
                    onPressed: _actionLoading
                        ? null
                        : () => _runAction(
                              () => _service.rejectFriendRequest(
                                requesterUid: requesterUid,
                              ),
                            ),
                    icon: const Icon(Icons.close),
                  ),
                  IconButton(
                    tooltip: l10n.friendsAccept,
                    onPressed: _actionLoading
                        ? null
                        : () => _runAction(
                              () => _service.acceptFriendRequest(
                                requesterUid: requesterUid,
                              ),
                            ),
                    icon: const Icon(Icons.check),
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

/// Tab label with a small pending-count badge, matching the alert-badge
/// pattern already used elsewhere in the app (e.g. PvpScreen's cards).
class _CountTab extends StatelessWidget {
  final String label;
  final Stream<QuerySnapshot<Map<String, dynamic>>> stream;

  const _CountTab({
    required this.label,
    required this.stream,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        final count = snap.data?.docs.length ?? 0;

        return Tab(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Badge(label: Text('$count')),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final String uid;
  final Map<String, dynamic> player;
  final String username;
  final _RelationStatus status;
  final Stream<DocumentSnapshot<Map<String, dynamic>>> presenceStream;
  final bool actionLoading;
  final VoidCallback onAdd;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final void Function(bool isOnline) onChallenge;

  const _SearchResultTile({
    required this.uid,
    required this.player,
    required this.username,
    required this.status,
    required this.presenceStream,
    required this.actionLoading,
    required this.onAdd,
    required this.onAccept,
    required this.onReject,
    required this.onChallenge,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    switch (status) {
      case _RelationStatus.friend:
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: presenceStream,
          builder: (context, presenceSnap) {
            final presenceData = presenceSnap.data?.data();
            final presence =
                presenceData?['presence'] as Map<String, dynamic>?;
            final online = PresenceService.instance.isProbablyOnline(
              presence,
            );

            return _UserTile(
              player: player,
              title: username,
              subtitle: l10n.friendsAlreadyFriend,
              statusColor: Colors.greenAccent,
              trailing: FilledButton.icon(
                onPressed: actionLoading ? null : () => onChallenge(online),
                icon: Icon(
                  online ? Icons.flash_on : Icons.schedule,
                  size: 18,
                ),
                label: Text(online ? l10n.asyncFindPlayersChallengeButton : l10n.friendsAsyncOnly),
              ),
            );
          },
        );

      case _RelationStatus.requestSent:
        return _UserTile(
          player: player,
          title: username,
          subtitle: l10n.friendsRequestSent,
          statusColor: Colors.orange,
          trailing: FilledButton(
            onPressed: null,
            child: Text(l10n.friendsSentStatus),
          ),
        );

      case _RelationStatus.requestReceived:
        return _UserTile(
          player: player,
          title: username,
          subtitle: l10n.friendsWantsToAddYouTile,
          statusColor: Colors.orange,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: l10n.friendsReject,
                onPressed: actionLoading ? null : onReject,
                icon: const Icon(Icons.close),
              ),
              IconButton(
                tooltip: l10n.friendsAccept,
                onPressed: actionLoading ? null : onAccept,
                icon: const Icon(Icons.check),
              ),
            ],
          ),
        );

      case _RelationStatus.none:
        return _UserTile(
          player: player,
          title: username,
          subtitle: l10n.friendsPlayerFound,
          statusColor: Colors.grey,
          trailing: FilledButton.tonalIcon(
            onPressed: actionLoading ? null : onAdd,
            icon: const Icon(Icons.person_add),
            label: Text(l10n.friendsAddButton),
          ),
        );
    }
  }
}

class _UserTile extends StatelessWidget {
  final Map<String, dynamic> player;
  final String title;
  final String subtitle;
  final Widget trailing;
  final Color statusColor;

  const _UserTile({
    required this.player,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.surface,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        leading: PlayerAvatarWidget.fromPlayer(
          player,
          radius: 20,
        ),
        title: Text(
          title,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                subtitle,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        trailing: trailing,
      ),
    );
  }
}

// Gives the Friends tab a passive comparison signal — previously it only
// showed online/offline presence, with no way to see how a friend is
// actually doing. Reuses the same daily_leaderboards/{dateId}/players doc
// daily_leaderboard_screen.dart already reads, so no new backend data.
class _DailyScoreBadge extends StatelessWidget {
  final String friendUid;

  const _DailyScoreBadge({required this.friendUid});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dateId = DailyChallengeService.instance.todayDateId();

    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('daily_leaderboards')
          .doc(dateId)
          .collection('players')
          .doc(friendUid)
          .get(),
      builder: (context, snap) {
        final data = snap.data?.data();
        final score = data == null ? null : ((data['score'] ?? 0) as num).toInt();

        return Text(
          score == null
              ? l10n.friendsNotPlayedToday
              : l10n.friendsTodayScore(score),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: score == null
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : Theme.of(context).colorScheme.primary,
          ),
        );
      },
    );
  }
}

class _LoadingCard extends StatelessWidget {
  final String text;

  const _LoadingCard({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(text),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final IconData icon;
  final String text;

  const _EmptyCard({
    required this.icon,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36),
          const SizedBox(height: 8),
          Text(
            text,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
