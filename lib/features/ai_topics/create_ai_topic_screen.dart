import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/ai_topic_service.dart';
import '../../services/economy_service.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/spotlight_hint.dart';

class CreateAiTopicScreen extends StatefulWidget {
  const CreateAiTopicScreen({super.key});

  @override
  State<CreateAiTopicScreen> createState() =>
      _CreateAiTopicScreenState();
}

class _CreateAiTopicScreenState
    extends State<CreateAiTopicScreen> {
  final _controller = TextEditingController();

  bool _loading = false;
  String? _selectedPoolId;
  String? _selectedPoolTitle;

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

  Future<void> _createTopic() async {
    final title = _controller.text.trim();

    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).createAiTopicEnterTopic),
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      await AiTopicService.instance.createAiTopic(
        title: title,
        fromPoolId: _selectedPoolId,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).createAiTopicCreated),
        ),
      );

      Navigator.pop(context);
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
        setState(() => _loading = false);
      }
    }
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
        title: Text(l10n.aiTopicsEmptyButton),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.createAiTopicSubtitle,
              style: GoogleFonts.baloo2(
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              l10n.createAiTopicExamplesLabel,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
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
              textCapitalization:
                  TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: l10n.createAiTopicFieldLabel,
                hintText: l10n.createAiTopicFieldHint,
                border: const OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 20),

            _PricingCard(
              uid: FirebaseAuth.instance.currentUser!.uid,
              poolDiscount: _selectedPoolId != null,
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _loading ? null : _createTopic,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  _loading
                      ? l10n.createAiTopicCreatingButton
                      : l10n.aiTopicsCreateTopic,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PricingCard extends StatelessWidget {
  final String uid;
  final bool poolDiscount;

  const _PricingCard({required this.uid, required this.poolDiscount});

  @override
  Widget build(BuildContext context) {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: userRef.snapshots(),
      builder: (context, snap) {
        final l10n = AppLocalizations.of(context);
        final data = snap.data?.data() ?? {};
        final coins = ((data['coins'] ?? 0) as num).toInt();
        final freePasses = ((data['freeTopicPasses'] ?? 0) as num).toInt();
        final hasFreePass = freePasses > 0;
        final cost = poolDiscount
            ? EconomyService.createAiTopicFromPoolCost
            : EconomyService.createAiTopicCost;
        final canAfford = hasFreePass || coins >= cost;

        final accentColor = canAfford ? Colors.green : Colors.redAccent;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accentColor.withValues(alpha: 0.3)),
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
              if (!hasFreePass && poolDiscount) ...[
                const SizedBox(height: 4),
                Text(
                  l10n.createAiTopicPopularSelectedHint,
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
class _PopularTopicsSection extends StatelessWidget {
  final String? selectedPoolId;
  final void Function(String poolId, String title) onSelect;

  const _PopularTopicsSection({
    required this.selectedPoolId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: AiTopicService.instance.watchPopularAiTopics(),
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
                  style: GoogleFonts.baloo2(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
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
                        selected: docs[index].id == selectedPoolId,
                        onTap: () => onSelect(docs[index].id, title),
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
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.1)
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accentColor.withValues(alpha: selected ? 0.6 : 0.2),
          ),
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
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
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