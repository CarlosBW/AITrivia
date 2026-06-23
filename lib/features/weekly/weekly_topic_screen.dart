import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/weekly_topic_service.dart';
import '../../services/avatar_service.dart';
import '../solo/level_select_screen.dart';

class WeeklyTopicScreen extends StatefulWidget {
  const WeeklyTopicScreen({super.key});

  @override
  State<WeeklyTopicScreen> createState() => _WeeklyTopicScreenState();
}

class _WeeklyTopicScreenState extends State<WeeklyTopicScreen> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;

  bool _claimingCoins = false;
  bool _claimingCompletion = false;

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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            claimed
                ? '+$rewardCoins coins claimed!'
                : 'Reward already claimed or not available yet.',
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
        const SnackBar(
          content: Text('No exclusive reward configured for this week.'),
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

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            claimed
                ? '${avatar.emoji} ${avatar.name} unlocked!'
                : 'Reward already claimed or not available yet.',
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Weekly Topic'),
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
            return const Center(
              child: Text('No Weekly Topic available.'),
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

              final levelsCompleted =
                  ((participation?['levelsCompleted'] ?? 0) as num).toInt();

              final coinRewardClaimed =
                  participation?['coinRewardClaimed'] == true;

              final completionRewardClaimed =
                  participation?['completionRewardClaimed'] == true;

              final canClaimCoins =
                  WeeklyTopicService.instance.canClaimCoinReward(participation);

              final canClaimCompletion = WeeklyTopicService.instance
                  .canClaimCompletionReward(participation);

              final progress = (levelsCompleted / 10).clamp(0.0, 1.0);

              return Stack(
                children: [
                  ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: Colors.amber.withOpacity(0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.star, color: Colors.amber),
                                SizedBox(width: 8),
                                Text(
                                  'Weekly Featured Topic',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
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
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Progress',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            LinearProgressIndicator(value: progress),
                            const SizedBox(height: 10),
                            Text('$levelsCompleted / 10 levels completed'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Rewards',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text('5 levels: +$rewardCoins coins'),
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
                                icon: const Icon(Icons.monetization_on),
                                label: Text(
                                  coinRewardClaimed
                                      ? 'Coin reward claimed'
                                      : 'Claim 5-level reward',
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Divider(),
                            const SizedBox(height: 8),
                            Text(
                              '10 levels: ${rewardAvatar.emoji} ${rewardAvatar.name}',
                            ),
                            const SizedBox(height: 6),
                            Text(
                              completionRewardClaimed
                                  ? 'Exclusive reward claimed.'
                                  : levelsCompleted >= 10
                                      ? 'Exclusive reward ready to claim.'
                                      : 'Complete all 10 levels to unlock this reward.',
                              style: const TextStyle(color: Colors.black54),
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
                                icon: const Icon(Icons.card_giftcard),
                                label: Text(
                                  completionRewardClaimed
                                      ? 'Exclusive reward claimed'
                                      : 'Claim 10-level reward',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () {
                          final categoryId =
                              (topicData['categoryId'] ?? '').toString();

                          if (categoryId.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('Weekly Topic category is missing.'),
                              ),
                            );
                            return;
                          }

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => LevelSelectScreen(
                                categoryId: categoryId,
                                categoryName: title,
                                isWeeklyTopic: true,
                                weeklyTopicWeekId: weekId,
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play Weekly Topic'),
                      ),
                    ],
                  ),
                  if (_claimingCoins || _claimingCompletion)
                    Container(
                      color: Colors.black.withOpacity(0.25),
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