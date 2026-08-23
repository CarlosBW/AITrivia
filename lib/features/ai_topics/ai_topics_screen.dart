import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/ai_topic_service.dart';
import '../../services/economy_service.dart';
import 'create_ai_topic_screen.dart';
import '../solo/level_select_screen.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../theme/app_theme.dart';

class AiTopicsScreen extends StatefulWidget {
  const AiTopicsScreen({super.key});

  @override
  State<AiTopicsScreen> createState() => _AiTopicsScreenState();
}

// Stateful only to hold the topics stream: creating it inside `build()` tore
// it down and re-subscribed on every rebuild, and creating/expanding a topic
// rebuilds this screen.
class _AiTopicsScreenState extends State<AiTopicsScreen> {
  late final _myTopics = AiTopicService.instance.watchMyAiTopics();

  Color _statusColor(String status) {
    switch (status) {
      case 'ready':
        return context.appColors.success;
      case 'failed':
      case 'invalid':
      case 'blocked':
        return context.appColors.danger;
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
      // Priced server-side: levels already at the question-bank cap aren't
      // charged for, so computing this from generatedLevels here would
      // quote more than the player gets charged — and would happily offer
      // a purchase that can only fail once every level is full.
      final AiTopicRegenerateQuote quote;
      try {
        quote = await AiTopicService.instance.getRegenerateQuote(
          topicId: topicId,
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
          ),
        );
        return;
      }

      if (!context.mounted) return;

      if (!quote.available) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              quote.allFull
                  ? l10n.aiTopicsRegenerateAllFull
                  : l10n.aiTopicsUnavailableSubtitle,
            ),
          ),
        );
        return;
      }

      await _confirmAndRun(
        context: context,
        l10n: l10n,
        title: l10n.aiTopicsRegenerateDialogTitle,
        message: l10n.aiTopicsRegenerateDialogBody(
          topicTitle,
          quote.cost,
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

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _myTopics,
      builder: (context, snap) {
        final docs = snap.hasData
            ? snap.data!.docs
                .where((doc) => (doc.data()['status'] ?? '') != 'deleted')
                .toList()
            : const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        // The confirmed-empty state already shows its own big "create"
        // button, so the FAB would just be a second, redundant way to do
        // the same thing there. Every other state (still loading, errored)
        // has no such button, so the FAB must stay as the only way in —
        // hide it only once we positively know the list is empty.
        final showFab = !(snap.hasData && docs.isEmpty);

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.aiTopicsTitle),
            actions: const [ProfileAvatarButton()],
          ),
          floatingActionButton: showFab
              // The default surface-tinted FAB washed out against this
              // screen's pale background — it read as disabled next to the
              // topic cards. Same purple gradient the app uses for its
              // other primary actions, so "create" is unmistakably the
              // thing to press here.
              ? Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF6C4FF2), Color(0xFF8A6BFF)],
                    ),
                    borderRadius: BorderRadius.circular(context.radii.md),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF6C4FF2).withValues(alpha: 0.45),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: FloatingActionButton.extended(
                    onPressed: () => _openCreate(context),
                    backgroundColor: Colors.transparent,
                    foregroundColor: context.appColors.onAccent,
                    elevation: 0,
                    highlightElevation: 0,
                    icon: const Icon(Icons.auto_awesome),
                    label: Text(
                      l10n.aiTopicsCreateTopic,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                )
              : null,
          body: Builder(
            builder: (context) {
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

                  final title =
                      (data['title'] ?? l10n.aiTopicsUntitled).toString();
                  final rawStatus =
                      (data['status'] ?? 'pending_generation').toString();

                  final isInvalidReadyTopic = rawStatus == 'ready' &&
                      !AiTopicService.instance.isTopicStructurallyValid(data);

                  final status = isInvalidReadyTopic ? 'invalid' : rawStatus;
                  final levelsCount =
                      ((data['levelsCount'] ?? 0) as num).toInt();
                  final questionsCount =
                      ((data['questionsCount'] ?? 0) as num).toInt();
                  final generatedLevels =
                      ((data['generatedLevels'] ?? 0) as num).toInt();
                  final usedFreePass = data['usedFreePass'] == true;
                  final cost =
                      ((data['generationCostCoins'] ?? 0) as num).toInt();

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
                        borderRadius: BorderRadius.circular(context.radii.md),
                      ),
                      child: Icon(
                        Icons.delete,
                        color: context.appColors.onAccent,
                      ),
                    ),
                    child: Card(
                      elevation: 0,
                      color: color.withValues(alpha: 0.10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(context.radii.md),
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
                          style:
                              context.headingFace,
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(status == 'ready'
                              ? l10n.aiTopicsLevelsQuestions(
                                  levelsCount, questionsCount)
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
                                      // No price here: it depends on how
                                      // many levels still have room in
                                      // their question bank, which only
                                      // the server knows. The exact cost
                                      // is quoted in the confirmation
                                      // dialog after tapping.
                                      PopupMenuItem(
                                        value: 'regenerate',
                                        child: Text(
                                          l10n.aiTopicsRegenerateMenuItemPlain,
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
      },
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
              style: context.heading(23),
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
