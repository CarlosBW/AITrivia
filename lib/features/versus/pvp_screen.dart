import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'play_with_friends_screen.dart';
import 'find_opponent_screen.dart';
import 'active_matches_screen.dart';
import 'pvp_season_screen.dart';

class PvPScreen extends StatelessWidget {
  const PvPScreen({super.key});

  Stream<bool> _hasPendingTurnsStream(String uid) {
    return FirebaseFirestore.instance
        .collection('async_matches')
        .where('challengedUid', isEqualTo: uid)
        .where('challengedStatus', isEqualTo: 'pending')
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isNotEmpty);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

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

          StreamBuilder<bool>(
            stream: _hasPendingTurnsStream(uid),
            builder: (context, snap) {
              final hasPendingTurn = snap.data == true;

              return _PvpCard(
                icon: Icons.flash_on,
                title: hasPendingTurn
                    ? 'Active Matches • Your Turn!'
                    : 'Active Matches',
                subtitle: hasPendingTurn
                    ? 'You have pending matches waiting for your move.'
                    : 'Pending turns, live games, and recent results.',
                alert: hasPendingTurn,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ActiveMatchesScreen(),
                    ),
                  );
                },
              );
            },
          ),

          _PvpCard(
            icon: Icons.workspace_premium,
            title: 'PvP Season',
            subtitle:
                'View your ranked league, season progress, leaderboard and rewards.',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PvpSeasonScreen(),
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
  final bool alert;

  const _PvpCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.alert = false,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = alert ? Colors.redAccent : Colors.black54;

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
              backgroundColor: alert ? Colors.redAccent.withOpacity(0.18) : null,
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
              color: alert ? accentColor : null,
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