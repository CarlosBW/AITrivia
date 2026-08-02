import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/economy_service.dart';
import '../../services/match_service.dart';
import '../../services/realtime_invite_service.dart';
import '../../theme/app_theme.dart';
import 'async_match_play_screen.dart';
import '../../l10n/generated/app_localizations.dart';

class _CategoryOption {
  final String id;
  final String name;

  const _CategoryOption({required this.id, required this.name});
}

class FriendChallengeSetupScreen extends StatefulWidget {
  final String friendUid;
  final String friendName;
  final bool isOnline;

  const FriendChallengeSetupScreen({
    super.key,
    required this.friendUid,
    required this.friendName,
    required this.isOnline,
  });

  @override
  State<FriendChallengeSetupScreen> createState() =>
      _FriendChallengeSetupScreenState();
}

class _FriendChallengeSetupScreenState
    extends State<FriendChallengeSetupScreen> {
  final _matchService = MatchService();
  final _realtimeInviteService = RealtimeInviteService.instance;

  bool _loading = false;
  String? _error;

  String _challengeType = 'realtime';
  String _categoryId = 'random';
  int _difficulty = 1;
  int _totalQuestions = 10;
  int _timePerQuestionSec = 10;

  late final Future<List<_CategoryOption>> _categoriesFuture =
      _loadCategories();

  // Mirrors live_menu_screen.dart's _loadCategories — reads the same
  // fixed_categories collection instead of a hand-maintained list that
  // drifts as categories are added/renamed/deactivated.
  Future<List<_CategoryOption>> _loadCategories() async {
    final snap = await FirebaseFirestore.instance
        .collection('fixed_categories')
        .where('isActive', isEqualTo: true)
        .get();

    final docs = snap.docs.toList()
      ..sort((a, b) {
        final ao = ((a.data()['order'] ?? 999) as num).toInt();
        final bo = ((b.data()['order'] ?? 999) as num).toInt();
        return ao.compareTo(bo);
      });

    return [
      for (final doc in docs)
        _CategoryOption(
          id: doc.id,
          name: (doc.data()['name'] ?? doc.id).toString(),
        ),
    ];
  }

  Future<void> _sendChallenge() async {
    if (_loading) return;

    if (_challengeType == 'realtime' && !widget.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).friendChallengeNotOnline),
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final myName = await _matchService.getMyDisplayNameFallback('Player');

      if (_challengeType == 'realtime') {
        await _realtimeInviteService.createInvite(
          toUid: widget.friendUid,
          toName: widget.friendName,
          fromName: myName,
          categoryId: _categoryId,
          difficulty: _difficulty,
          totalQuestions: _totalQuestions,
          timePerQuestionSec: _timePerQuestionSec,
          winReward: EconomyService.defaultPvpWinReward,
        );

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context).friendChallengeRealtimeSent(widget.friendName),
            ),
          ),
        );

        Navigator.pop(context);
        return;
      }

      final matchId = await _matchService.createAsyncFixedMatch(
        challengedUid: widget.friendUid,
        categoryId: _categoryId,
        difficulty: _difficulty,
        totalQuestions: _totalQuestions,
        timePerQuestionSec: _timePerQuestionSec,
        winReward: EconomyService.defaultPvpWinReward,
        challengerDisplayName: myName,
        challengedDisplayName: widget.friendName,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AsyncMatchPlayScreen(asyncMatchId: matchId),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final onlineText = widget.isOnline ? l10n.friendChallengeOnline : l10n.friendChallengeOffline;
    final onlineColor = widget.isOnline
        ? AppColors.success
        : Theme.of(context).colorScheme.onSurfaceVariant;

    final canSendRealtime = widget.isOnline;
    final sendButtonText = _challengeType == 'realtime'
        ? l10n.friendChallengeSendRealtime
        : l10n.friendChallengeCreateAsync;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.friendChallengeTitle),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.sports_esports_outlined, size: 42),
                    const SizedBox(height: 12),
                    Text(
                      widget.friendName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: onlineColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          onlineText,
                          style: TextStyle(
                            color: onlineColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                l10n.friendChallengeTypeLabel,
                style: GoogleFonts.baloo2(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'realtime',
                    icon: Icon(
                      widget.isOnline
                          ? Icons.bolt_outlined
                          : Icons.lock_outline,
                    ),
                    label: Text(l10n.findOpponentLiveTab),
                  ),
                  ButtonSegment(
                    value: 'async',
                    icon: const Icon(Icons.schedule_outlined),
                    label: Text(l10n.findOpponentAsyncTab),
                  ),
                ],
                selected: {_challengeType},
                onSelectionChanged: (values) {
                  setState(() {
                    _challengeType = values.first;
                  });
                },
              ),
              if (_challengeType == 'realtime' && !canSendRealtime) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.friendChallengeNeedOnlineHint,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                l10n.friendChallengeMatchConfig,
                style: GoogleFonts.baloo2(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              FutureBuilder<List<_CategoryOption>>(
                future: _categoriesFuture,
                builder: (context, snap) {
                  final options = [
                    _CategoryOption(
                      id: 'random',
                      name: l10n.friendChallengeCategoryRandom,
                    ),
                    ...?snap.data,
                  ];

                  return DropdownButtonFormField<String>(
                    initialValue: _categoryId,
                    decoration: InputDecoration(
                      labelText: l10n.createMatchCategory,
                      border: const OutlineInputBorder(),
                    ),
                    items: options
                        .map(
                          (category) => DropdownMenuItem(
                            value: category.id,
                            child: Text(category.name),
                          ),
                        )
                        .toList(),
                    onChanged: _loading
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _categoryId = value);
                          },
                  );
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _difficulty,
                decoration: InputDecoration(
                  labelText: l10n.createMatchDifficulty,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(value: 1, child: Text(l10n.friendChallengeDiffEasy)),
                  DropdownMenuItem(value: 2, child: Text(l10n.friendChallengeDiffMedium)),
                  DropdownMenuItem(value: 3, child: Text(l10n.friendChallengeDiffHard)),
                ],
                onChanged: _loading
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _difficulty = value);
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _totalQuestions,
                decoration: InputDecoration(
                  labelText: l10n.friendChallengeQuestionCountLabel,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(value: 5, child: Text(l10n.friendChallengeQuestionsCount(5))),
                  DropdownMenuItem(value: 10, child: Text(l10n.friendChallengeQuestionsCount(10))),
                  DropdownMenuItem(value: 15, child: Text(l10n.friendChallengeQuestionsCount(15))),
                ],
                onChanged: _loading
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _totalQuestions = value);
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _timePerQuestionSec,
                decoration: InputDecoration(
                  labelText: l10n.friendChallengeTimePerQuestionLabel,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(value: 10, child: Text(l10n.friendChallengeSeconds(10))),
                  DropdownMenuItem(value: 15, child: Text(l10n.friendChallengeSeconds(15))),
                  DropdownMenuItem(value: 20, child: Text(l10n.friendChallengeSeconds(20))),
                ],
                onChanged: _loading
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _timePerQuestionSec = value);
                      },
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: const TextStyle(color: AppColors.danger),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed:
                    _loading || (_challengeType == 'realtime' && !canSendRealtime)
                        ? null
                        : _sendChallenge,
                icon: Icon(
                  _challengeType == 'realtime'
                      ? Icons.bolt_outlined
                      : Icons.schedule_outlined,
                ),
                label: Text(sendButtonText),
              ),
              const SizedBox(height: 12),
              Text(
                _challengeType == 'realtime'
                    ? l10n.friendChallengeRealtimeHint
                    : l10n.friendChallengeAsyncHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (_loading)
            Container(
              color: Colors.black.withValues(alpha: 0.25),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}