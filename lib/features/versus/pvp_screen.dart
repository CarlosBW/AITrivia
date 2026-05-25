import 'package:flutter/material.dart';

import 'play_with_friends_screen.dart';
import 'find_opponent_screen.dart';
import 'active_matches_screen.dart';

class PvPScreen extends StatelessWidget {
  const PvPScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PvP'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Competitive Hub',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Choose how you want to compete.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 18),
          _PvpCard(
            icon: Icons.flash_on,
            title: 'Active Matches',
            subtitle: 'Pending turns, live games, and recent results.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ActiveMatchesScreen(),
                ),
              );
            },
          ),
          _PvpCard(
            icon: Icons.group,
            title: 'Play with Friends',
            subtitle: 'Challenge your friends in real-time or async mode.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PlayWithFriendsScreen(),
                ),
              );
            },
          ),
          _PvpCard(
            icon: Icons.public,
            title: 'Find Opponent',
            subtitle: 'Play against any available challenger.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const FindOpponentScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PvpCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PvpCard({
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
