import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/ai_topic_service.dart';
import '../../services/economy_service.dart';

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
        const SnackBar(
          content: Text('Enter a topic'),
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
        const SnackBar(
          content: Text('AI topic created'),
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create AI Topic'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Create your own trivia category',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            const Text(
              'Examples:',
              style: TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              '• Formula 1\n'
              '• Harry Potter\n'
              '• Marvel Movies\n'
              '• Ancient Egypt\n'
              '• Space Exploration',
            ),

            const SizedBox(height: 24),

            TextField(
              controller: _controller,
              maxLength: 60,
              textCapitalization:
                  TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Topic',
                hintText: 'Example: Formula 1',
                border: OutlineInputBorder(),
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
                      ? 'Creating...'
                      : 'Create Topic',
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
            color: accentColor.withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: accentColor.withOpacity(0.3)),
          ),
          child: Column(
            children: [
              const Icon(Icons.auto_awesome),
              const SizedBox(height: 10),
              Text(
                'Tienes $coins monedas',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                hasFreePass
                    ? '🎉 Tu primer tema es gratis'
                    : 'Este tema cuesta $cost monedas',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (!hasFreePass && !canAfford) ...[
                const SizedBox(height: 4),
                Text(
                  'Te faltan ${cost - coins} monedas',
                  style: TextStyle(color: accentColor, fontSize: 12),
                ),
              ],
              const SizedBox(height: 10),
              const Text(
                'Incluye 10 niveles con 10 preguntas cada uno, '
                'preparados de a poco mientras juegas.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}