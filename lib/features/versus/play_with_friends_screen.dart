import 'package:flutter/material.dart';

import 'async_inbox_screen.dart';
import 'async_outbox_screen.dart';
import 'challenge_friend_list_screen.dart';

class PlayWithFriendsScreen extends StatelessWidget {
  const PlayWithFriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Play with Friends'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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

  const _MenuCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.black12,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(
          child: Icon(icon),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
