import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/ai_topic_service.dart';
import '../../services/economy_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../theme/app_theme.dart';
import '../../widgets/spotlight_hint.dart';
import '../../widgets/profile_avatar_button.dart';

class CreateAiTopicScreen extends StatefulWidget {
  const CreateAiTopicScreen({super.key});

  @override
  State<CreateAiTopicScreen> createState() => _CreateAiTopicScreenState();
}

enum _Stage {
  typing,
  showingMatches,
  showingAiSuggestions,
  suggestionsUnavailable,
}

/// Which of the three prices `_PricingCard` should show — mirrors the
/// server's own tiering in `createAiTopic`: brand-new generation, an
/// existing-but-not-yet-popular reuse, or a popular reuse.
enum _TopicPriceTier { full, existing, popular }

class _CreateAiTopicScreenState extends State<CreateAiTopicScreen> {
  final _controller = TextEditingController();

  bool _loading = false;
  String _loadingLabel = '';
  String? _selectedPoolId;
  String? _selectedPoolTitle;

  _Stage _stage = _Stage.typing;
  List<SimilarAiTopic> _matches = [];
  List<AiTopicSuggestion> _aiSuggestions = [];
  String _searchedTitle = '';

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTitleChanged);
  }

  void _onTitleChanged() {
    // Picking a popular topic pre-fills the exact title it discounts —
    // editing away from that exact text falls back to the normal
    // full-price flow (the server still auto-detects a matching title on
    // its own either way, this is purely a UI-clarity guard).
    if (_selectedPoolId != null &&
        _controller.text.trim() != _selectedPoolTitle) {
      setState(() {
        _selectedPoolId = null;
        _selectedPoolTitle = null;
      });
    }
  }

  void _selectPopularTopic(String poolId, String title) {
    setState(() {
      _selectedPoolId = poolId;
      _selectedPoolTitle = title;
      _controller.text = title;
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Entry point for the main button. A title picked from the "Temas
  /// Populares" showcase is already a confirmed exact pool match, so it
  /// skips straight to creation; anything freely typed goes through the
  /// search-then-suggest flow first.
  Future<void> _onCreatePressed() async {
    final title = _controller.text.trim();
    final l10n = AppLocalizations.of(context);

    if (title.isEmpty) {
      _showError(l10n.createAiTopicEnterTopic);
      return;
    }

    if (_selectedPoolId != null) {
      await _doCreate(title, fromPoolId: _selectedPoolId);
      return;
    }

    await _search(title, l10n);
  }

  Future<void> _search(String title, AppLocalizations l10n) async {
    setState(() {
      _loading = true;
      _loadingLabel = l10n.createAiTopicSearchingButton;
    });

    try {
      final result =
          await AiTopicService.instance.findSimilarAiTopics(title: title);

      if (!mounted) return;

      if (result.blocked) {
        setState(() => _loading = false);
        _showError(l10n.createAiTopicBlockedMessage);
        return;
      }

      if (result.matches.isEmpty) {
        // Nothing close enough to reuse — go straight to AI suggestions
        // for this same title, no dead-end "no matches found" screen.
        await _requestAiSuggestions(title, l10n);
        return;
      }

      setState(() {
        _searchedTitle = title;
        _matches = result.matches;
        _stage = _Stage.showingMatches;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _requestAiSuggestions(
    String title,
    AppLocalizations l10n,
  ) async {
    setState(() {
      _loading = true;
      _loadingLabel = l10n.createAiTopicSuggestingButton;
    });

    try {
      final result =
          await AiTopicService.instance.suggestAiTopicTitles(title: title);

      if (!mounted) return;

      if (result.blocked) {
        setState(() => _loading = false);
        _showError(l10n.createAiTopicBlockedMessage);
        return;
      }

      if (result.suggestions.isEmpty) {
        // Not blocked (the server says so explicitly), just nothing usable
        // came back — same recovery as an outright failure.
        _fallBackToOwnTitle(title);
        return;
      }

      setState(() {
        _searchedTitle = title;
        _aiSuggestions = result.suggestions;
        _stage = _Stage.showingAiSuggestions;
        _loading = false;
      });
    } on AiTopicSuggestionUnavailable {
      if (!mounted) return;
      // Suggestions are a convenience, not a gate. This used to dead-end
      // the whole flow at the exact moment the player wanted to spend, for
      // a failure that has nothing to do with what they typed. Continuing
      // with their raw title is safe: createAiTopic independently
      // re-checks length, reserved names, blocked keywords and the topic
      // cap, and it generates before it charges, so if the model is still
      // down they simply get an error instead of losing coins.
      _fallBackToOwnTitle(title);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _fallBackToOwnTitle(String title) {
    setState(() {
      _searchedTitle = title;
      _aiSuggestions = [];
      _stage = _Stage.suggestionsUnavailable;
      _loading = false;
    });
  }

  Future<void> _doCreate(String title, {String? fromPoolId}) async {
    final l10n = AppLocalizations.of(context);

    setState(() {
      _loading = true;
      _loadingLabel = l10n.createAiTopicCreatingButton;
    });

    try {
      await AiTopicService.instance.createAiTopic(
        title: title,
        fromPoolId: fromPoolId,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.createAiTopicCreated)),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showError(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _backToTyping() {
    setState(() {
      _stage = _Stage.typing;
      _matches = [];
      _aiSuggestions = [];
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onTitleChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        actions: const [ProfileAvatarButton()],
        title: Text(l10n.aiTopicsEmptyButton),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: switch (_stage) {
            _Stage.typing => _buildTypingStage(l10n),
            _Stage.showingMatches => _buildMatchesStage(l10n),
            _Stage.showingAiSuggestions => _buildAiSuggestionsStage(l10n),
            _Stage.suggestionsUnavailable =>
              _buildSuggestionsUnavailableStage(l10n),
          },
        ),
      ),
    );
  }

  List<Widget> _buildTypingStage(AppLocalizations l10n) {
    return [
      Text(
        l10n.createAiTopicSubtitle,
        style: context.heading(22),
      ),
      const SizedBox(height: 10),
      Text(
        l10n.createAiTopicExamplesLabel,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 6),
      Text(l10n.createAiTopicExamplesList),
      const SizedBox(height: 24),
      _PopularTopicsSection(
        selectedPoolId: _selectedPoolId,
        onSelect: _selectPopularTopic,
      ),
      TextField(
        controller: _controller,
        maxLength: 60,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: l10n.createAiTopicFieldLabel,
          hintText: l10n.createAiTopicFieldHint,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 20),
      _PricingCard(
        uid: FirebaseAuth.instance.currentUser!.uid,
        // Only the "Temas Populares" showcase sets _selectedPoolId, and
        // that showcase is itself filtered to popular entries only — so
        // any selection here is always the popular tier.
        tier: _selectedPoolId != null
            ? _TopicPriceTier.popular
            : _TopicPriceTier.full,
      ),
      const SizedBox(height: 24),
      // Explained here rather than on the Popular Topics showcase alone:
      // that showcase stays hidden until topics actually get reused, so on
      // a fresh install this button is the only place the search-first
      // behaviour (and its discount) can be introduced.
      SpotlightHint(
        id: 'ai_topics_guided_creation',
        title: l10n.spotlightAiTopicsGuidedTitle,
        description: l10n.spotlightAiTopicsGuidedBody,
        child: SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _loading ? null : _onCreatePressed,
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.auto_awesome),
            label: Text(_loading ? _loadingLabel : l10n.aiTopicsCreateTopic),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildMatchesStage(AppLocalizations l10n) {
    return [
      Text(
        l10n.createAiTopicMatchesFoundTitle,
        style: context.heading(20),
      ),
      const SizedBox(height: 6),
      Text(
        l10n.createAiTopicMatchesFoundHint,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 16),
      _EconomyBuilder(
        uid: FirebaseAuth.instance.currentUser!.uid,
        builder: (context, coins, hasFreePass) => Column(
          children: [
            _CoinsBalanceLine(coins: coins, hasFreePass: hasFreePass),
            const SizedBox(height: 12),
            for (final match in _matches) ...[
              _TopicChoiceCard(
                title: match.title,
                badge: match.isPopular
                    ? _ChoiceBadge.popular
                    : _ChoiceBadge.existing,
                cost: match.cost,
                hasFreePass: hasFreePass,
                onTap: _loading
                    ? null
                    : () => _doCreate(match.title, fromPoolId: match.poolId),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: _loading
              ? null
              : () => _requestAiSuggestions(_searchedTitle, l10n),
          child: Text(l10n.createAiTopicNoneOfTheseButton),
        ),
      ),
      const SizedBox(height: 8),
      TextButton(
        onPressed: _loading ? null : _backToTyping,
        child: Text(l10n.createAiTopicBackButton),
      ),
      if (_loading) ...[
        const SizedBox(height: 12),
        Center(
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 8),
              Text(_loadingLabel),
            ],
          ),
        ),
      ],
    ];
  }

  List<Widget> _buildAiSuggestionsStage(AppLocalizations l10n) {
    return [
      Text(
        l10n.createAiTopicAiSuggestionsTitle,
        style: context.heading(20),
      ),
      const SizedBox(height: 6),
      Text(
        l10n.createAiTopicAiSuggestionsHint,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 16),
      _EconomyBuilder(
        uid: FirebaseAuth.instance.currentUser!.uid,
        builder: (context, coins, hasFreePass) => Column(
          children: [
            _CoinsBalanceLine(coins: coins, hasFreePass: hasFreePass),
            const SizedBox(height: 12),
            for (final suggestion in _aiSuggestions) ...[
              _TopicChoiceCard(
                title: suggestion.title,
                // Claude can land on a title that already exists in the
                // pool — the server discounts it, so badge and price it
                // the same way a search match would be.
                badge: !suggestion.existsInPool
                    ? _ChoiceBadge.none
                    : suggestion.isPopular
                        ? _ChoiceBadge.popular
                        : _ChoiceBadge.existing,
                cost: suggestion.cost,
                hasFreePass: hasFreePass,
                onTap: _loading ? null : () => _doCreate(suggestion.title),
              ),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
      const SizedBox(height: 6),
      TextButton(
        onPressed: _loading ? null : _backToTyping,
        child: Text(l10n.createAiTopicBackButton),
      ),
      if (_loading) ...[
        const SizedBox(height: 12),
        Center(
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 8),
              Text(_loadingLabel),
            ],
          ),
        ),
      ],
    ];
  }

  /// Shown when suggestions couldn't be produced. Offers the title the
  /// player already typed as a normal choice, so a hiccup in an optional
  /// helper never costs them the topic they came to create.
  List<Widget> _buildSuggestionsUnavailableStage(AppLocalizations l10n) {
    return [
      Text(
        l10n.createAiTopicSuggestionsUnavailableTitle,
        style: context.heading(20),
      ),
      const SizedBox(height: 6),
      Text(
        l10n.createAiTopicSuggestionsUnavailableHint,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 16),
      _EconomyBuilder(
        uid: FirebaseAuth.instance.currentUser!.uid,
        builder: (context, coins, hasFreePass) => Column(
          children: [
            _CoinsBalanceLine(coins: coins, hasFreePass: hasFreePass),
            const SizedBox(height: 12),
            _TopicChoiceCard(
              title: _searchedTitle,
              badge: _ChoiceBadge.none,
              // Quoted at full price: without suggestions there's no
              // server-side pool lookup to tell us otherwise. If the title
              // does turn out to exist, createAiTopic discounts it on its
              // own — erring high means the surprise is always pleasant.
              cost: EconomyService.createAiTopicCost,
              hasFreePass: hasFreePass,
              onTap: _loading ? null : () => _doCreate(_searchedTitle),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _loading
              ? null
              : () => _requestAiSuggestions(_searchedTitle, l10n),
          icon: const Icon(Icons.refresh),
          label: Text(l10n.createAiTopicRetrySuggestionsButton),
        ),
      ),
      const SizedBox(height: 6),
      TextButton(
        onPressed: _loading ? null : _backToTyping,
        child: Text(l10n.createAiTopicBackButton),
      ),
      if (_loading) ...[
        const SizedBox(height: 12),
        Center(
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 8),
              Text(_loadingLabel),
            ],
          ),
        ),
      ],
    ];
  }
}

/// What (if anything) makes a choice cheaper than a brand-new topic.
enum _ChoiceBadge { none, existing, popular }

/// Streams the caller's coin balance and free-pass state once for a whole
/// step, so a list of cards doesn't open one Firestore subscription each.
class _EconomyBuilder extends StatefulWidget {
  final String uid;
  final Widget Function(BuildContext context, int coins, bool hasFreePass)
      builder;

  const _EconomyBuilder({required this.uid, required this.builder});

  @override
  State<_EconomyBuilder> createState() => _EconomyBuilderState();
}

// Stateful only to keep the balance stream across rebuilds — this screen
// rebuilds on every step change and every loading-state flip.
class _EconomyBuilderState extends State<_EconomyBuilder> {
  late final _userDoc = FirebaseFirestore.instance
      .collection('users')
      .doc(widget.uid)
      .snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDoc,
      builder: (context, snap) {
        final data = snap.data?.data() ?? {};
        final coins = ((data['coins'] ?? 0) as num).toInt();
        final freePasses = ((data['freeTopicPasses'] ?? 0) as num).toInt();
        return widget.builder(context, coins, freePasses > 0);
      },
    );
  }
}

class _CoinsBalanceLine extends StatelessWidget {
  final int coins;
  final bool hasFreePass;

  const _CoinsBalanceLine({required this.coins, required this.hasFreePass});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Text(
      hasFreePass
          ? l10n.createAiTopicFirstFree
          : l10n.createAiTopicYouHaveCoins(coins),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontWeight: FontWeight.w600,
        color: hasFreePass ? context.appColors.success : null,
      ),
    );
  }
}

/// A pickable topic title in the guided-creation flow — either an existing
/// pool match or an AI-proposed title. [cost] is what the server will
/// really charge, so it already reflects any reuse discount; a free pass
/// overrides it entirely.
class _TopicChoiceCard extends StatelessWidget {
  final String title;
  final _ChoiceBadge badge;
  final int cost;
  final bool hasFreePass;
  final VoidCallback? onTap;

  const _TopicChoiceCard({
    required this.title,
    required this.badge,
    required this.cost,
    required this.hasFreePass,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    final (IconData icon, Color iconColor, String tooltip) = switch (badge) {
      _ChoiceBadge.popular => (
          Icons.star,
          context.appColors.reward,
          l10n.createAiTopicPopularBadgeTooltip,
        ),
      _ChoiceBadge.existing => (
          Icons.sell,
          Colors.blueAccent,
          l10n.createAiTopicExistingBadgeTooltip,
        ),
      _ChoiceBadge.none => (
          Icons.auto_awesome,
          scheme.onSurfaceVariant,
          l10n.createAiTopicNewBadgeTooltip,
        ),
    };

    return InkWell(
      borderRadius: BorderRadius.circular(context.radii.sm),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(context.radii.sm),
          boxShadow: context.surfaces.shadowsOr(null),
          border: context.surfaces.borderOr(Border.all(color: scheme.outline.withValues(alpha: 0.2))),
        ),
        child: Row(
          children: [
            Tooltip(
              message: tooltip,
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              hasFreePass
                  ? l10n.createAiTopicFreeLabel
                  : l10n.createAiTopicPopularCostLabel(cost),
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: hasFreePass || badge != _ChoiceBadge.none
                    ? Colors.green
                    : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PricingCard extends StatefulWidget {
  final String uid;
  final _TopicPriceTier tier;

  const _PricingCard({required this.uid, required this.tier});

  @override
  State<_PricingCard> createState() => _PricingCardState();
}

// Stateful for the same reason as _EconomyBuilder above.
class _PricingCardState extends State<_PricingCard> {
  late final _userDoc = FirebaseFirestore.instance
      .collection('users')
      .doc(widget.uid)
      .snapshots();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _userDoc,
      builder: (context, snap) {
        final l10n = AppLocalizations.of(context);
        final data = snap.data?.data() ?? {};
        final coins = ((data['coins'] ?? 0) as num).toInt();
        final freePasses = ((data['freeTopicPasses'] ?? 0) as num).toInt();
        final hasFreePass = freePasses > 0;
        final cost = switch (widget.tier) {
          _TopicPriceTier.popular => EconomyService.createAiTopicFromPoolCost,
          _TopicPriceTier.existing => EconomyService.createAiTopicExistingCost,
          _TopicPriceTier.full => EconomyService.createAiTopicCost,
        };
        final canAfford = hasFreePass || coins >= cost;

        final accentColor = canAfford ? context.appColors.success : context.appColors.danger;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(context.radii.md),
            boxShadow: context.surfaces.shadowsOr(null),
            border: context.surfaces.borderOr(Border.all(color: accentColor.withValues(alpha: 0.3))),
          ),
          child: Column(
            children: [
              const Icon(Icons.auto_awesome),
              const SizedBox(height: 10),
              Text(
                l10n.createAiTopicYouHaveCoins(coins),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                hasFreePass
                    ? l10n.createAiTopicFirstFree
                    : l10n.createAiTopicCosts(cost),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (!hasFreePass && widget.tier != _TopicPriceTier.full) ...[
                const SizedBox(height: 4),
                Text(
                  widget.tier == _TopicPriceTier.popular
                      ? l10n.createAiTopicPopularSelectedHint
                      : l10n.createAiTopicExistingSelectedHint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              ],
              if (!hasFreePass && !canAfford) ...[
                const SizedBox(height: 4),
                Text(
                  l10n.createAiTopicMissingCoins(cost - coins),
                  style: TextStyle(color: accentColor, fontSize: 12),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                l10n.createAiTopicIncludesHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Ready shared pool entries the player can create from at a discount
/// instead of paying full price — see AiTopicService.watchPopularAiTopics.
/// Renders nothing while the pool is empty/cold-start (no "no popular
/// topics yet" placeholder), so it never gets in the way of just typing a
/// new title.
class _PopularTopicsSection extends StatefulWidget {
  final String? selectedPoolId;
  final void Function(String poolId, String title) onSelect;

  const _PopularTopicsSection({
    required this.selectedPoolId,
    required this.onSelect,
  });

  @override
  State<_PopularTopicsSection> createState() => _PopularTopicsSectionState();
}

// Stateful only to hold the pool query across rebuilds — selecting a topic
// rebuilds the parent, which used to re-subscribe this.
class _PopularTopicsSectionState extends State<_PopularTopicsSection> {
  late final _popularTopics = AiTopicService.instance.watchPopularAiTopics();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _popularTopics,
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        return SpotlightHint(
          id: 'ai_topics_popular_discount',
          title: l10n.spotlightAiTopicsPopularTitle,
          description: l10n.spotlightAiTopicsPopularBody,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.createAiTopicPopularSectionTitle,
                  style: context.heading(16),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.createAiTopicPopularSectionHint,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 100,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final data = docs[index].data();
                      final title = (data['title'] ?? '').toString();
                      final usageCount =
                          ((data['usageCount'] ?? 0) as num).toInt();

                      return _PopularTopicCard(
                        title: title,
                        usageCount: usageCount,
                        selected: docs[index].id == widget.selectedPoolId,
                        onTap: () => widget.onSelect(docs[index].id, title),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PopularTopicCard extends StatelessWidget {
  final String title;
  final int usageCount;
  final bool selected;
  final VoidCallback onTap;

  const _PopularTopicCard({
    required this.title,
    required this.usageCount,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final accentColor = selected ? scheme.primary : scheme.outline;

    return InkWell(
      borderRadius: BorderRadius.circular(context.radii.sm),
      onTap: onTap,
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.1)
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(context.radii.sm),
          boxShadow: context.surfaces.shadowsOr(null),
          border: context.surfaces.borderOr(Border.all(
            color: accentColor.withValues(alpha: selected ? 0.6 : 0.2),
          )),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            Text(
              l10n.createAiTopicPopularUsedCount(usageCount),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            Row(
              children: [
                Text(
                  l10n.createAiTopicPopularCostLabel(
                    EconomyService.createAiTopicCost,
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    decoration: TextDecoration.lineThrough,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.createAiTopicPopularCostLabel(
                    EconomyService.createAiTopicFromPoolCost,
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: context.appColors.success,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
