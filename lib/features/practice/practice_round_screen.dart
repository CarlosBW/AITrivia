import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/generated/app_localizations.dart';
import '../../l10n/localized_content.dart';
import '../../services/answer_reveal.dart';
import '../../services/sfx_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_bar_title.dart';
import '../../widgets/count_pill.dart';
import '../../widgets/question_answer_card.dart';
import '../../widgets/segmented_progress.dart';

/// A round of practice questions, played entirely on the phone: what there
/// is to do with no connection.
///
/// Nothing here reaches the server. A round costs no lives and pays no
/// coins, experience or progress, and says so; the answers are judged from
/// the pack itself (see `PracticePackService`).
class PracticeRoundScreen extends StatefulWidget {
  const PracticeRoundScreen({
    super.key,
    required this.loadRound,
    required this.offline,
  });

  /// Deals the next round. Empty when the phone has no pack.
  final Future<List<Map<String, dynamic>>> Function() loadRound;

  /// Whether the phone is still without a connection, to say so when it
  /// comes back.
  final ValueListenable<bool> offline;

  @override
  State<PracticeRoundScreen> createState() => _PracticeRoundScreenState();
}

class _PracticeRoundScreenState extends State<PracticeRoundScreen> {
  static const Duration _revealDelay = Duration(milliseconds: 700);

  List<Map<String, dynamic>>? _questions;
  final List<bool> _results = [];
  int _index = 0;
  int? _selectedIndex;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _deal();
  }

  Future<void> _deal() async {
    setState(() => _questions = null);
    final questions = await widget.loadRound();
    if (!mounted) return;
    setState(() {
      _questions = questions;
      _results.clear();
      _index = 0;
      _selectedIndex = null;
      _finished = false;
    });
  }

  Future<void> _answer(int index) async {
    if (_selectedIndex != null) return;

    final correct = index == _questions![_index]['answerIndex'];
    if (correct) {
      HapticFeedback.lightImpact();
      SfxService.instance.playCorrect();
    } else {
      HapticFeedback.heavyImpact();
      SfxService.instance.playWrong();
    }

    setState(() {
      _selectedIndex = index;
      _results.add(correct);
    });

    await Future.delayed(
      answerRevealPause(correct: correct, base: _revealDelay),
    );
    if (!mounted) return;

    setState(() {
      if (_index + 1 >= _questions!.length) {
        _finished = true;
      } else {
        _index++;
        _selectedIndex = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final questions = _questions;

    return Scaffold(
      appBar: AppBar(title: AppBarTitle(l10n.practiceTitle)),
      body: SafeArea(
        child: questions == null
            ? const Center(child: CircularProgressIndicator())
            : questions.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        l10n.offlineNoPack,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : _finished
                    ? _buildResult(context, questions.length)
                    : _buildQuestion(context, questions),
      ),
    );
  }

  Widget _buildQuestion(
    BuildContext context,
    List<Map<String, dynamic>> questions,
  ) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final question = localizedQuestion(
      questions[_index],
      Localizations.localeOf(context).languageCode,
    );

    return AbsorbPointer(
      absorbing: _selectedIndex != null,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedProgress(
              results: [
                for (var i = 0; i < questions.length; i++)
                  i < _results.length ? _results[i] : null,
              ],
              current: _index,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(Icons.wifi_off_rounded,
                    size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                // One over the other: side by side they didn't fit a narrow
                // phone with large text.
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.practiceBadge,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.levelPlayQuestionOfTotal(
                          _index + 1,
                          questions.length,
                        ),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            QuestionAnswerCard(
              qText: question.text,
              options: question.options,
              answerIndex: _selectedIndex == null
                  ? -1
                  : questions[_index]['answerIndex'] as int,
              selectedIndex: _selectedIndex,
              locked: _selectedIndex != null,
              onTapAnswer: _answer,
            ),
            const SizedBox(height: 12),
            Center(
              child: CountPill(
                icon: Icons.check_circle_rounded,
                label:
                    l10n.playCorrectCount(_results.where((r) => r).length),
                color: context.appColors.success,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(BuildContext context, int total) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final correct = _results.where((r) => r).length;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.practiceResultTitle,
              textAlign: TextAlign.center,
              style: context.heading(26),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.practiceResultScore(correct, total),
              textAlign: TextAlign.center,
              style: context.heading(
                20,
                color: readableInk(context.appColors.success, scheme.surface),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.practiceResultNote,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            ValueListenableBuilder<bool>(
              valueListenable: widget.offline,
              builder: (context, offline, _) {
                // Back online, the way out comes first: the game proper is
                // what they came for.
                final again = offline
                    ? FilledButton(
                        onPressed: _deal,
                        child: Text(l10n.practiceAgain),
                      )
                    : OutlinedButton(
                        onPressed: _deal,
                        child: Text(l10n.practiceAgain),
                      );
                final leave = offline
                    ? OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(l10n.practiceExit),
                      )
                    : FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(l10n.practiceBackToGame),
                      );
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!offline) ...[
                      Text(
                        l10n.practiceBackOnline,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      leave,
                      const SizedBox(height: 8),
                      again,
                    ] else ...[
                      again,
                      const SizedBox(height: 8),
                      leave,
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
