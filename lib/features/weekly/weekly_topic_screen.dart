import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/weekly_topic_service.dart';
import '../../services/avatar_service.dart';
import '../../services/life_service.dart';
import '../../widgets/no_lives_dialog.dart';
import '../../widgets/spotlight_hint.dart';
import 'weekly_topic_play_screen.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../l10n/user_facing_error.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bar_title.dart';
import '../../widgets/category_illustration.dart';
import '../../widgets/result_hero_banner.dart';
import 'weekly_reward_tile.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../l10n/lives_format.dart';

class WeeklyTopicScreen extends StatefulWidget {
  const WeeklyTopicScreen({super.key});

  @override
  State<WeeklyTopicScreen> createState() => _WeeklyTopicScreenState();
}

class _WeeklyTopicScreenState extends State<WeeklyTopicScreen> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;

  // Held so a rebuild doesn't tear down and re-subscribe them.
  late final _topicStream = WeeklyTopicService.instance.watchCurrentTopic();

  // Participation depends on the week the topic stream reports, so it can't
  // be a plain field — it's rebuilt only when that week actually changes.
  String? _participationWeekId;
  Stream<DocumentSnapshot<Map<String, dynamic>>>? _participationStream;

  Stream<DocumentSnapshot<Map<String, dynamic>>> _participationFor(
    String weekId,
  ) {
    if (_participationStream == null || _participationWeekId != weekId) {
      _participationWeekId = weekId;
      _participationStream = WeeklyTopicService.instance.watchMyParticipation(
        uid: _uid,
        weekId: weekId,
      );
    }
    return _participationStream!;
  }

  bool _claimingCoins = false;
  bool _claimingCompletion = false;
  bool _isNavigating = false;

  Future<bool> _ensureHasLives() async {
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
              '${AppLocalizations.of(context).lives(lifeUnits)} / '
              '${AppLocalizations.of(context).lives(maxLifeUnits)}',
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
            userFacingError(AppLocalizations.of(context), e),
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
            userFacingError(AppLocalizations.of(context), e),
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
        actions: const [ProfileAvatarButton()],
        title: AppBarTitle(l10n.weeklyTopicScreenTitle),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _topicStream,
        builder: (context, topicSnap) {
          if (topicSnap.hasError) {
            return Center(child: Text(userFacingError(AppLocalizations.of(context), topicSnap.error!)));
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
          final categoryId = (topicData['categoryId'] ?? '').toString();
          // The rotation writes per-language fields; the bare ones are what
          // older docs carried. Reading only `description` left this empty.
          final languageCode = Localizations.localeOf(context).languageCode;
          final title = (topicData['title_$languageCode'] ??
                  topicData['title'] ??
                  l10n.weeklyTopicScreenTitle)
              .toString();
          final description = (topicData['description_$languageCode'] ??
                  topicData['description'] ??
                  '')
              .toString();
          final rewardCoins = ((topicData['rewardCoins'] ?? 0) as num).toInt();
          final rewardAvatarId =
              (topicData['rewardAvatarId'] ?? '').toString();
          final rewardAvatar =
              AvatarService.instance.avatarById(rewardAvatarId);

          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: _participationFor(weekId),
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
                      // The topic on the theme's hero banner, with the
                      // category's own illustration: the screen opened on
                      // a flat tinted box with a star icon.
                      ResultHeroBanner(
                        child: Row(
                          children: [
                            CategoryIllustration(
                              categoryId: categoryId,
                              name: title,
                              size: 88,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  HeroBadge(
                                    label: l10n.weeklyTopicFeaturedBadge,
                                    icon: Icons.star_rounded,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    title,
                                    style: context.heading(
                                      24,
                                      color: context.appColors.onAccent,
                                    ),
                                  ),
                                  if (description.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      description,
                                      style: TextStyle(
                                        color: context.appColors.onAccent,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surface,
                          borderRadius: BorderRadius.circular(context.radii.md),
                          border: context.surfaces.borderOr(null),
                          boxShadow: context.surfaces.shadowsOr(null),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.weeklyTopicProgressTitle,
                              style: context.heading(18),
                            ),
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(
                                context.radii.pill,
                              ),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: 10,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              l10n.weeklyTopicCorrectAnswersProgress(
                                correctAnswers,
                                WeeklyTopicService.completionRewardThreshold,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        children: [
                          Icon(
                            Icons.emoji_events_rounded,
                            color: context.readableOnOwnTint(
                              context.appColors.reward,
                              wash: 0,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            l10n.weeklyTopicRewardsTitle,
                            style: context.heading(20),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      WeeklyRewardTile(
                        emblem: Icon(
                          Icons.monetization_on_rounded,
                          size: 30,
                          color: context.readableOnOwnTint(
                            context.appColors.reward,
                            wash: 0,
                          ),
                        ),
                        title: l10n.weeklyTopicCoinRewardDescription(
                          WeeklyTopicService.coinRewardThreshold,
                          rewardCoins,
                        ),
                        progress: correctAnswers /
                            WeeklyTopicService.coinRewardThreshold,
                        progressLabel: l10n.weeklyTopicCorrectAnswersProgress(
                          correctAnswers.clamp(
                            0,
                            WeeklyTopicService.coinRewardThreshold,
                          ),
                          WeeklyTopicService.coinRewardThreshold,
                        ),
                        state: weeklyRewardState(
                          correctAnswers: correctAnswers,
                          threshold: WeeklyTopicService.coinRewardThreshold,
                          claimed: coinRewardClaimed,
                        ),
                        claimLabel: l10n.weeklyTopicClaimCoinReward,
                        claimedLabel: l10n.weeklyTopicCoinRewardClaimed,
                        onClaim: canClaimCoins && !_claimingCoins
                            ? () => _claimCoinReward(
                                  weekId: weekId,
                                  rewardCoins: rewardCoins,
                                )
                            : null,
                      ),
                      const SizedBox(height: 12),
                      WeeklyRewardTile(
                        emblem: Text(
                          rewardAvatar.emoji,
                          style: const TextStyle(fontSize: 26),
                        ),
                        title: l10n.weeklyTopicCompletionRewardDescription(
                          WeeklyTopicService.completionRewardThreshold,
                          rewardAvatar.emoji,
                          rewardAvatar.name,
                        ),
                        progress: correctAnswers /
                            WeeklyTopicService.completionRewardThreshold,
                        progressLabel: l10n.weeklyTopicCorrectAnswersProgress(
                          correctAnswers.clamp(
                            0,
                            WeeklyTopicService.completionRewardThreshold,
                          ),
                          WeeklyTopicService.completionRewardThreshold,
                        ),
                        state: weeklyRewardState(
                          correctAnswers: correctAnswers,
                          threshold:
                              WeeklyTopicService.completionRewardThreshold,
                          claimed: completionRewardClaimed,
                        ),
                        claimLabel: l10n.weeklyTopicClaimCompletionReward,
                        claimedLabel: l10n.weeklyTopicExclusiveClaimed,
                        onClaim: canClaimCompletion && !_claimingCompletion
                            ? () => _claimCompletionReward(
                                  weekId: weekId,
                                  rewardAvatarId: rewardAvatarId,
                                )
                            : null,
                      ),
                      const SizedBox(height: 24),
                      SpotlightHint(
                        id: 'weekly_topic_play',
                        title: l10n.spotlightWeeklyTopicTitle,
                        description: l10n.spotlightWeeklyTopicBody,
                        child: FilledButton.icon(
                          onPressed: _isNavigating
                              ? null
                              : () {
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
                      ),
                    ],
                  ),
                  if (_claimingCoins || _claimingCompletion)
                    Container(
                      color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.25),
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
