import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/ai_topic_service.dart';
import 'create_ai_topic_screen.dart';
import '../solo/level_select_screen.dart';

class AiTopicsScreen extends StatelessWidget {
  const AiTopicsScreen({super.key});

  Color _statusColor(String status) {
    switch (status) {
      case 'ready':
        return Colors.green;
      case 'failed':
        return Colors.redAccent;
      case 'deleted':
        return Colors.grey;
      case 'pending_generation':
      default:
        return Colors.orange;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'ready':
        return 'Ready';
      case 'failed':
        return 'Failed';
      case 'deleted':
        return 'Deleted';
      case 'pending_generation':
      default:
        return 'Preparing';
    }
  }

  Future<void> _openCreate(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CreateAiTopicScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = AiTopicService.instance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Topics'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreate(context),
        icon: const Icon(Icons.add),
        label: const Text('Create Topic'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: service.watchMyAiTopics(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error loading AI topics:\n${snap.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs
              .where((doc) => (doc.data()['status'] ?? '') != 'deleted')
              .toList();

          if (docs.isEmpty) {
            return _EmptyAiTopics(
              onCreate: () => _openCreate(context),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();

              final title = (data['title'] ?? 'Untitled topic').toString();
              final status =
                  (data['status'] ?? 'pending_generation').toString();
              final levelsCount = ((data['levelsCount'] ?? 0) as num).toInt();
              final questionsCount =
                  ((data['questionsCount'] ?? 0) as num).toInt();
              final usedFreePass = data['usedFreePass'] == true;
              final cost = ((data['generationCostCoins'] ?? 0) as num).toInt();

              final color = _statusColor(status);

              return Dismissible(
                key: ValueKey(doc.id),
                direction: DismissDirection.endToStart,
                confirmDismiss: (_) async {
                  return showDialog<bool>(
                    context: context,
                    builder: (dialogContext) {
                      return AlertDialog(
                        title: const Text('Delete topic?'),
                        content: Text(
                          'Do you want to remove "$title" from your AI topics?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(dialogContext, false);
                            },
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(dialogContext, true);
                            },
                            child: const Text('Delete'),
                          ),
                        ],
                      );
                    },
                  );
                },
                onDismissed: (_) async {
                  await service.deleteAiTopic(topicId: doc.id);
                },
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.delete,
                    color: Colors.white,
                  ),
                ),
                child: Card(
                  elevation: 0,
                  color: color.withOpacity(0.10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: color.withOpacity(0.35)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(14),
                    leading: CircleAvatar(
                      backgroundColor: color.withOpacity(0.16),
                      child: const Icon(Icons.auto_awesome),
                    ),
                    title: Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        status == 'ready'
                            ? '$levelsCount levels • $questionsCount questions'
                            : status == 'failed'
                                ? 'Tap to retry generation.'
                                : 'Tap to continue preparing this topic.',
                      ),
                    ),
                    trailing: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _statusLabel(status),
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          usedFreePass ? 'Free' : '$cost coins',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                    onTap: () async {
                      if (status == 'pending_generation' ||
                          status == 'failed') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Generating topic...'),
                          ),
                        );

                        try {
                          await AiTopicService.instance.generateMockTopic(
                            topicId: doc.id,
                          );
                        } catch (e) {
                          if (!context.mounted) return;

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                e.toString().replaceFirst('Exception: ', ''),
                              ),
                            ),
                          );
                        }

                        return;
                      }

                      if (status == 'ready') {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LevelSelectScreen(
                              categoryId: doc.id,
                              categoryName: title,
                              isAiTopic: true,
                              aiTopicId: doc.id,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyAiTopics extends StatelessWidget {
  final VoidCallback onCreate;

  const _EmptyAiTopics({
    required this.onCreate,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 58),
            const SizedBox(height: 14),
            const Text(
              'Create your own trivia topic',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 23,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose any topic you like. AI-generated questions will be connected in the next step.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Create AI Topic'),
            ),
          ],
        ),
      ),
    );
  }
}
