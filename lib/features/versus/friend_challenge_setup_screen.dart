import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/ai_topic_service.dart';
import '../../services/match_service.dart';
import '../../services/realtime_invite_service.dart';
import '../../theme/app_theme.dart';
import 'async_match_play_screen.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../services/locale_controller.dart';
import '../../l10n/localized_content.dart';
import '../../l10n/user_facing_error.dart';
import '../../widgets/app_bar_title.dart';
import '../../widgets/profile_avatar_button.dart';

class _CategoryOption {
  final String id;
  final String name;
  final bool custom;

  const _CategoryOption({
    required this.id,
    required this.name,
    this.custom = false,
  });
}

const _customTopicPrefix = 'custom:';

/// The category picker's value for one of the player's custom topics.
String customTopicOptionValue(String topicId) => '$_customTopicPrefix$topicId';

/// The custom topic a picker value names, or null for a fixed category.
String? customTopicIdFrom(String value) {
  if (!value.startsWith(_customTopicPrefix)) return null;
  final id = value.substring(_customTopicPrefix.length);
  return id.isEmpty ? null : id;
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
  int _timePerQuestionSec = 15;

  late final Future<List<_CategoryOption>> _categoriesFuture =
      _loadCategories();

  // Only async challenges can use them: their questions are written for
  // the challenge, which takes longer than a live invite should wait.
  late final Future<List<_CategoryOption>> _customTopicsFuture =
      _loadCustomTopics();

  Future<List<_CategoryOption>> _loadCustomTopics() async {
    try {
      final topics = await AiTopicService.instance.readyTopicsForChallenge();
      return [
        for (final topic in topics)
          _CategoryOption(
            id: customTopicOptionValue(topic.id),
            name: topic.title,
            custom: true,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  // Held here: a Future.wait built in build() would be a new future on
  // every rebuild, and the picker would blank out while it resolved.
  late final Future<List<List<_CategoryOption>>> _allCategoriesFuture =
      Future.wait([_categoriesFuture, _customTopicsFuture]);

  bool get _customSelected => customTopicIdFrom(_categoryId) != null;

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
          name: localizedCategoryName(doc.data(), LocaleController.instance.locale.value.languageCode) ?? doc.id,
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
      if (_challengeType == 'realtime') {
        await _realtimeInviteService.createInvite(
          toUid: widget.friendUid,
          categoryId: _categoryId,
          difficulty: _difficulty,
          totalQuestions: _totalQuestions,
          timePerQuestionSec: _timePerQuestionSec,
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

      final aiTopicId = customTopicIdFrom(_categoryId);
      final matchId = await _matchService.createAsyncFixedMatch(
        challengedUid: widget.friendUid,
        categoryId: aiTopicId != null ? 'custom' : _categoryId,
        aiTopicId: aiTopicId,
        difficulty: _difficulty,
        totalQuestions: _totalQuestions,
        timePerQuestionSec: _timePerQuestionSec,
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
        _error = userFacingError(AppLocalizations.of(context), e);
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
        ? context.appColors.success
        : Theme.of(context).colorScheme.onSurfaceVariant;

    final canSendRealtime = widget.isOnline;
    final sendButtonText = _challengeType == 'realtime'
        ? l10n.friendChallengeSendRealtime
        : l10n.friendChallengeCreateAsync;

    return Scaffold(
      appBar: AppBar(
        actions: const [ProfileAvatarButton()],
        title: AppBarTitle(l10n.friendChallengeTitle),
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
                  borderRadius: BorderRadius.circular(context.radii.md),
                  boxShadow: context.surfaces.shadowsOr(null),
                  border: context.surfaces.borderOr(Border.all(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.25),
                  )),
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
                style: context.heading(18),
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
                    if (_challengeType == 'realtime' && _customSelected) {
                      _categoryId = 'random';
                    }
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
                style: context.heading(18),
              ),
              const SizedBox(height: 10),
              FutureBuilder<List<List<_CategoryOption>>>(
                future: _allCategoriesFuture,
                builder: (context, snap) {
                  final options = [
                    _CategoryOption(
                      id: 'random',
                      name: l10n.friendChallengeCategoryRandom,
                    ),
                    ...?snap.data?[0],
                    if (_challengeType == 'async') ...?snap.data?[1],
                  ];

                  return DropdownButtonFormField<String>(
                    key: ValueKey(_challengeType),
                    initialValue: options.any((o) => o.id == _categoryId)
                        ? _categoryId
                        : null,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: l10n.createMatchCategory,
                      border: const OutlineInputBorder(),
                    ),
                    items: options
                        .map(
                          (category) => DropdownMenuItem(
                            value: category.id,
                            child: Row(
                              children: [
                                if (category.custom) ...[
                                  const Icon(Icons.edit_note, size: 20),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: Text(
                                    category.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
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
              if (_challengeType == 'async' && _customSelected) ...[
                const SizedBox(height: 8),
                Text(
                  l10n.friendChallengeCustomTopicHint,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
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
                  style: TextStyle(color: context.appColors.danger),
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
              color: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.25),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    if (_customSelected) ...[
                      const SizedBox(height: 16),
                      Text(
                        l10n.friendChallengePreparingQuestions,
                        style: context.heading(16),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
