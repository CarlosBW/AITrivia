import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/achievement_service.dart';
import '../../widgets/spotlight_hint.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';

class AchievementsScreen extends StatefulWidget {
  const AchievementsScreen({super.key});

  @override
  State<AchievementsScreen> createState() => _AchievementsScreenState();
}

class _AchievementsScreenState extends State<AchievementsScreen> {
  final _service = AchievementService.instance;

  bool _claiming = false;

  late final String uid;

  // Held so claiming a reward (which rebuilds this screen) doesn't
  // re-subscribe the query.
  late final _achievements = _service.watchUserAchievements(uid: uid);

  @override
  void initState() {
    super.initState();
    uid = FirebaseAuth.instance.currentUser!.uid;
  }

  Future<void> _claim(String achievementId) async {
    if (_claiming) return;

    setState(() => _claiming = true);

    try {
      await _service.claimAchievement(
        uid: uid,
        achievementId: achievementId,
      );

      if (!mounted) return;

      final achievement =
          _service.getAchievementById(achievementId);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context).achievementsRewardClaimed(
              achievement?.rewardCoins ?? 0,
              achievement?.rewardXp ?? 0,
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.toString().replaceFirst('Exception: ', ''),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _claiming = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final achievements = AchievementService.achievementsFor(l10n);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.achievementsTitle),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _achievements,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.achievementsErrorLoading(snap.error.toString()),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final docs = snap.data!.docs;

          final progressMap = {
            for (final d in docs) d.id: d.data(),
          };

          final completedCount = achievements.where((a) {
            final data = progressMap[a.id];
            return data?['completed'] == true;
          }).length;

          return Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    Text(
                      l10n.achievementsProgressTitle,
                      style: GoogleFonts.baloo2(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      l10n.achievementsCompletedCount(completedCount, achievements.length),
                      style: GoogleFonts.baloo2(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: LinearProgressIndicator(
                        value: achievements.isEmpty
                            ? 0
                            : completedCount / achievements.length,
                        minHeight: 12,
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  itemCount: achievements.length,
                  itemBuilder: (context, i) {
                    final achievement = achievements[i];

                    final data =
                        progressMap[achievement.id] ?? {};

                    final progress =
                        ((data['progress'] ?? 0) as num).toInt();

                    final completed =
                        data['completed'] == true;

                    final claimed =
                        data['claimed'] == true;

                    final progressValue =
                        achievement.target == 0
                            ? 0.0
                            : (progress / achievement.target)
                                .clamp(0.0, 1.0);

                    final card = _AchievementCard(
                      achievement: achievement,
                      progress: progress,
                      completed: completed,
                      claimed: claimed,
                      progressValue: progressValue,
                      claiming: _claiming,
                      onClaim: completed && !claimed
                          ? () => _claim(achievement.id)
                          : null,
                    );

                    if (i != 0) return card;

                    final l10n = AppLocalizations.of(context);
                    return SpotlightHint(
                      id: 'achievements_first_card',
                      title: l10n.spotlightAchievementsTitle,
                      description: l10n.spotlightAchievementsBody,
                      child: card,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  final AchievementInfo achievement;
  final int progress;
  final bool completed;
  final bool claimed;
  final double progressValue;
  final bool claiming;
  final VoidCallback? onClaim;

  const _AchievementCard({
    required this.achievement,
    required this.progress,
    required this.completed,
    required this.claimed,
    required this.progressValue,
    required this.claiming,
    required this.onClaim,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final Color accentColor;
    final Color accentBg;

    if (claimed) {
      accentColor = AppColors.success;
      accentBg = AppColors.successBg;
    } else if (completed) {
      accentColor = AppColors.reward;
      accentBg = AppColors.rewardBg;
    } else {
      accentColor = Theme.of(context).colorScheme.primary;
      accentBg = Theme.of(context).colorScheme.surfaceContainerHighest;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accentBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accentColor.withValues(alpha: completed || claimed ? 1 : 0.25),
          width: 2,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  achievement.icon,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      achievement.title,
                      style: GoogleFonts.baloo2(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      achievement.description,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: Text(
                  '$progress / ${achievement.target}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.reward.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  l10n.achievementsCoinsPill(achievement.rewardCoins),
                  style: GoogleFonts.baloo2(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: Color.lerp(AppColors.reward, Colors.black, 0.35),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progressValue,
              minHeight: 10,
            ),
          ),

          const SizedBox(height: 14),

          if (claimed)
            _StatusChip(
              text: l10n.achievementsClaimed,
              color: AppColors.success,
            )
          else if (completed)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: claiming ? null : onClaim,
                icon: const Icon(Icons.card_giftcard_outlined),
                label: Text(l10n.achievementsClaimReward),
              ),
            )
          else
            _StatusChip(
              text: l10n.achievementsInProgress,
              color: AppColors.reward,
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusChip({
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}