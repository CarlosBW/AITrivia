import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/notification_service.dart';
import '../social/friends_screen.dart';
import '../versus/async_match_play_screen.dart';
import '../versus/realtime_invites_screen.dart';
import '../versus/match_lobby_screen.dart';
import '../leagues/season_rewards_screen.dart';
import '../achievements/achievements_screen.dart';
import '../versus/match_play_screen.dart';
import '../daily/daily_challenge_screen.dart';
import '../../services/match_service.dart';
import '../../services/realtime_invite_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = NotificationService.instance;
  final _matchService = MatchService();
  final _realtimeInviteService = RealtimeInviteService.instance;
  final Set<String> _decliningIds = {};

  bool _markingAll = false;

  IconData _iconForType(String type) {
    switch (type) {
      case 'friend_request':
        return Icons.person_add;
      case 'match_invite':
        return Icons.sports_esports;
      case 'match_turn':
        return Icons.play_circle;
      case 'match_result':
        return Icons.emoji_events;
      case 'achievement_completed':
        return Icons.emoji_events;
      case 'season_reward':
        return Icons.card_giftcard;
      case 'rematch_request':
        return Icons.replay;
      case 'streak_at_risk':
        return Icons.local_fire_department;
      case 'realtime_invite':
        return Icons.bolt;
      case 'realtime_invite_accepted':
        return Icons.check_circle;
      default:
        return Icons.notifications;
    }
  }

  Color _colorForType(String type, bool read) {
    if (read) return Colors.black54;

    switch (type) {
      case 'match_invite':
        return Colors.deepPurple;
      case 'match_turn':
        return Colors.green;
      case 'match_result':
        return Colors.amber.shade700;
      case 'friend_request':
        return Colors.blue;
      case 'season_reward':
        return Colors.orange;
      case 'achievement_completed':
        return Colors.teal;
      case 'rematch_request':
        return Colors.deepPurple;
      case 'streak_at_risk':
        return Colors.deepOrange;
      default:
        return Colors.deepPurple;
    }
  }

  String _ctaForType(String type) {
    switch (type) {
      case 'match_invite':
        return 'Play now';
      case 'match_turn':
        return 'Continue';
      case 'match_result':
        return 'View result';
      case 'friend_request':
        return 'Review';
      case 'season_reward':
        return 'Claim';
      case 'achievement_completed':
        return 'View';
      case 'rematch_request':
        return 'View';
      case 'streak_at_risk':
        return 'Play now';
      case 'realtime_invite':
        return 'Open';
      case 'realtime_invite_accepted':
        return 'Open lobby';
      default:
        return 'Open';
    }
  }

  Future<void> _markAllAsRead() async {
    if (_markingAll) return;

    setState(() => _markingAll = true);

    try {
      await _service.markAllAsRead();
    } finally {
      if (mounted) {
        setState(() => _markingAll = false);
      }
    }
  }

  Future<void> _declineRealtimeInvite({
    required String notificationId,
    required String inviteId,
  }) async {
    if (inviteId.isEmpty) return;
    if (_decliningIds.contains(notificationId)) return;

    setState(() => _decliningIds.add(notificationId));

    try {
      await _realtimeInviteService.declineInvite(inviteId: inviteId);
      await _markAsRead(notificationId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invitación rechazada')),
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
        setState(() => _decliningIds.remove(notificationId));
      }
    }
  }

  Future<void> _declineAsyncInvite({
    required String notificationId,
    required String matchId,
  }) async {
    if (matchId.isEmpty) return;
    if (_decliningIds.contains(notificationId)) return;

    setState(() => _decliningIds.add(notificationId));

    try {
      await _matchService.declineAsyncMatch(matchId: matchId);
      await _markAsRead(notificationId);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reto rechazado')),
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
        setState(() => _decliningIds.remove(notificationId));
      }
    }
  }

  Future<void> _markAsRead(String notificationId) async {
    await _service.markAsRead(notificationId: notificationId);
  }

  Future<void> _delete(String notificationId) async {
    await _service.deleteNotification(notificationId: notificationId);
  }

  Future<void> _handleNotificationTap({
    required String notificationId,
    required String type,
    required Map<String, dynamic> data,
  }) async {
    await _markAsRead(notificationId);

    if (!mounted) return;

    switch (type) {
      case 'friend_request':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const FriendsScreen(),
          ),
        );
        return;

      case 'match_invite':
      case 'match_turn':
      case 'match_result':
        final matchId = (data['matchId'] ?? '').toString();

        if (matchId.isEmpty) return;

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AsyncMatchPlayScreen(
              asyncMatchId: matchId,
            ),
          ),
        );
        return;

      case 'season_reward':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const SeasonRewardsScreen(),
          ),
        );
        return;

      case 'achievement_completed':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const AchievementsScreen(),
          ),
        );
        return;

      case 'realtime_invite':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const RealtimeInvitesScreen(),
          ),
        );
        return;

      case 'realtime_invite_accepted':
        final matchId = (data['matchId'] ?? '').toString();

        if (matchId.isEmpty) return;

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MatchLobbyScreen(
              matchId: matchId,
            ),
          ),
        );
        return;

      case 'rematch_request':
        final matchId = (data['matchId'] ?? '').toString();

        if (matchId.isEmpty) return;

        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MatchPlayScreen(
              matchId: matchId,
            ),
          ),
        );
        return;

      case 'streak_at_risk':
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DailyChallengeScreen(
              uid: FirebaseAuth.instance.currentUser!.uid,
            ),
          ),
        );
        return;

      default:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          TextButton.icon(
            onPressed: _markingAll ? null : _markAllAsRead,
            icon: _markingAll
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.done_all),
            label: const Text('Read all'),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _service.watchMyNotifications(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error loading notifications:\n${snap.error}',
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
            return const _EmptyNotifications();
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final data = doc.data();

              final type = (data['type'] ?? '').toString();
              final title = (data['title'] ?? 'Notification').toString();
              final body = (data['body'] ?? '').toString();
              final read = data['read'] == true;
              final payload = Map<String, dynamic>.from(
                data['data'] ?? {},
              );

              return Dismissible(
                key: ValueKey(doc.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 18),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.delete,
                    color: Colors.white,
                  ),
                ),
                onDismissed: (_) => _delete(doc.id),
                child: _NotificationTile(
                  icon: _iconForType(type),
                  accentColor: _colorForType(type, read),
                  title: title,
                  body: body,
                  cta: _ctaForType(type),
                  read: read,
                  isPvp: type == 'match_invite' ||
                      type == 'match_turn' ||
                      type == 'match_result',
                  matchData: payload,
                  declining: _decliningIds.contains(doc.id),
                  onDecline: type == 'match_invite'
                      ? () => _declineAsyncInvite(
                            notificationId: doc.id,
                            matchId: (payload['matchId'] ?? '').toString(),
                          )
                      : type == 'realtime_invite'
                          ? () => _declineRealtimeInvite(
                                notificationId: doc.id,
                                inviteId:
                                    (payload['inviteId'] ?? '').toString(),
                              )
                          : null,
                  onTap: () => _handleNotificationTap(
                    notificationId: doc.id,
                    type: type,
                    data: payload,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String body;
  final String cta;
  final bool read;
  final bool isPvp;
  final Map<String, dynamic> matchData;
  final bool declining;
  final VoidCallback? onDecline;
  final VoidCallback? onTap;

  const _NotificationTile({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.body,
    required this.cta,
    required this.read,
    required this.isPvp,
    required this.matchData,
    required this.declining,
    required this.onDecline,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final challengerName = (matchData['challengerName'] ?? '').toString();

    final categoryId = (matchData['categoryId'] ?? '').toString();

    final totalQuestions = (matchData['totalQuestions'] ?? '').toString();

    final timePerQuestionSec =
        (matchData['timePerQuestionSec'] ?? '').toString();

    final showMatchDetails = cta == 'Play now' && categoryId.isNotEmpty;
    final cardColor = read
        ? Colors.black12
        : isPvp
            ? accentColor.withOpacity(0.14)
            : Colors.deepPurple.withOpacity(0.14);

    return Card(
      elevation: 0,
      color: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: read ? Colors.transparent : accentColor,
          width: read ? 0 : 1.5,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: read ? Colors.white.withOpacity(0.8) : accentColor,
          child: Icon(
            icon,
            color: read ? Colors.black87 : Colors.white,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: read ? FontWeight.w600 : FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (body.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(body),
            ],
            if (showMatchDetails) ...[
              const SizedBox(height: 10),
              if (challengerName.isNotEmpty)
                Text(
                  '👤 $challengerName',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 4),
              Text('🎯 Category: $categoryId'),
              Text('❓ Questions: $totalQuestions'),
              Text('⏱ Time: $timePerQuestionSec sec'),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    cta,
                    style: TextStyle(
                      color: read ? Colors.black54 : accentColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (onDecline != null)
                  TextButton.icon(
                    onPressed: declining ? null : onDecline,
                    icon: declining
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.close),
                    label: const Text('Decline'),
                  ),
              ],
            ),
          ],
        ),
        trailing: read
            ? null
            : Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
              ),
      ),
    );
  }
}

class _EmptyNotifications extends StatelessWidget {
  const _EmptyNotifications();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none, size: 48),
            SizedBox(height: 12),
            Text(
              'No notifications yet.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
