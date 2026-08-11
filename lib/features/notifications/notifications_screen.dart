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
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/profile_avatar_button.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = NotificationService.instance;

  // Held so marking notifications read (which rebuilds this screen) doesn't
  // re-subscribe the query.
  late final _notifications = _service.watchMyNotifications();
  final _matchService = MatchService();
  final _realtimeInviteService = RealtimeInviteService.instance;
  final Set<String> _decliningIds = {};

  bool _markingAll = false;

  IconData _iconForType(String type) {
    switch (type) {
      case 'friend_request':
        return Icons.person_add_outlined;
      case 'match_invite':
        return Icons.sports_esports_outlined;
      case 'match_turn':
        return Icons.play_circle_outline;
      case 'match_result':
        return Icons.emoji_events_outlined;
      case 'achievement_completed':
        return Icons.emoji_events_outlined;
      case 'season_reward':
        return Icons.card_giftcard_outlined;
      case 'rematch_request':
        return Icons.replay;
      case 'streak_at_risk':
        return Icons.local_fire_department_outlined;
      case 'realtime_invite':
        return Icons.bolt_outlined;
      case 'realtime_invite_accepted':
        return Icons.check_circle_outline;
      default:
        return Icons.notifications_outlined;
    }
  }

  // Uses the app's own vivid palette (matching CategoryAccent/AppColors
  // elsewhere) instead of plain Material colors, so this list reads as
  // part of the same design system as Home/PvP/Achievements.
  Color _colorForType(String type, bool read) {
    if (read) return Theme.of(context).colorScheme.onSurfaceVariant;

    switch (type) {
      case 'match_invite':
        return Theme.of(context).colorScheme.primary;
      case 'match_turn':
        return context.appColors.success;
      case 'match_result':
        return context.appColors.reward;
      case 'friend_request':
        return const Color(0xFF185FA5);
      case 'season_reward':
        return const Color(0xFFE5622C);
      case 'achievement_completed':
        return const Color(0xFF993556);
      case 'rematch_request':
        return Theme.of(context).colorScheme.primary;
      case 'streak_at_risk':
        return context.appColors.danger;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  String _ctaForType(AppLocalizations l10n, String type) {
    switch (type) {
      case 'match_invite':
        return l10n.navPlayNow;
      case 'match_turn':
        return l10n.notificationsContinue;
      case 'match_result':
        return l10n.notificationsViewResult;
      case 'friend_request':
        return l10n.notificationsReview;
      case 'season_reward':
        return l10n.weeklyLeagueClaim;
      case 'achievement_completed':
        return l10n.notificationsView;
      case 'rematch_request':
        return l10n.notificationsView;
      case 'streak_at_risk':
        return l10n.navPlayNow;
      case 'realtime_invite':
        return l10n.notificationsOpen;
      case 'realtime_invite_accepted':
        return l10n.notificationsOpenLobby;
      default:
        return l10n.notificationsOpen;
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
        SnackBar(content: Text(AppLocalizations.of(context).realtimeInvitesDeclined)),
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
        SnackBar(content: Text(AppLocalizations.of(context).notificationsChallengeDeclined)),
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
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.notificationsTitle),
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
            label: Text(l10n.notificationsReadAll),
          ),
          const ProfileAvatarButton(),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _notifications,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.notificationsErrorLoading(snap.error.toString()),
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
              final title = (data['title'] ?? l10n.notificationsFallbackTitle).toString();
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
                    color: context.appColors.danger,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.delete_outline,
                    color: Colors.white,
                  ),
                ),
                onDismissed: (_) => _delete(doc.id),
                child: _NotificationTile(
                  icon: _iconForType(type),
                  accentColor: _colorForType(type, read),
                  title: title,
                  body: body,
                  type: type,
                  cta: _ctaForType(l10n, type),
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
  final String type;
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
    required this.type,
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
    final l10n = AppLocalizations.of(context);
    final challengerName = (matchData['challengerName'] ?? '').toString();

    final categoryId = (matchData['categoryId'] ?? '').toString();

    final totalQuestions = (matchData['totalQuestions'] ?? '').toString();

    final timePerQuestionSec =
        (matchData['timePerQuestionSec'] ?? '').toString();

    final showMatchDetails =
        (type == 'match_invite' || type == 'streak_at_risk') &&
            categoryId.isNotEmpty;
    final cardColor = read
        ? Theme.of(context).colorScheme.surface
        : isPvp
            ? accentColor.withValues(alpha: 0.14)
            : Theme.of(context).colorScheme.primary.withValues(alpha: 0.14);

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
          backgroundColor: read
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : accentColor,
          child: Icon(
            icon,
            color: read
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : Colors.white,
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
                  l10n.notificationsChallengerPrefix(challengerName),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              const SizedBox(height: 4),
              Text(l10n.notificationsCategoryLine(categoryId)),
              Text(l10n.notificationsQuestionsLine(totalQuestions)),
              Text(l10n.notificationsTimeLine(timePerQuestionSec)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    cta,
                    style: TextStyle(
                      color: read
                          ? Theme.of(context).colorScheme.onSurfaceVariant
                          : accentColor,
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
                    label: Text(l10n.realtimeInvitesDecline),
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
                decoration: BoxDecoration(
                  color: context.appColors.danger,
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.notifications_none, size: 48),
            const SizedBox(height: 12),
            Text(
              AppLocalizations.of(context).notificationsEmptyState,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
