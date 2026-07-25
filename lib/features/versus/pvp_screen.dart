import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'realtime_invites_screen.dart';
import 'find_opponent_screen.dart';
import 'active_matches_screen.dart';
import 'pvp_season_screen.dart';
import '../../theme/app_theme.dart';

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
        title: const Text('PvP'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Competitive Hub',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose how you want to compete.',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          StreamBuilder<bool>(
            stream: _hasPendingTurnsStream(uid),
            builder: (context, snap) {
              final hasPendingTurn = snap.data == true;

              return _PvpCard(
                icon: Icons.flash_on_outlined,
                accent: const Color(0xFF85B7EB),
                accentBg: const Color(0xFF042C53),
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
          StreamBuilder<bool>(
            stream: _hasPendingRealtimeInvites(uid),
            builder: (context, snap) {
              final hasPending = snap.data == true;

              return _PvpCard(
                icon: Icons.bolt_outlined,
                accent: const Color(0xFFED93B1),
                accentBg: const Color(0xFF4B1528),
                title: hasPending
                    ? 'Realtime Invites • New!'
                    : 'Realtime Invites',
                subtitle: hasPending
                    ? 'You have live challenges waiting.'
                    : 'Accept or decline live challenges. '
                        'Para retar a un amigo, ve a la pestaña Friends.',
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
          _PvpCard(
            icon: Icons.public_outlined,
            accent: const Color(0xFF5DCAA5),
            accentBg: const Color(0xFF04342C),
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
          _PvpCard(
            icon: Icons.workspace_premium_outlined,
            accent: AppColors.reward,
            accentBg: AppColors.rewardBg,
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
        ],
      ),
    );
  }
}

class _PvpCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final Color accentBg;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool alert;

  const _PvpCard({
    required this.icon,
    required this.accent,
    required this.accentBg,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.alert = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final iconColor = alert ? AppColors.danger : accent;
    final iconBg = alert ? AppColors.dangerBg : accentBg;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(
          color: alert ? AppColors.danger : Colors.transparent,
          width: alert ? 1.5 : 0,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Stack(
          clipBehavior: Clip.none,
          children: [
            CircleAvatar(
              backgroundColor: iconBg,
              child: Icon(icon, color: iconColor),
            ),
            if (alert)
              Positioned(
                right: -1,
                top: -1,
                child: Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: AppColors.danger,
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
            color: alert ? AppColors.danger : null,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            subtitle,
            style: TextStyle(
              color: alert ? AppColors.danger : colorScheme.onSurfaceVariant,
              fontWeight: alert ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
        trailing: Icon(
          Icons.chevron_right,
          color: alert ? AppColors.danger : null,
        ),
        onTap: onTap,
      ),
    );
  }
}
