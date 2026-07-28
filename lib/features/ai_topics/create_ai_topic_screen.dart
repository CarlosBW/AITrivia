import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/ai_topic_service.dart';
import '../../services/economy_service.dart';
import '../../l10n/generated/app_localizations.dart';

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

  const _PricingCard({required this.uid});

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
        final cost = EconomyService.createAiTopicCost;
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