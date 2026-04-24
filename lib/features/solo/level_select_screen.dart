import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/life_service.dart';
import 'level_play_screen.dart';

class LevelSelectScreen extends StatefulWidget {
  final String categoryId;
  final String categoryName;

  const LevelSelectScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  @override
  State<LevelSelectScreen> createState() => _LevelSelectScreenState();
}

class _LevelSelectScreenState extends State<LevelSelectScreen> {
  bool _isNavigating = false;

  String _formatCountdown(int? totalSeconds) {
    if (totalSeconds == null) return '--:--';
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _showNoLivesDialog({
    required BuildContext context,
    required String uid,
    required int lifeUnits,
    required int maxLifeUnits,
    required int? secondsToNextHalfLife,
  }) async {
    final currentLivesText =
        '${LifeService.instance.formatLives(lifeUnits)} / ${LifeService.instance.formatLives(maxLifeUnits)}';

    final nextHalfLifeText = secondsToNextHalfLife == null
        ? '--:--'
        : _formatCountdown(secondsToNextHalfLife);

    final needOneMoreHalf = lifeUnits == 1;
    final secondsToFullLife = secondsToNextHalfLife == null
        ? null
        : needOneMoreHalf
            ? secondsToNextHalfLife
            : secondsToNextHalfLife + 150;

    final nextFullLifeText = secondsToFullLife == null
        ? '--:--'
        : _formatCountdown(secondsToFullLife);

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _NoLivesDialog(
        currentLivesText: currentLivesText,
        nextHalfLifeText: nextHalfLifeText,
        nextFullLifeText: nextFullLifeText,
        cost: 10,
        onBuyLife: () async {
          Navigator.pop(context);

          final success = await LifeService.instance.buyFullLife(
            uid: uid,
            cost: 10,
          );

          if (!mounted) return;

          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('❤️ Vida recuperada')),
            );
            setState(() {});
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('❌ No tienes suficientes monedas'),
              ),
            );
          }
        },
      ),
    );
  }

  Future<bool> _ensureHasLives(BuildContext context, String uid) async {
    await LifeService.instance.ensureUserLifeDoc(uid);
    final lifeState = await LifeService.instance.refreshLives(uid);

    final lifeUnits = (lifeState['lifeUnits'] ?? 0) as int;
    final maxLifeUnits = (lifeState['maxLifeUnits'] ?? 10) as int;
    final secondsToNextHalfLife =
        lifeState['secondsToNextHalfLife'] as int?;

    if (lifeUnits < 2) {
      if (!context.mounted) return false;

      await _showNoLivesDialog(
        context: context,
        uid: uid,
        lifeUnits: lifeUnits,
        maxLifeUnits: maxLifeUnits,
        secondsToNextHalfLife: secondsToNextHalfLife,
      );

      return false;
    }

    return true;
  }

  Future<void> _safeNavigate(Future<void> Function() action) async {
    if (_isNavigating) return;

    setState(() => _isNavigating = true);

    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _isNavigating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final categoryRef =
        db.collection('fixed_categories').doc(widget.categoryId);
    final progressRef = db
        .collection('users')
        .doc(uid)
        .collection('progress_fixed')
        .doc(widget.categoryId);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.categoryName),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: categoryRef.snapshots(),
            builder: (context, categorySnap) {
              if (!categorySnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final categoryData = categorySnap.data!.data() ?? {};
              final levelCount = (categoryData['levelCount'] ?? 10) as int;

              return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: progressRef.snapshots(),
                builder: (context, progressSnap) {
                  if (progressSnap.connectionState == ConnectionState.waiting &&
                      !progressSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final progressData = progressSnap.data?.data() ?? {};

                  final completedLevels =
                      (progressData['completedLevels'] as List<dynamic>? ?? [])
                          .map((e) => (e as num).toInt())
                          .toSet();

                  final levelStats = Map<String, dynamic>.from(
                    progressData['levelStats'] as Map? ?? {},
                  );

                  int maxUnlocked = 1;
                  if (completedLevels.isNotEmpty) {
                    final highestCompleted = completedLevels.reduce(
                      (a, b) => a > b ? a : b,
                    );
                    maxUnlocked = highestCompleted + 1;
                  }
                  if (maxUnlocked > levelCount) {
                    maxUnlocked = levelCount;
                  }

                  final completedCount = completedLevels.length;
                  final progress = levelCount == 0
                      ? 0.0
                      : (completedCount / levelCount).clamp(0.0, 1.0);

                  final completedAll =
                      progressData['completedAllLevels'] == true ||
                          completedCount >= levelCount;

                  final recommendedLevel =
                      completedAll ? levelCount : maxUnlocked;

                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Selecciona un nivel',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                completedAll
                                    ? 'Categoría completada'
                                    : 'Tu progreso en esta categoría',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Completados: $completedCount / $levelCount',
                                style: const TextStyle(fontSize: 15),
                              ),
                              const SizedBox(height: 10),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 10,
                                ),
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _isNavigating
                                      ? null
                                      : () {
                                          _safeNavigate(() async {
                                            final canPlay =
                                                await _ensureHasLives(
                                              context,
                                              uid,
                                            );
                                            if (!canPlay) return;

                                            if (!context.mounted) return;
                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => LevelPlayScreen(
                                                  categoryId: widget.categoryId,
                                                  levelNumber: recommendedLevel,
                                                ),
                                              ),
                                            );
                                          });
                                        },
                                  icon: Icon(
                                    completedAll
                                        ? Icons.replay
                                        : Icons.play_arrow,
                                  ),
                                  label: Text(
                                    completedAll
                                        ? 'Jugar último nivel'
                                        : 'Continuar en nivel $recommendedLevel',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        Expanded(
                          child: GridView.builder(
                            itemCount: levelCount,
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.92,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemBuilder: (context, index) {
                              final level = index + 1;
                              final isCompleted =
                                  completedLevels.contains(level);
                              final isUnlocked = level <= maxUnlocked;

                              final stars = _starsForLevel(
                                level: level,
                                isCompleted: isCompleted,
                                levelStats: levelStats,
                              );

                              Color tileColor;
                              IconData icon;
                              String subtitle;

                              if (isCompleted) {
                                tileColor = Colors.green.withOpacity(0.15);
                                icon = Icons.check_circle;
                                subtitle = 'Completado';
                              } else if (isUnlocked) {
                                tileColor = Colors.blue.withOpacity(0.12);
                                icon = Icons.play_circle_fill;
                                subtitle = 'Disponible';
                              } else {
                                tileColor = Colors.black12;
                                icon = Icons.lock;
                                subtitle = 'Bloqueado';
                              }

                              final showRecommended =
                                  level == recommendedLevel && !completedAll;

                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOut,
                                decoration: BoxDecoration(
                                  color: tileColor,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: showRecommended
                                        ? Colors.blueAccent
                                        : Colors.black12,
                                    width: showRecommended ? 2 : 1,
                                  ),
                                  boxShadow: showRecommended
                                      ? [
                                          BoxShadow(
                                            color: Colors.blue.withOpacity(0.08),
                                            blurRadius: 12,
                                            offset: const Offset(0, 4),
                                          ),
                                        ]
                                      : [],
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(16),
                                  onTap: (!isUnlocked || _isNavigating)
                                      ? null
                                      : () {
                                          _safeNavigate(() async {
                                            final canPlay =
                                                await _ensureHasLives(
                                              context,
                                              uid,
                                            );
                                            if (!canPlay) return;

                                            if (!context.mounted) return;
                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => LevelPlayScreen(
                                                  categoryId: widget.categoryId,
                                                  levelNumber: level,
                                                ),
                                              ),
                                            );
                                          });
                                        },
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(icon, size: 32),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Nivel $level',
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          subtitle,
                                          style: const TextStyle(fontSize: 13),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 6),
                                        _StarsRow(count: stars),
                                        if (showRecommended) ...[
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.withOpacity(
                                                0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: const Text(
                                              'Siguiente',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.blue,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          if (_isNavigating)
            Container(
              color: Colors.black.withOpacity(0.4),
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text(
                      'Cargando...',
                      style: TextStyle(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  int _starsForLevel({
    required int level,
    required bool isCompleted,
    required Map<String, dynamic> levelStats,
  }) {
    if (!isCompleted) return 0;

    final stat = Map<String, dynamic>.from(
      levelStats[level.toString()] as Map? ?? {},
    );

    final percent = ((stat['percent'] ?? 0.0) as num).toDouble();

    if (percent >= 0.9) return 3;
    if (percent >= 0.7) return 2;
    return 1;
  }
}

class _StarsRow extends StatelessWidget {
  final int count;

  const _StarsRow({required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final filled = i < count;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: Icon(
            filled ? Icons.star : Icons.star_border,
            size: 18,
          ),
        );
      }),
    );
  }
}

class _NoLivesDialog extends StatelessWidget {
  final String currentLivesText;
  final String nextHalfLifeText;
  final String nextFullLifeText;
  final VoidCallback? onBuyLife;
  final int cost;

  const _NoLivesDialog({
    required this.currentLivesText,
    required this.nextHalfLifeText,
    required this.nextFullLifeText,
    this.onBuyLife,
    this.cost = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.favorite_border,
                size: 38,
                color: Colors.red,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Sin vidas suficientes',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Necesitas al menos 1 vida completa para entrar a un nivel.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _DialogInfoRow(
                    icon: Icons.favorite,
                    label: 'Tus vidas',
                    value: currentLivesText,
                  ),
                  const SizedBox(height: 10),
                  _DialogInfoRow(
                    icon: Icons.timer,
                    label: 'Próx. media vida',
                    value: nextHalfLifeText,
                  ),
                  const SizedBox(height: 10),
                  _DialogInfoRow(
                    icon: Icons.hourglass_bottom,
                    label: 'Para 1 vida completa',
                    value: nextFullLifeText,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Volver'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Esperar'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onBuyLife,
                icon: const Icon(Icons.favorite),
                label: Text('Recuperar 1 vida ($cost monedas)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DialogInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DialogInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}