import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Gradient question card + lettered answer list, shared by Solo and Daily
/// Challenge so both quiz flows stay visually identical.
class QuestionAnswerCard extends StatelessWidget {
  final String qText;
  final List<String> options;
  final int answerIndex;
  final int? selectedIndex;
  final bool locked;
  final bool timedOut;
  final int? timeoutAnswerIndex;
  final void Function(int index) onTapAnswer;

  const QuestionAnswerCard({
    super.key,
    required this.qText,
    required this.options,
    required this.answerIndex,
    required this.selectedIndex,
    required this.locked,
    required this.onTapAnswer,
    this.timedOut = false,
    this.timeoutAnswerIndex,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF8A6BFF), Color(0xFFFF5C93)],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            qText,
            style: const TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              height: 1.35,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 20),
        ...List.generate(options.length, (i) {
          final isSelected = selectedIndex == i;
          final isCorrect = i == answerIndex;
          final letter = String.fromCharCode(65 + i);

          Color? fillColor;
          if (locked && !timedOut) {
            if (isCorrect) fillColor = AppColors.success.withValues(alpha: 0.16);
            if (isSelected && !isCorrect) {
              fillColor = AppColors.danger.withValues(alpha: 0.16);
            }
          } else if (!locked && isSelected) {
            fillColor = colorScheme.surfaceContainerHighest;
          }

          Color borderColor = colorScheme.outline;
          double borderWidth = 1;

          if (timedOut && timeoutAnswerIndex != null) {
            if (i == timeoutAnswerIndex) {
              borderColor = AppColors.reward;
              borderWidth = 3;
            }
          } else if (locked) {
            if (isCorrect) {
              borderColor = AppColors.success;
              borderWidth = 2;
            }
            if (isSelected && !isCorrect) {
              borderColor = AppColors.danger;
              borderWidth = 2;
            }
          } else if (isSelected) {
            borderColor = colorScheme.primary;
            borderWidth = 2;
          }

          final badgeColor = (locked && isCorrect)
              ? AppColors.success
              : (locked && isSelected && !isCorrect)
                  ? AppColors.danger
                  : (!locked && isSelected)
                      ? colorScheme.primary
                      : colorScheme.surfaceContainerHighest;

          final badgeTextColor = badgeColor == colorScheme.surfaceContainerHighest
              ? colorScheme.onSurfaceVariant
              : Colors.white;

          IconData? trailingIcon;
          Color? trailingIconColor;
          if (locked && !timedOut) {
            if (isCorrect) {
              trailingIcon = Icons.check_circle;
              trailingIconColor = AppColors.success;
            } else if (isSelected) {
              trailingIcon = Icons.cancel;
              trailingIconColor = AppColors.danger;
            }
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => onTapAnswer(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                // A BoxDecoration border adds to the box's size rather than
                // being drawn over it, so thickening it on selection made
                // the card grow and pushed everything below it down — an
                // animated shove, since AnimatedContainer tweens the change.
                // Padding absorbs the extra width so the outer size is
                // constant (14 + 1 == 13 + 2 == 12 + 3) and only the border
                // itself appears to change.
                padding: EdgeInsets.all(15 - borderWidth),
                decoration: BoxDecoration(
                  color: fillColor ?? colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: borderColor,
                    width: borderWidth,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: badgeColor,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        letter,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: badgeTextColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        options[i],
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (trailingIcon != null) ...[
                      const SizedBox(width: 8),
                      Icon(trailingIcon, color: trailingIconColor),
                    ],
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
