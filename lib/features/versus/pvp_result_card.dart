import 'package:flutter/material.dart';

enum PvpResultState {
  victory,
  defeat,
  draw,
  waiting,
}

class PvpResultCard extends StatelessWidget {
  final PvpResultState state;
  final String title;
  final String subtitle;

  final String myName;
  final String opponentName;
  final int myScore;
  final int? opponentScore;

  final int? coinsEarned;
  final int? xpEarned;

  final int? oldRating;
  final int? newRating;
  final int? ratingDelta;
  final int? winStreak;
  final String? oldLeagueName;
  final String? newLeagueName;

  final String primaryButtonText;
  final VoidCallback onPrimaryPressed;

  final String? secondaryButtonText;
  final VoidCallback? onSecondaryPressed;

  const PvpResultCard({
    super.key,
    required this.state,
    required this.title,
    required this.subtitle,
    required this.myName,
    required this.opponentName,
    required this.myScore,
    this.opponentScore,
    this.coinsEarned,
    this.xpEarned,
    this.oldRating,
    this.newRating,
    this.ratingDelta,
    this.winStreak,
    this.oldLeagueName,
    this.newLeagueName,
    required this.primaryButtonText,
    required this.onPrimaryPressed,
    this.secondaryButtonText,
    this.onSecondaryPressed,
  });

  IconData get _icon {
    switch (state) {
      case PvpResultState.victory:
        return Icons.emoji_events;
      case PvpResultState.defeat:
        return Icons.sentiment_dissatisfied;
      case PvpResultState.draw:
        return Icons.handshake;
      case PvpResultState.waiting:
        return Icons.hourglass_bottom;
    }
  }

  Color get _color {
    switch (state) {
      case PvpResultState.victory:
        return Colors.amber;
      case PvpResultState.defeat:
        return Colors.redAccent;
      case PvpResultState.draw:
        return Colors.blueGrey;
      case PvpResultState.waiting:
        return Colors.deepPurple;
    }
  }

  String get _scoreDifferenceText {
    if (opponentScore == null) return '';

    final diff = myScore - opponentScore!;

    if (diff == 0) return 'Empate perfecto';
    if (diff > 0) return 'Ganaste por +$diff puntos';
    return 'Perdiste por ${diff.abs()} puntos';
  }

  int get _accuracy {
    if (myScore <= 0) return 0;

    final total = myScore > (opponentScore ?? 0) ? myScore : (opponentScore ?? myScore);

    if (total <= 0) return 0;

    return ((myScore / total) * 100).round().clamp(0, 100);
  }

  @override
  Widget build(BuildContext context) {
    final hasOpponentScore = opponentScore != null;
    final hasRatingChange =
        oldRating != null && newRating != null && ratingDelta != null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: _color.withOpacity(0.16),
                shape: BoxShape.circle,
                border: Border.all(
                  color: _color.withOpacity(0.55),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _color.withOpacity(0.22),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(
                _icon,
                size: 52,
                color: _color,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: Colors.black.withOpacity(0.68),
              ),
            ),
            if (_scoreDifferenceText.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: _color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _color.withOpacity(0.35),
                  ),
                ),
                child: Text(
                  _scoreDifferenceText,
                  style: TextStyle(
                    color: _color,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.06),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.black.withOpacity(0.08),
                ),
              ),
              child: Column(
                children: [
                  const Text(
                    'Resultado final',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: _ScoreColumn(
                          label: myName,
                          score: myScore,
                          highlight: true,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'VS',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.black54,
                          ),
                        ),
                      ),
                      Expanded(
                        child: hasOpponentScore
                            ? _ScoreColumn(
                                label: opponentName,
                                score: opponentScore!,
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _MatchSummaryCard(
                    myScore: myScore,
                    opponentScore: opponentScore,
                    accuracy: _accuracy,
                  ),
                  if (coinsEarned != null || xpEarned != null) ...[
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        if (xpEarned != null)
                          Expanded(
                            child: _RewardMiniCard(
                              icon: Icons.auto_awesome,
                              label: 'XP',
                              value: '+$xpEarned',
                            ),
                          ),
                        if (xpEarned != null && coinsEarned != null)
                          const SizedBox(width: 12),
                        if (coinsEarned != null)
                          Expanded(
                            child: _RewardMiniCard(
                              icon: Icons.monetization_on,
                              label: 'Monedas',
                              value: '+$coinsEarned',
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (hasRatingChange) ...[
                    const SizedBox(height: 18),
                    _RatingChangeCard(
                      oldRating: oldRating!,
                      newRating: newRating!,
                      ratingDelta: ratingDelta!,
                      winStreak: winStreak,
                      oldLeagueName: oldLeagueName,
                      newLeagueName: newLeagueName,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 26),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: onPrimaryPressed,
                child: Text(primaryButtonText),
              ),
            ),
            if (secondaryButtonText != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: onSecondaryPressed,
                  child: Text(secondaryButtonText!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScoreColumn extends StatelessWidget {
  final String label;
  final int score;
  final bool highlight;

  const _ScoreColumn({
    required this.label,
    required this.score,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = highlight ? Colors.deepPurple : Colors.black87;

    return Column(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
            color: color,
          ),
        ),
        const SizedBox(height: 6),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          child: Text(
            '$score',
            key: ValueKey(score),
            style: TextStyle(
              fontSize: 38,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _MatchSummaryCard extends StatelessWidget {
  final int myScore;
  final int? opponentScore;
  final int accuracy;

  const _MatchSummaryCard({
    required this.myScore,
    required this.opponentScore,
    required this.accuracy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.70),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Icon(Icons.analytics_outlined, size: 20),
              SizedBox(width: 8),
              Text(
                'Resumen del match',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SummaryItem(
                  label: 'Tu score',
                  value: '$myScore',
                ),
              ),
              Expanded(
                child: _SummaryItem(
                  label: 'Rival',
                  value: opponentScore == null ? '—' : '$opponentScore',
                ),
              ),
              Expanded(
                child: _SummaryItem(
                  label: 'Rendimiento',
                  value: '$accuracy%',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final String label;
  final String value;

  const _SummaryItem({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }
}

class _RewardMiniCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _RewardMiniCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.70),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          Icon(icon),
          const SizedBox(height: 6),
          Text(label),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
        ],
      ),
    );
  }
}

class _RatingChangeCard extends StatelessWidget {
  final int oldRating;
  final int newRating;
  final int ratingDelta;
  final int? winStreak;
  final String? oldLeagueName;
  final String? newLeagueName;

  const _RatingChangeCard({
    required this.oldRating,
    required this.newRating,
    required this.ratingDelta,
    this.winStreak,
    this.oldLeagueName,
    this.newLeagueName,
  });

  String get _deltaText {
    if (ratingDelta > 0) return '+$ratingDelta';
    return '$ratingDelta';
  }

  @override
  Widget build(BuildContext context) {
    final positive = ratingDelta > 0;
    final neutral = ratingDelta == 0;

    final color = neutral
        ? Colors.blueGrey
        : positive
            ? Colors.green
            : Colors.redAccent;

    final hasLeague = (oldLeagueName != null && oldLeagueName!.isNotEmpty) ||
        (newLeagueName != null && newLeagueName!.isNotEmpty);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color.withOpacity(0.35),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                positive
                    ? Icons.trending_up
                    : neutral
                        ? Icons.remove_circle_outline
                        : Icons.trending_down,
                color: color,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Ranked MMR',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              Text(
                _deltaText,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MmrBox(
                  label: 'Antes',
                  value: oldRating,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.arrow_forward, size: 20),
              ),
              Expanded(
                child: _MmrBox(
                  label: 'Ahora',
                  value: newRating,
                  highlight: true,
                ),
              ),
            ],
          ),
          if (hasLeague) ...[
            const SizedBox(height: 10),
            Text(
              oldLeagueName != null &&
                      newLeagueName != null &&
                      oldLeagueName != newLeagueName
                  ? '$oldLeagueName → $newLeagueName'
                  : (newLeagueName ?? oldLeagueName ?? ''),
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (winStreak != null && winStreak! > 1) ...[
            const SizedBox(height: 8),
            Text(
              '🔥 Racha actual: $winStreak victorias',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MmrBox extends StatelessWidget {
  final String label;
  final int value;
  final bool highlight;

  const _MmrBox({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 10,
        horizontal: 8,
      ),
      decoration: BoxDecoration(
        color: highlight ? Colors.white.withOpacity(0.85) : Colors.white54,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$value',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: highlight ? 18 : 16,
            ),
          ),
        ],
      ),
    );
  }
}