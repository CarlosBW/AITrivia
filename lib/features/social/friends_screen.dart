import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/friend_service.dart';
import '../../services/match_service.dart';
import '../../services/presence_service.dart';
import '../versus/async_match_play_screen.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _service = FriendService.instance;
  final _matchService = MatchService();
  final _presenceService = PresenceService.instance;
  final _searchCtrl = TextEditingController();

  bool _searching = false;
  bool _actionLoading = false;
  String? _error;

  String _activeSearchQuery = '';
  bool _hasSearched = false;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _searchResults = [];

  @override
  void dispose() {
    _searchCtrl.dispose();
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

  bool _matchesActiveSearch(String value) {
    if (_activeSearchQuery.isEmpty) return true;
    return value.toLowerCase().contains(_activeSearchQuery);
  }

  Future<Set<String>> _blockedSearchUserIds() async {
    final db = FirebaseFirestore.instance;
    final uid = _service.uid;
    final userRef = db.collection('users').doc(uid);

    final friendsSnap = await userRef.collection('friends').get();

    final sentSnap = await userRef
        .collection('sent_friend_requests')
        .where('status', isEqualTo: 'pending')
        .get();

    final incomingSnap = await userRef
        .collection('friend_requests')
        .where('status', isEqualTo: 'pending')
        .get();

    final ids = <String>{uid};

    for (final doc in friendsSnap.docs) {
      final data = doc.data();
      ids.add((data['uid'] ?? doc.id).toString());
    }

    for (final doc in sentSnap.docs) {
      final data = doc.data();
      ids.add((data['targetUid'] ?? doc.id).toString());
    }

    for (final doc in incomingSnap.docs) {
      final data = doc.data();
      ids.add((data['requesterUid'] ?? doc.id).toString());
    }

    return ids;
  }

  Future<void> _search() async {
    if (_searching) return;

    final query = _searchCtrl.text.trim();
    final normalizedQuery = query.toLowerCase();

    if (query.isEmpty) {
      setState(() {
        _error = 'Escribe un username para buscar.';
        _searchResults = [];
        _activeSearchQuery = '';
        _hasSearched = false;
      });
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
      _searchResults = [];
      _activeSearchQuery = normalizedQuery;
      _hasSearched = true;
    });

    try {
      final blockedIds = await _blockedSearchUserIds();
      final snap = await _service.searchUsersByUsername(query: query);

      if (!mounted) return;

      _searchCtrl.clear();
      FocusScope.of(context).unfocus();

      setState(() {
        _searchResults = snap.docs
            .where((doc) => !blockedIds.contains(doc.id))
            .toList();
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
        _searchResults.removeWhere((doc) => doc.id == targetUid);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Solicitud enviada')),
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

  Future<void> _runAction(Future<void> Function() action) async {
    if (_actionLoading) return;

    setState(() {
      _actionLoading = true;
      _error = null;
    });

    try {
      await action();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Acción completada')),
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

  Future<void> _challengeFriend({
    required String friendUid,
    required String displayName,
  }) async {
    if (_actionLoading) return;

    setState(() {
      _actionLoading = true;
      _error = null;
    });

    try {
      final myName = await _matchService.getMyDisplayNameFallback('Player');

      final matchId = await _matchService.createAsyncFixedMatch(
        challengedUid: friendUid,
        categoryId: 'random',
        difficulty: 1,
        totalQuestions: 10,
        timePerQuestionSec: 10,
        winReward: 2,
        challengerDisplayName: myName,
        challengedDisplayName: displayName,
      );

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => AsyncMatchPlayScreen(asyncMatchId: matchId),
        ),
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

  @override
  Widget build(BuildContext context) {
    final filterText = _activeSearchQuery.isEmpty
        ? null
        : 'Filtrando por "$_activeSearchQuery"';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Friends'),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Buscar jugador',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      textInputAction: TextInputAction.search,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
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
                        : const Text('Buscar'),
                  ),
                ],
              ),

              if (filterText != null) ...[
                const SizedBox(height: 10),
                Text(
                  filterText,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ],

              if (_hasSearched) ...[
                const SizedBox(height: 14),
                const Text(
                  'Resultados nuevos',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                if (_searchResults.isEmpty)
                  const _EmptyCard(
                    icon: Icons.person_search,
                    text:
                        'No hay nuevos jugadores para agregar con esa búsqueda.',
                  )
                else
                  ..._searchResults.map((doc) {
                    final data = doc.data();
                    final username =
                        (data['username'] ?? data['displayName'] ?? 'Player')
                            .toString();
                    final avatarId =
                        (data['avatarId'] ?? 'avatar_1').toString();

                    return _UserTile(
                      avatar: _avatarEmoji(avatarId),
                      title: username,
                      subtitle: 'Jugador encontrado',
                      statusColor: Colors.grey,
                      trailing: FilledButton.tonalIcon(
                        onPressed: _actionLoading
                            ? null
                            : () => _sendFriendRequest(doc.id),
                        icon: const Icon(Icons.person_add),
                        label: const Text('Agregar'),
                      ),
                    );
                  }),
              ],

              const SizedBox(height: 24),
              const Text(
                'Solicitudes enviadas',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),

              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _service.watchOutgoingRequests(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Text(
                      'Error cargando solicitudes enviadas:\n${snap.error}',
                      textAlign: TextAlign.center,
                    );
                  }

                  if (!snap.hasData) {
                    return const _LoadingCard(
                      text: 'Cargando solicitudes enviadas...',
                    );
                  }

                  final docs = snap.data!.docs.where((doc) {
                    final data = doc.data();

                    final targetName = (data['targetDisplayName'] ??
                            data['targetUsername'] ??
                            'Player')
                        .toString();

                    return _matchesActiveSearch(targetName);
                  }).toList();

                  if (docs.isEmpty) {
                    return _EmptyCard(
                      icon: Icons.outbox_outlined,
                      text: _activeSearchQuery.isEmpty
                          ? 'No tienes solicitudes pendientes por responder.'
                          : 'No hay solicitudes enviadas que coincidan.',
                    );
                  }

                  return Column(
                    children: docs.map((doc) {
                      final data = doc.data();

                      final targetName = (data['targetDisplayName'] ??
                              data['targetUsername'] ??
                              'Player')
                          .toString();

                      final avatarId =
                          (data['targetAvatarId'] ?? 'avatar_1').toString();

                      return _UserTile(
                        avatar: _avatarEmoji(avatarId),
                        title: targetName,
                        subtitle: 'Pendiente',
                        statusColor: Colors.orange,
                        trailing: const FilledButton(
                          onPressed: null,
                          child: Text('Enviado'),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),

              const SizedBox(height: 24),
              const Text(
                'Solicitudes recibidas',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _service.watchIncomingRequests(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Text(
                      'Error cargando solicitudes:\n${snap.error}',
                      textAlign: TextAlign.center,
                    );
                  }

                  if (!snap.hasData) {
                    return const _LoadingCard(text: 'Cargando solicitudes...');
                  }

                  final docs = snap.data!.docs.where((doc) {
                    final data = doc.data();

                    final name = (data['requesterDisplayName'] ??
                            data['requesterUsername'] ??
                            'Player')
                        .toString();

                    return _matchesActiveSearch(name);
                  }).toList();

                  if (docs.isEmpty) {
                    return _EmptyCard(
                      icon: Icons.inbox_outlined,
                      text: _activeSearchQuery.isEmpty
                          ? 'No tienes solicitudes pendientes.'
                          : 'No hay solicitudes recibidas que coincidan.',
                    );
                  }

                  return Column(
                    children: docs.map((doc) {
                      final data = doc.data();

                      final requesterUid =
                          (data['requesterUid'] ?? doc.id).toString();

                      final name = (data['requesterDisplayName'] ??
                              data['requesterUsername'] ??
                              'Player')
                          .toString();

                      final avatarId =
                          (data['requesterAvatarId'] ?? 'avatar_1').toString();

                      return _UserTile(
                        avatar: _avatarEmoji(avatarId),
                        title: name,
                        subtitle: 'Quiere agregarte',
                        statusColor: Colors.orange,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Rechazar',
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
                              tooltip: 'Aceptar',
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
              ),

              const SizedBox(height: 24),
              const Text(
                'Tus amigos',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _service.watchFriends(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Text(
                      'Error cargando amigos:\n${snap.error}',
                      textAlign: TextAlign.center,
                    );
                  }

                  if (!snap.hasData) {
                    return const _LoadingCard(text: 'Cargando amigos...');
                  }

                  final docs = snap.data!.docs.where((doc) {
                    final data = doc.data();

                    final displayName =
                        (data['displayName'] ?? data['username'] ?? 'Player')
                            .toString();

                    return _matchesActiveSearch(displayName);
                  }).toList();

                  if (docs.isEmpty) {
                    return _EmptyCard(
                      icon: Icons.group_outlined,
                      text: _activeSearchQuery.isEmpty
                          ? 'Todavía no tienes amigos agregados.'
                          : 'No hay amigos que coincidan.',
                    );
                  }

                  return Column(
                    children: docs.map((doc) {
                      final data = doc.data();

                      final friendUid = (data['uid'] ?? doc.id).toString();

                      final displayName =
                          (data['displayName'] ?? data['username'] ?? 'Player')
                              .toString();

                      final avatarId =
                          (data['avatarId'] ?? 'avatar_1').toString();

                      return StreamBuilder<
                          DocumentSnapshot<Map<String, dynamic>>>(
                        stream: _presenceService.watchUserPresence(
                          userId: friendUid,
                        ),
                        builder: (context, presenceSnap) {
                          final presenceData = presenceSnap.data?.data();

                          final presence = presenceData?['presence']
                              as Map<String, dynamic>?;

                          final online = _presenceService.isProbablyOnline(
                            presence,
                          );

                          final statusText = _presenceService.presenceLabel(
                            presence,
                          );

                          return _UserTile(
                            avatar: _avatarEmoji(avatarId),
                            title: displayName,
                            subtitle: online ? statusText : 'Offline',
                            statusColor: online
                                ? (statusText == 'In match'
                                    ? Colors.orange
                                    : statusText == 'Searching match'
                                        ? Colors.blue
                                        : Colors.green)
                                : Colors.grey,
                            trailing: FilledButton(
                              onPressed: _actionLoading
                                  ? null
                                  : () => _challengeFriend(
                                        friendUid: friendUid,
                                        displayName: displayName,
                                      ),
                              child: const Text('Retar'),
                            ),
                          );
                        },
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
          if (_actionLoading)
            Container(
              color: Colors.black.withOpacity(0.25),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  final String avatar;
  final String title;
  final String subtitle;
  final Widget trailing;
  final Color statusColor;

  const _UserTile({
    required this.avatar,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.statusColor,
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
        leading: CircleAvatar(
          child: Text(avatar),
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
        color: Colors.black12,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
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