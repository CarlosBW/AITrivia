import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/weekly_topic_service.dart';
import '../../services/avatar_service.dart';
import '../../services/life_service.dart';
import '../../widgets/no_lives_dialog.dart';
import 'weekly_topic_play_screen.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';

class WeeklyTopicScreen extends StatefulWidget {
  const WeeklyTopicScreen({super.key});

  @override
  State<WeeklyTopicScreen> createState() => _WeeklyTopicScreenState();
}

class _WeeklyTopicScreenState extends State<WeeklyTopicScreen> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;

  bool _claimingCoins = false;
  bool _claimingCompletion = false;
  bool _isNavigating = false;

  Future<bool> _ensureHasLives() async {
    await LifeService.instance.ensureUserLifeDoc(_uid);
    final lifeState = await LifeService.instance.refreshLives(_uid);

    final lifeUnits = (lifeState['lifeUnits'] ?? 0) as int;
    final maxLifeUnits = (lifeState['maxLifeUnits'] ?? 10) as int;
    final secondsToNextHalfLife = lifeState['secondsToNextHalfLife'] as int?;

    if (lifeUnits < 2) {
      if (!mounted) return false;

      final nextHalfLifeText = secondsToNextHalfLife == null
          ? '--:--'
          : '${(secondsToNextHalfLife ~/ 60).toString().padLeft(2, '0')}:'
              '${(secondsToNextHalfLife % 60).toString().padLeft(2, '0')}';

      await showDialog<bool>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) => NoLivesDialog(
          currentLivesText:
              '${LifeService.instance.formatLives(lifeUnits)} / '
              '${LifeService.instance.formatLives(maxLifeUnits)}',
          nextHalfLifeText: nextHalfLifeText,
          nextFullLifeText: '--:--',
        ),
      );

      return false;
    }

    return true;
  }

  Future<void> _playRound({
    required String categoryId,
    required String categoryName,
    required String weekId,
  }) async {
    if (_isNavigating) return;

    setState(() => _isNavigating = true);

    try {
      final canPlay = await _ensureHasLives();
      if (!canPlay) return;

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WeeklyTopicPlayScreen(
            categoryId: categoryId,
            categoryName: categoryName,
            weekId: weekId,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isNavigating = false);
    }
  }

  Future<void> _claimCoinReward({
    required String weekId,
    required int rewardCoins,
  }) async {
    if (_claimingCoins) return;

    setState(() => _claimingCoins = true);

    try {
      final claimed = await WeeklyTopicService.instance.claimCoinReward(
        uid: _uid,
        weekId: weekId,
        rewardCoins: rewardCoins,
      );

      if (!mounted) return;

      final l10n = AppLocalizations.of(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            claimed
                ? l10n.weeklyTopicCoinsClaimed(rewardCoins)
                : l10n.weeklyTopicRewardUnavailable,
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
        setState(() => _claimingCoins = false);
      }
    }
  }

  Future<void> _claimCompletionReward({
    required String weekId,
    required String rewardAvatarId,
  }) async {
    if (_claimingCompletion) return;

    if (rewardAvatarId.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).weeklyTopicNoExclusiveReward),
        ),
      );
      return;
    }

    setState(() => _claimingCompletion = true);

    try {
      final claimed = await WeeklyTopicService.instance.claimCompletionReward(
        uid: _uid,
        weekId: weekId,
        rewardAvatarId: rewardAvatarId,
      );

      final avatar = AvatarService.instance.avatarById(rewardAvatarId);

      if (!mounted) return;

      final l10n = AppLocalizations.of(context);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            claimed
                ? l10n.weeklyTopicAvatarUnlocked(avatar.emoji, avatar.name)
                : l10n.weeklyTopicRewardUnavailable,
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
        setState(() => _claimingCompletion = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.weeklyTopicScreenTitle),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: WeeklyTopicService.instance.watchCurrentTopic(),
        builder: (context, topicSnap) {
          if (topicSnap.hasError) {
            return Center(child: Text(topicSnap.error.toString()));
          }

          if (!topicSnap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final topicData = topicSnap.data!.data();

          if (topicData == null || topicData['active'] != true) {
            return Center(
              child: Text(l10n.homeWeeklyTopicNoneAvailable),
            );
          }

          final weekId = (topicData['weekId'] ?? '').toString();
          final title = (topicData['title'] ?? 'Weekly Topic').toString();
          final description = (topicData['description'] ?? '').toString();
          final rewardCoins = ((topicData['rewardCoins'] ?? 0) as num).toInt();
          final rewardAvatarId =
              (topicData['rewardAvatarId'] ?? '').toString();
          final rewardAvatar =
              AvatarService.instance.avatarById(rewardAvatarId);

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: WeeklyTopicService.instance.watchMyParticipation(
              uid: _uid,
              weekId: weekId,
            ),
            builder: (context, participationSnap) {
              final participation = participationSnap.data?.data();

              final correctAnswers =
                  ((participation?['correctAnswers'] ?? 0) as num).toInt();

              final coinRewardClaimed =
                  participation?['coinRewardClaimed'] == true;

              final completionRewardClaimed =
                  participation?['completionRewardClaimed'] == true;

              final canClaimCoins =
                  WeeklyTopicService.instance.canClaimCoinReward(participation);

              final canClaimCompletion = WeeklyTopicService.instance
                  .canClaimCompletionReward(participation);

              final progress = (correctAnswers /
                      WeeklyTopicService.completionRewardThreshold)
                  .clamp(0.0, 1.0);

              return Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.rewardBg,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: AppColors.reward.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.star_border, color: AppColors.reward),
                                const SizedBox(width: 8),
                                Text(
                                  l10n.weeklyTopicFeaturedBadge,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              title,
                              style: GoogleFonts.baloo2(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(description),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.weeklyTopicProgressTitle,
                              style: GoogleFonts.baloo2(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            LinearProgressIndicator(value: progress),
                            const SizedBox(height: 10),
                            Text(
                              l10n.weeklyTopicCorrectAnswersProgress(
                                correctAnswers,
                                WeeklyTopicService.completionRewardThreshold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.weeklyTopicRewardsTitle,
                              style: GoogleFonts.baloo2(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              l10n.weeklyTopicCoinRewardDescription(
                                WeeklyTopicService.coinRewardThreshold,
                                rewardCoins,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: canClaimCoins && !_claimingCoins
                                    ? () => _claimCoinReward(
                                          weekId: weekId,
                                          rewardCoins: rewardCoins,
                                        )
                                    : null,
                                icon: const Icon(Icons.monetization_on_outlined),
                                label: Text(
                                  coinRewardClaimed
                                      ? l10n.weeklyTopicCoinRewardClaimed
                                      : l10n.weeklyTopicClaimCoinReward,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Divider(),
                            const SizedBox(height: 8),
                            Text(
                              l10n.weeklyTopicCompletionRewardDescription(
                                WeeklyTopicService.completionRewardThreshold,
                                rewardAvatar.emoji,
                                rewardAvatar.name,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              completionRewardClaimed
                                  ? l10n.weeklyTopicExclusiveClaimed
                                  : correctAnswers >=
                                          WeeklyTopicService
                                              .completionRewardThreshold
                                      ? l10n.weeklyTopicExclusiveReady
                                      : l10n.weeklyTopicExclusiveLockedRounds(
                                          WeeklyTopicService
                                              .completionRewardThreshold,
                                        ),
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: canClaimCompletion &&
                                        !_claimingCompletion
                                    ? () => _claimCompletionReward(
                                          weekId: weekId,
                                          rewardAvatarId: rewardAvatarId,
                                        )
                                    : null,
                                icon: const Icon(Icons.card_giftcard_outlined),
                                label: Text(
                                  completionRewardClaimed
                                      ? l10n.weeklyTopicExclusiveClaimedButton
                                      : l10n.weeklyTopicClaimCompletionReward,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: _isNavigating
                            ? null
                            : () {
                                final categoryId =
                                    (topicData['categoryId'] ?? '').toString();

                                if (categoryId.isEmpty) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        l10n.weeklyTopicCategoryMissing,
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                _playRound(
                                  categoryId: categoryId,
                                  categoryName: title,
                                  weekId: weekId,
                                );
                              },
                        icon: const Icon(Icons.play_arrow),
                        label: Text(l10n.weeklyTopicPlayButton),
                      ),
                    ],
                  ),
                  if (_claimingCoins || _claimingCompletion)
                    Container(
                      color: Colors.black.withValues(alpha: 0.25),
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}