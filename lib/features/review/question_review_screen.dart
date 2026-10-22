import 'package:flutter/material.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../l10n/user_facing_error.dart';
import '../../services/question_report_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bar_title.dart';

/// The questions of a finished round, with the right answer and the
/// player's own, and a way to report any that was wrong.
///
/// Opened from the end of a Solo level, a Daily Challenge or a Weekly Topic
/// round. Reporting from here rather than mid-question: the player has
/// time to think, and the clock is not running.
class QuestionReviewScreen extends StatefulWidget {
  final List<ReviewedQuestion> questions;

  const QuestionReviewScreen({super.key, required this.questions});

  @override
  State<QuestionReviewScreen> createState() => _QuestionReviewScreenState();
}

class _QuestionReviewScreenState extends State<QuestionReviewScreen> {
  final Set<int> _reported = {};
  int? _sending;

  Future<void> _report(int index) async {
    final choice = await showModalBottomSheet<_ReportChoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ReportSheet(),
    );
    if (choice == null || !mounted) return;

    setState(() => _sending = index);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);

    try {
      await QuestionReportService.instance.report(
        target: widget.questions[index].reportTarget,
        reason: choice.reason,
        details: choice.details,
      );
      if (!mounted) return;
      setState(() => _reported.add(index));
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.questionReportSent)),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(userFacingError(l10n, e))),
      );
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: AppBarTitle(l10n.questionReviewButton)),
      body: widget.questions.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.questionReviewEmpty,
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: widget.questions.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Text(
                    l10n.questionReviewHint,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  );
                }
                final index = i - 1;
                return _ReviewCard(
                  number: index + 1,
                  question: widget.questions[index],
                  reported: _reported.contains(index),
                  sending: _sending == index,
                  onReport: _sending == null ? () => _report(index) : null,
                );
              },
            ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final int number;
  final ReviewedQuestion question;
  final bool reported;
  final bool sending;
  final VoidCallback? onReport;

  const _ReviewCard({
    required this.number,
    required this.question,
    required this.reported,
    required this.sending,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.appColors;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.questionReviewNumber(number),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    question.text,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (var o = 0; o < question.options.length; o++)
                    _OptionRow(
                      text: question.options[o],
                      isCorrect: o == question.correctIndex,
                      isPicked: o == question.selectedIndex,
                      correctColor: colors.success,
                      wrongColor: colors.danger,
                    ),
                  if (question.selectedIndex == null) ...[
                    const SizedBox(height: 4),
                    Text(
                      l10n.questionReviewUnanswered,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: reported
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check, size: 18, color: colors.success),
                          const SizedBox(width: 6),
                          Text(l10n.questionReviewReported),
                        ],
                      ),
                    )
                  : TextButton.icon(
                      onPressed: onReport,
                      icon: sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.flag_outlined, size: 18),
                      label: Text(l10n.questionReviewReport),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  final String text;
  final bool isCorrect;
  final bool isPicked;
  final Color correctColor;
  final Color wrongColor;

  const _OptionRow({
    required this.text,
    required this.isCorrect,
    required this.isPicked,
    required this.correctColor,
    required this.wrongColor,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;

    final Color? accent = isCorrect
        ? correctColor
        : isPicked
            ? wrongColor
            : null;
    final IconData icon = isCorrect
        ? Icons.check_circle
        : isPicked
            ? Icons.cancel
            : Icons.circle_outlined;

    // Labelled in words too, not only by color.
    final String? tag = isCorrect && isPicked
        ? '${l10n.questionReviewYourAnswer} · ${l10n.questionReviewCorrect}'
        : isCorrect
            ? l10n.questionReviewCorrect
            : isPicked
                ? l10n.questionReviewYourAnswer
                : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              icon,
              size: 20,
              color: accent ?? scheme.outline,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  style: TextStyle(
                    fontWeight:
                        accent != null ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (tag != null)
                  Text(
                    tag,
                    style: TextStyle(
                      fontSize: 12,
                      color: readableInk(accent!, scheme.surface),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportChoice {
  final String reason;
  final String details;

  const _ReportChoice(this.reason, this.details);
}

/// Picks why a question is being reported, with an optional comment.
class _ReportSheet extends StatefulWidget {
  const _ReportSheet();

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String _reason = QuestionReportService.reasons.first;
  final TextEditingController _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  String _label(AppLocalizations l10n, String reason) {
    switch (reason) {
      case 'wrong_answer':
        return l10n.questionReportReasonWrongAnswer;
      case 'confusing':
        return l10n.questionReportReasonConfusing;
      case 'typo':
        return l10n.questionReportReasonTypo;
      case 'inappropriate':
        return l10n.questionReportReasonInappropriate;
      default:
        return l10n.questionReportReasonOther;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return SafeArea(
      child: Padding(
        // Keeps the comment field above the keyboard.
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(l10n.questionReportDialogTitle, style: context.heading(18)),
              const SizedBox(height: 8),
              RadioGroup<String>(
                groupValue: _reason,
                onChanged: (v) => setState(() => _reason = v ?? _reason),
                child: Column(
                  children: [
                    for (final reason in QuestionReportService.reasons)
                      RadioListTile<String>(
                        value: reason,
                        contentPadding: EdgeInsets.zero,
                        title: Text(_label(l10n, reason)),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _details,
                maxLength: 200,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: l10n.questionReportDetailsHint,
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  _ReportChoice(_reason, _details.text),
                ),
                child: Text(l10n.questionReportSubmit),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
