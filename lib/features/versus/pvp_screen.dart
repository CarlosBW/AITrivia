import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'realtime_invites_screen.dart';
import 'find_opponent_screen.dart';
import 'active_matches_screen.dart';
import 'pvp_season_screen.dart';
import '../../widgets/spotlight_hint.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';

class PvPScreen extends StatefulWidget {
  const PvPScreen({super.key});

  @override
  State<PvPScreen> createState() => _PvPScreenState();
}

// Stateful only to hold the two badge streams. Built inside `build()` they
// were torn down and re-subscribed on every rebuild of this screen, and a
// re-subscription re-reads the query.
class _PvPScreenState extends State<PvPScreen> {
  final String uid = FirebaseAuth.instance.currentUser!.uid;

  late final Stream<bool> _pendingTurns = FirebaseFirestore.instance
      .collection('async_matches')
      .where('challengedUid', isEqualTo: uid)
      .where('challengedStatus', isEqualTo: 'pending')
      .limit(1)
      .snapshots()
      .map((snap) => snap.docs.isNotEmpty);

  late final Stream<bool> _pendingRealtimeInvites = FirebaseFirestore.instance
      .collection('realtime_invites')
      .where('toUid', isEqualTo: uid)
      .where('status', isEqualTo: 'pending')
      .limit(1)
      .snapshots()
      .map((snap) => snap.docs.isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.pvpHubTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            l10n.pvpHubHeading,
            style: GoogleFonts.baloo2(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.pvpHubSubheading,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 18),
          StreamBuilder<bool>(
            stream: _pendingTurns,
            builder: (context, snap) {
              final hasPendingTurn = snap.data == true;

              return _PvpCard(
                icon: Icons.flash_on_outlined,
                accent: const Color(0xFF6C4FF2),
                accentBg: const Color(0xFFEEEDFE),
                title: hasPendingTurn
                    ? l10n.pvpActiveMatchesTitleAlert
                    : l10n.pvpActiveMatchesTitle,
                subtitle: hasPendingTurn
                    ? l10n.pvpActiveMatchesSubtitleAlert
                    : l10n.pvpActiveMatchesSubtitle,
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
            stream: _pendingRealtimeInvites,
            builder: (context, snap) {
              final hasPending = snap.data == true;

              return _PvpCard(
                icon: Icons.flare_outlined,
                accent: const Color(0xFFFF6B5B),
                accentBg: const Color(0xFFFFF0EE),
                title: hasPending
                    ? l10n.pvpRealtimeInvitesTitleAlert
                    : l10n.pvpRealtimeInvitesTitle,
                subtitle: hasPending
                    ? l10n.pvpRealtimeInvitesSubtitleAlert
                    : l10n.pvpRealtimeInvitesSubtitle,
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
          SpotlightHint(
            id: 'pvp_find_opponent',
            title: l10n.spotlightPvpTitle,
            description: l10n.spotlightPvpBody,
            child: _PvpCard(
              icon: Icons.travel_explore_outlined,
              accent: const Color(0xFFE5A400),
              accentBg: const Color(0xFFFFF6DE),
              title: l10n.pvpFindOpponentTitle,
              subtitle: l10n.pvpFindOpponentSubtitle,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const FindOpponentScreen(),
                  ),
                );
              },
            ),
          ),
          _PvpCard(
            icon: Icons.workspace_premium_outlined,
            accent: const Color(0xFFE5622C),
            accentBg: const Color(0xFFFFE8D6),
            title: l10n.pvpSeasonTitle,
            subtitle: l10n.pvpSeasonSubtitle,
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
    final color = alert ? AppColors.danger : accent;
    final bg = alert ? AppColors.dangerBg : accentBg;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: color.withValues(alpha: alert ? 0.7 : 0.35),
          width: alert ? 1.6 : 1.2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      backgroundColor: color,
                      child: Icon(icon, color: Colors.white),
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
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.baloo2(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: alert ? color : colorScheme.onSurfaceVariant,
                          fontWeight:
                              alert ? FontWeight.w600 : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
