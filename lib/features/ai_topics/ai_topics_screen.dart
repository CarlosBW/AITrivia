import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/ai_topic_service.dart';
import '../../services/economy_service.dart';
import 'create_ai_topic_screen.dart';
import '../solo/level_select_screen.dart';
import '../../l10n/generated/app_localizations.dart';

class AiTopicsScreen extends StatelessWidget {
  const AiTopicsScreen({super.key});

  Color _statusColor(String status) {
    switch (status) {
      case 'ready':
        return Colors.green;
      case 'failed':
      case 'invalid':
      case 'blocked':
        return Colors.redAccent;
      case 'deleted':
        return Colors.grey;
      case 'pending_generation':
      default:
        return Colors.orange;
    }
  }

  String _statusLabel(AppLocalizations l10n, String status) {
    switch (status) {
      case 'ready':
        return l10n.aiTopicsStatusReady;
      case 'failed':
        return l10n.aiTopicsStatusFailed;
      case 'deleted':
        return l10n.aiTopicsStatusDeleted;
      case 'invalid':
        return l10n.aiTopicsStatusInvalid;
      case 'blocked':
        return l10n.aiTopicsStatusBlocked;
      case 'pending_generation':
      default:
        return l10n.aiTopicsStatusPreparing;
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

  Widget _statusCostColumn({
    required AppLocalizations l10n,
    required Color color,
    required String status,
    required bool usedFreePass,
    required int cost,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          _statusLabel(l10n, status),
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          usedFreePass ? l10n.aiTopicsFree : l10n.aiTopicsCoinsCost(cost),
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Future<void> _confirmAndRun({
    required BuildContext context,
    required AppLocalizations l10n,
    required String title,
    required String message,
    required Future<void> Function() action,
    required String successMessage,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.aiTopicsCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.aiTopicsConfirm),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await action();

      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
    } catch (e) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  Future<void> _onTopicMenuAction({
    required BuildContext context,
    required String action,
    required String topicId,
    required String topicTitle,
    required int generatedLevels,
  }) async {
    final uid = AiTopicService.instance.uid;
    final userSnap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final coins = ((userSnap.data()?['coins'] ?? 0) as num).toInt();

    if (!context.mounted) return;

    final l10n = AppLocalizations.of(context);

    if (action == 'regenerate') {
      final regenerateCost =
          EconomyService.regenerateAiQuestionsCostFor(generatedLevels);

      await _confirmAndRun(
        context: context,
        l10n: l10n,
        title: l10n.aiTopicsRegenerateDialogTitle,
        message: l10n.aiTopicsRegenerateDialogBody(
          topicTitle,
          regenerateCost,
          coins,
        ),
        action: () => AiTopicService.instance.regenerateTopicQuestions(
          topicId: topicId,
        ),
        successMessage: l10n.aiTopicsRegenerateSuccess,
      );
    } else if (action == 'expand') {
      await _confirmAndRun(
        context: context,
        l10n: l10n,
        title: l10n.aiTopicsExpandDialogTitle,
        message: l10n.aiTopicsExpandDialogBody(
          topicTitle,
          EconomyService.expandAiTopicCost,
          coins,
        ),
        action: () => AiTopicService.instance.expandTopic(topicId: topicId),
        successMessage: l10n.aiTopicsExpandSuccess,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = AiTopicService.instance;
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.aiTopicsTitle),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreate(context),
        icon: const Icon(Icons.add),
        label: Text(l10n.aiTopicsCreateTopic),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: service.watchMyAiTopics(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.aiTopicsErrorLoading(snap.error.toString()),
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

              final title = (data['title'] ?? l10n.aiTopicsUntitled).toString();
              final rawStatus =
                  (data['status'] ?? 'pending_generation').toString();

              final isInvalidReadyTopic = rawStatus == 'ready' &&
                  !AiTopicService.instance.isTopicStructurallyValid(data);

              final status = isInvalidReadyTopic ? 'invalid' : rawStatus;
              final levelsCount = ((data['levelsCount'] ?? 0) as num).toInt();
              final questionsCount =
                  ((data['questionsCount'] ?? 0) as num).toInt();
              final generatedLevels =
                  ((data['generatedLevels'] ?? 0) as num).toInt();
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
                        title: Text(l10n.aiTopicsDeleteTitle),
                        content: Text(
                          l10n.aiTopicsDeleteBody(title),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(dialogContext, false);
                            },
                            child: Text(l10n.aiTopicsCancel),
                          ),
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(dialogContext, true);
                            },
                            child: Text(l10n.aiTopicsDelete),
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
                    color: Colors.redAccent.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.delete,
                    color: Colors.white,
                  ),
                ),
                child: Card(
                  elevation: 0,
                  color: color.withValues(alpha: 0.10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                    side: BorderSide(color: color.withValues(alpha: 0.35)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(14),
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.16),
                      child: Icon(Icons.auto_awesome, color: color),
                    ),
                    title: Text(
                      title,
                      style: GoogleFonts.baloo2(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(status == 'ready'
                          ? l10n.aiTopicsLevelsQuestions(levelsCount, questionsCount)
                          : l10n.aiTopicsUnavailableSubtitle),
                    ),
                    trailing: status == 'ready'
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _statusCostColumn(
                                l10n: l10n,
                                color: color,
                                status: status,
                                usedFreePass: usedFreePass,
                                cost: cost,
                              ),
                              PopupMenuButton<String>(
                                onSelected: (action) => _onTopicMenuAction(
                                  context: context,
                                  action: action,
                                  topicId: doc.id,
                                  topicTitle: title,
                                  generatedLevels: generatedLevels,
                                ),
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'regenerate',
                                    child: Text(
                                      l10n.aiTopicsRegenerateMenuItem(
                                        EconomyService
                                            .regenerateAiQuestionsCostFor(
                                          generatedLevels,
                                        ),
                                      ),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'expand',
                                    child: Text(
                                      l10n.aiTopicsExpandMenuItem(
                                        EconomyService.expandAiTopicCost,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : _statusCostColumn(
                            l10n: l10n,
                            color: color,
                            status: status,
                            usedFreePass: usedFreePass,
                            cost: cost,
                          ),
                    onTap: () async {
                      if (status != 'ready') {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(l10n.aiTopicsUnavailableSubtitle),
                          ),
                        );
                        return;
                      }

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
    final l10n = AppLocalizations.of(context);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 58),
            const SizedBox(height: 14),
            Text(
              l10n.aiTopicsEmptyTitle,
              textAlign: TextAlign.center,
              style: GoogleFonts.baloo2(
                fontSize: 23,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.aiTopicsEmptySubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: Text(l10n.aiTopicsEmptyButton),
            ),
          ],
        ),
      ),
    );
  }
}
