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

  @override
  Widget build(BuildContext context) {
    final hasOpponentScore = opponentScore != null;
    final hasRatingChange =
        oldRating != null && newRating != null && ratingDelta != null;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: _color.withOpacity(0.16),
                shape: BoxShape.circle,
                border: Border.all(color: _color.withOpacity(0.55), width: 2),
              ),
              child: Icon(_icon, size: 48, color: _color),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 28,
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
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.black12),
              ),
              child: Column(
                children: [
                  const Text(
                    'Resultado',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _ScoreColumn(
                          label: myName,
                          score: myScore,
                          highlight: true,
                        ),
                      ),
                      Text(
                        hasOpponentScore ? 'VS' : '',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.black54,
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
              child: FilledButton(
                onPressed: onPrimaryPressed,
                child: Text(primaryButtonText),
              ),
            ),
            if (secondaryButtonText != null && onSecondaryPressed != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
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
    return Column(
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
            color: highlight ? Colors.deepPurple : Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$score',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.bold,
            color: highlight ? Colors.deepPurple : Colors.black87,
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
        color: Colors.white.withOpacity(0.65),
        borderRadius: BorderRadius.circular(16),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(positive ? Icons.trending_up : Icons.trending_down, color: color),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Ranked rating',
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
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$oldRating MMR'),
              const Icon(Icons.arrow_forward, size: 18),
              Text(
                '$newRating MMR',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          if (hasLeague) ...[
            const SizedBox(height: 8),
            Text(
              oldLeagueName != null &&
                      newLeagueName != null &&
                      oldLeagueName != newLeagueName
                  ? '$oldLeagueName → $newLeagueName'
                  : (newLeagueName ?? oldLeagueName ?? ''),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
          if (winStreak != null && winStreak! > 1) ...[
            const SizedBox(height: 8),
            Text(
              'Racha actual: $winStreak victorias',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}
