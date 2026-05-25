import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/friend_service.dart';
import '../../services/presence_service.dart';
import 'friend_challenge_setup_screen.dart';

class ChallengeFriendListScreen extends StatelessWidget {
  const ChallengeFriendListScreen({super.key});

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
    final friendService = FriendService.instance;
    final presenceService = PresenceService.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Challenge a Friend'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: friendService.watchFriends(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error loading friends:\n${snap.error}',
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
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'You do not have friends yet.\nAdd friends first from the Friends tab.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();

              final friendUid = (data['uid'] ?? doc.id).toString();
              final displayName =
                  (data['displayName'] ?? data['username'] ?? 'Player')
                      .toString();

              final avatarId = (data['avatarId'] ?? 'avatar_1').toString();

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: presenceService.watchUserPresence(
                  userId: friendUid,
                ),
                builder: (context, presenceSnap) {
                  final presenceData = presenceSnap.data?.data();
                  final presence =
                      presenceData?['presence'] as Map<String, dynamic>?;

                  final online = presenceService.isProbablyOnline(presence);
                  final statusText = presenceService.presenceLabel(presence);

                  final statusColor = online
                      ? (statusText == 'In match'
                          ? Colors.orange
                          : statusText == 'Searching match'
                              ? Colors.blue
                              : Colors.green)
                      : Colors.grey;

                  return Card(
                    elevation: 0,
                    color: Colors.black12,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        child: Text(_avatarEmoji(avatarId)),
                      ),
                      title: Text(
                        displayName,
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
                              online ? statusText : 'Offline',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      trailing: FilledButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => FriendChallengeSetupScreen(
                                friendUid: friendUid,
                                friendName: displayName,
                                isOnline: online,
                              ),
                            ),
                          );
                        },
                        child: const Text('Challenge'),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}