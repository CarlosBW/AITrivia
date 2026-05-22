import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _service = NotificationService.instance;

  bool _markingAll = false;

  IconData _iconForType(String type) {
    switch (type) {
      case 'friend_request':
        return Icons.person_add;
      case 'match_invite':
        return Icons.sports_esports;
      case 'achievement_completed':
        return Icons.emoji_events;
      case 'season_reward':
        return Icons.card_giftcard;
      case 'daily_available':
        return Icons.calendar_today;
      default:
        return Icons.notifications;
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

  Future<void> _markAsRead(String notificationId) async {
    await _service.markAsRead(notificationId: notificationId);
  }

  Future<void> _delete(String notificationId) async {
    await _service.deleteNotification(notificationId: notificationId);
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
                  title: title,
                  body: body,
                  read: read,
                  onTap: read ? null : () => _markAsRead(doc.id),
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
  final String title;
  final String body;
  final bool read;
  final VoidCallback? onTap;

  const _NotificationTile({
    required this.icon,
    required this.title,
    required this.body,
    required this.read,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: read ? Colors.black12 : Colors.deepPurple.withOpacity(0.14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: read ? Colors.transparent : Colors.deepPurple,
          width: read ? 0 : 1.5,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor:
              read ? Colors.white.withOpacity(0.8) : Colors.deepPurple,
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
        subtitle: body.isEmpty ? null : Text(body),
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