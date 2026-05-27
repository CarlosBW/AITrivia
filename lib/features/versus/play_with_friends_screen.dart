import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'async_inbox_screen.dart';
import 'async_outbox_screen.dart';
import 'challenge_friend_list_screen.dart';
import 'realtime_invites_screen.dart';

class PlayWithFriendsScreen extends StatelessWidget {
  const PlayWithFriendsScreen({super.key});

  Stream<bool> _hasPendingRealtimeInvites(String uid) {
    return FirebaseFirestore.instance
        .collection('realtime_invites')
        .where('toUid', isEqualTo: uid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Play with Friends'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StreamBuilder<bool>(
            stream: _hasPendingRealtimeInvites(uid),
            builder: (context, snap) {
              final hasPending = snap.data == true;

              return _MenuCard(
                icon: Icons.bolt,
                title: hasPending
                    ? 'Realtime Invites • New!'
                    : 'Realtime Invites',
                subtitle: hasPending
                    ? 'You have live challenges waiting.'
                    : 'Accept or decline live challenges from friends.',
                alert: hasPending,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const RealtimeInvitesScreen(),
                    ),
                  );
                },
              );
            },
          ),
          _MenuCard(
            icon: Icons.inbox,
            title: 'Retos recibidos',
            subtitle: 'Juega los retos que tus amigos te enviaron.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AsyncInboxScreen(),
                ),
              );
            },
          ),
          _MenuCard(
            icon: Icons.outbox,
            title: 'Retos enviados',
            subtitle: 'Revisa retos pendientes y resultados.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const AsyncOutboxScreen(),
                ),
              );
            },
          ),
          _MenuCard(
            icon: Icons.person_add_alt_1,
            title: 'Retar a un amigo',
            subtitle: 'Elige un amigo y decide si será realtime o async.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ChallengeFriendListScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool alert;

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.alert = false,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: alert ? Colors.redAccent.withOpacity(0.12) : Colors.black12,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: alert ? Colors.redAccent : Colors.transparent,
          width: alert ? 1.5 : 0,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              backgroundColor:
                  alert ? Colors.redAccent.withOpacity(0.18) : null,
              child: Icon(
                icon,
                color: alert ? Colors.redAccent : null,
              ),
            ),
            if (alert)
              Positioned(
                right: -1,
                top: -1,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      width: 1.4,
                    ),
                  ),
                ),
              ),
          ],
        ),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: alert ? Colors.redAccent : null,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: TextStyle(
              color: alert ? Colors.redAccent : null,
              fontWeight: alert ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: alert ? Colors.redAccent : null,
        ),
        onTap: onTap,
      ),
    );
  }
}