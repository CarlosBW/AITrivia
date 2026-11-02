import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'realtime_invites_screen.dart';
import 'find_opponent_screen.dart';
import 'active_matches_screen.dart';
import 'pvp_season_screen.dart';
import '../../widgets/spotlight_hint.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/league_names.dart';
import '../../services/my_profile_service.dart';
import '../../services/pvp_league_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/hero_card.dart';

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

  // Shared with the rest of the app: one listener on the user doc.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _me =
      MyProfileService.instance.watchMe();

  void _push(Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

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
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _me,
            builder: (context, snap) {
              final data = snap.data?.data() ?? const {};
              final rating = ((data['pvpRating'] ?? 1000) as num).toInt();
              final wins = ((data['wins1v1'] ?? 0) as num).toInt();
              final losses = ((data['losses1v1'] ?? 0) as num).toInt();
              final league = PvpLeagueService.instance.leagueForRating(rating);

              return HeroCard(
                gradientStart: context.appColors.heroGradientStart,
                gradientEnd: context.appColors.heroGradientEnd,
                illustration: 'assets/illustrations/trophy.png',
                badge: league.emoji,
                title: l10n.pvpRankTitle(l10n.leagueName(league.id)),
                subtitle: l10n.pvpRankSubtitle(rating, wins, losses),
                actionLabel: l10n.pvpSeasonAction,
                onTap: () => _push(const PvpSeasonScreen()),
              );
            },
          ),
          const SizedBox(height: 14),
          SpotlightHint(
            id: 'pvp_find_opponent',
            title: l10n.spotlightPvpTitle,
            description: l10n.spotlightPvpBody,
            child: HeroCard(
              gradientStart: context.appColors.brandGradientStart,
              gradientEnd: context.appColors.brandGradientEnd,
              illustration: 'assets/illustrations/pvp.png',
              title: l10n.pvpFindOpponentTitle,
              subtitle: l10n.pvpFindOpponentSubtitle,
              actionLabel: l10n.pvpFindAction,
              onTap: () => _push(const FindOpponentScreen()),
            ),
          ),
          const SizedBox(height: 18),
          StreamBuilder<bool>(
            stream: _pendingTurns,
            builder: (context, snap) {
              final hasPendingTurn = snap.data == true;

              return _PvpCard(
                illustration: 'assets/illustrations/matches.png',
                title: hasPendingTurn
                    ? l10n.pvpActiveMatchesTitleAlert
                    : l10n.pvpActiveMatchesTitle,
                subtitle: hasPendingTurn
                    ? l10n.pvpActiveMatchesSubtitleAlert
                    : l10n.pvpActiveMatchesSubtitle,
                alert: hasPendingTurn,
                onTap: () => _push(const ActiveMatchesScreen()),
              );
            },
          ),
          StreamBuilder<bool>(
            stream: _pendingRealtimeInvites,
            builder: (context, snap) {
              final hasPending = snap.data == true;

              return _PvpCard(
                illustration: 'assets/illustrations/friends.png',
                title: hasPending
                    ? l10n.pvpRealtimeInvitesTitleAlert
                    : l10n.pvpRealtimeInvitesTitle,
                subtitle: hasPending
                    ? l10n.pvpRealtimeInvitesSubtitleAlert
                    : l10n.pvpRealtimeInvitesSubtitle,
                alert: hasPending,
                onTap: () => _push(const RealtimeInvitesScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PvpCard extends StatelessWidget {
  /// An asset under `assets/illustrations/`.
  final String illustration;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool alert;

  const _PvpCard({
    required this.illustration,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.alert = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final danger = context.appColors.danger;
    final radius = BorderRadius.circular(context.radii.md);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: alert ? context.appColors.dangerBg : colorScheme.surface,
        borderRadius: radius,
        boxShadow: context.surfaces.shadowsOr(null),
        border: context.surfaces.borderOr(Border.all(
          color: alert
              ? danger.withValues(alpha: 0.7)
              : colorScheme.outline.withValues(alpha: 0.4),
          width: alert ? 1.6 : 1,
        )),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Image.asset(
                      illustration,
                      width: 56,
                      height: 56,
                      cacheWidth:
                          (56 * MediaQuery.devicePixelRatioOf(context)).round(),
                      filterQuality: FilterQuality.medium,
                    ),
                    if (alert)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          width: 13,
                          height: 13,
                          decoration: BoxDecoration(
                            color: danger,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: context.decor.pageColor,
                              width: 1.6,
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
                        style: context.heading(16, color: colorScheme.onSurface),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: alert
                              ? readableInk(danger, context.appColors.dangerBg)
                              : colorScheme.onSurfaceVariant,
                          fontWeight:
                              alert ? FontWeight.w600 : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  color: alert ? danger : colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
