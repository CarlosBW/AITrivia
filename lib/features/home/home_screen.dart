import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../solo/level_play_screen.dart';
import '../solo/level_select_screen.dart';
import '../versus/versus_menu_screen.dart';
import '../../services/life_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _lifeState;
  bool _loadingLives = true;
  Timer? _lifeTimer;
  bool _isNavigating = false;

  late final String uid;

  @override
  void initState() {
    super.initState();
    uid = FirebaseAuth.instance.currentUser!.uid;
    _initLives();
    _startLifeTimer();
  }

  Future<void> _initLives() async {
    await LifeService.instance.ensureUserLifeDoc(uid);
    await _refreshLives();
  }

  void _startLifeTimer() {
    _lifeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _refreshLives();
    });
  }

  Future<void> _refreshLives() async {
    final state = await LifeService.instance.refreshLives(uid);

    if (!mounted) return;

    setState(() {
      _lifeState = state;
      _loadingLives = false;
    });
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
  void dispose() {
    _lifeTimer?.cancel();
    super.dispose();
  }

  String _formatCountdown(int? totalSeconds) {
    if (totalSeconds == null) return '--:--';
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _showNoLivesDialog({
    required BuildContext context,
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
        lifeUnits: lifeUnits,
        maxLifeUnits: maxLifeUnits,
        secondsToNextHalfLife: secondsToNextHalfLife,
      );

      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final db = FirebaseFirestore.instance;
    final userRef = db.collection('users').doc(uid);

    final categoriesQuery =
        db.collection('fixed_categories').where('isActive', isEqualTo: true);

    return Scaffold(
      appBar: AppBar(
        title: const Text('TriviaIA'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: userRef.snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const LinearProgressIndicator();
                    }

                    final data = snap.data!.data() ?? {};
                    final coins = data['coins'] ?? 0;
                    final passes = data['freeTopicPasses'] ?? 0;
                    final xp = data['xp'] ?? 0;

                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          _loadingLives || _lifeState == null
                              ? const LinearProgressIndicator()
                              : Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _StatCard(
                                            icon: Icons.favorite,
                                            label: 'Vidas',
                                            value:
                                                '${LifeService.instance.formatLives(_lifeState!['lifeUnits'])} / ${LifeService.instance.formatLives(_lifeState!['maxLifeUnits'])}',
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: _StatCard(
                                            icon: Icons.timer,
                                            label: 'Próx. media vida',
                                            value: _lifeState!['lifeUnits'] >=
                                                    _lifeState!['maxLifeUnits']
                                                ? 'MAX'
                                                : _formatCountdown(
                                                    _lifeState![
                                                        'secondsToNextHalfLife'],
                                                  ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                ),
                          Row(
                            children: [
                              Expanded(
                                child: _StatCard(
                                  icon: Icons.monetization_on,
                                  label: 'Monedas',
                                  value: '$coins',
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _StatCard(
                                  icon: Icons.auto_awesome,
                                  label: 'XP',
                                  value: '$xp',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _StatCard(
                            icon: Icons.style,
                            label: 'Tema libre',
                            value: '$passes',
                            fullWidth: true,
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isNavigating
                            ? null
                            : () {
                                _safeNavigate(() async {
                                  if (!context.mounted) return;
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const VersusMenuScreen(),
                                    ),
                                  );
                                });
                              },
                        icon: const Icon(Icons.sports_esports),
                        label: const Text('1 vs 1'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isNavigating
                            ? null
                            : () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Próximamente: Tema libre con IA (consumirá pases o monedas).',
                                    ),
                                  ),
                                );
                              },
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Tema libre (IA)'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Temas fijos',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: categoriesQuery.snapshots(),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Center(
                          child: Text(
                            'Error al cargar categorías:\n${snap.error}',
                            textAlign: TextAlign.center,
                          ),
                        );
                      }

                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final docs = snap.data!.docs;
                      docs.sort((a, b) {
                        final ao = (a.data()['order'] ?? 999) as int;
                        final bo = (b.data()['order'] ?? 999) as int;
                        return ao.compareTo(bo);
                      });

                      if (docs.isEmpty) {
                        return const Center(
                          child: Text('No hay categorías activas en Firestore.'),
                        );
                      }

                      return ListView.separated(
                        itemCount: docs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final doc = docs[i];
                          final data = doc.data();

                          final categoryId = doc.id;
                          final name = (data['name'] ?? categoryId).toString();
                          final levelCount = (data['levelCount'] ?? 10) as int;

                          final progressRef = db
                              .collection('users')
                              .doc(uid)
                              .collection('progress_fixed')
                              .doc(categoryId);

                          return StreamBuilder<
                              DocumentSnapshot<Map<String, dynamic>>>(
                            stream: progressRef.snapshots(),
                            builder: (context, progressSnap) {
                              final progressData = progressSnap.data?.data() ?? {};

                              final completedLevels =
                                  (progressData['completedLevels']
                                              as List<dynamic>? ??
                                          [])
                                      .map((e) => (e as num).toInt())
                                      .toSet();

                              final completedCount = completedLevels.length;
                              final progress = levelCount == 0
                                  ? 0.0
                                  : (completedCount / levelCount).clamp(0.0, 1.0);

                              int nextLevel = 1;
                              if (completedLevels.isNotEmpty) {
                                final highestCompleted = completedLevels.reduce(
                                  (a, b) => a > b ? a : b,
                                );
                                nextLevel = highestCompleted + 1;
                              }
                              if (nextLevel > levelCount) {
                                nextLevel = levelCount;
                              }

                              final completedAll =
                                  progressData['completedAllLevels'] == true ||
                                      completedCount >= levelCount;

                              String statusText;
                              Color statusColor;

                              if (completedAll) {
                                statusText = 'Completado';
                                statusColor = Colors.green;
                              } else if (completedCount > 0) {
                                statusText = 'En curso';
                                statusColor = Colors.orange;
                              } else {
                                statusText = 'Nuevo';
                                statusColor = Colors.blue;
                              }

                              return Card(
                                elevation: 0,
                                color: Colors.black12,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(14),
                                  onTap: _isNavigating
                                      ? null
                                      : () {
                                          _safeNavigate(() async {
                                            final canPlay =
                                                await _ensureHasLives(
                                                    context, uid);
                                            if (!canPlay) return;

                                            if (!context.mounted) return;
                                            await Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => LevelSelectScreen(
                                                  categoryId: categoryId,
                                                  categoryName: name,
                                                ),
                                              ),
                                            );
                                          });
                                        },
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                name,
                                                style: const TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 10,
                                                vertical: 5,
                                              ),
                                              decoration: BoxDecoration(
                                                color: statusColor
                                                    .withOpacity(0.12),
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                              ),
                                              child: Text(
                                                statusText,
                                                style: TextStyle(
                                                  color: statusColor,
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        Text(
                                          'Progreso: $completedCount / $levelCount niveles',
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                        const SizedBox(height: 8),
                                        ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: LinearProgressIndicator(
                                            value: progress,
                                            minHeight: 10,
                                          ),
                                        ),
                                        const SizedBox(height: 14),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: OutlinedButton.icon(
                                                onPressed: _isNavigating
                                                    ? null
                                                    : () {
                                                        _safeNavigate(() async {
                                                          final canPlay =
                                                              await _ensureHasLives(
                                                                  context, uid);
                                                          if (!canPlay) return;

                                                          if (!context.mounted) {
                                                            return;
                                                          }
                                                          await Navigator.push(
                                                            context,
                                                            MaterialPageRoute(
                                                              builder: (_) =>
                                                                  LevelSelectScreen(
                                                                categoryId:
                                                                    categoryId,
                                                                categoryName:
                                                                    name,
                                                              ),
                                                            ),
                                                          );
                                                        });
                                                      },
                                                icon: const Icon(
                                                    Icons.map_outlined),
                                                label:
                                                    const Text('Ver niveles'),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: FilledButton.icon(
                                                onPressed: _isNavigating
                                                    ? null
                                                    : completedAll
                                                        ? () {
                                                            _safeNavigate(
                                                                () async {
                                                              final canPlay =
                                                                  await _ensureHasLives(
                                                                      context,
                                                                      uid);
                                                              if (!canPlay) {
                                                                return;
                                                              }

                                                              if (!context
                                                                  .mounted) {
                                                                return;
                                                              }
                                                              await Navigator
                                                                  .push(
                                                                context,
                                                                MaterialPageRoute(
                                                                  builder: (_) =>
                                                                      LevelSelectScreen(
                                                                    categoryId:
                                                                        categoryId,
                                                                    categoryName:
                                                                        name,
                                                                  ),
                                                                ),
                                                              );
                                                            });
                                                          }
                                                        : () {
                                                            _safeNavigate(
                                                                () async {
                                                              final canPlay =
                                                                  await _ensureHasLives(
                                                                      context,
                                                                      uid);
                                                              if (!canPlay) {
                                                                return;
                                                              }

                                                              if (!context
                                                                  .mounted) {
                                                                return;
                                                              }
                                                              await Navigator
                                                                  .push(
                                                                context,
                                                                MaterialPageRoute(
                                                                  builder: (_) =>
                                                                      LevelPlayScreen(
                                                                    categoryId:
                                                                        categoryId,
                                                                    levelNumber:
                                                                        nextLevel,
                                                                  ),
                                                                ),
                                                              );
                                                            });
                                                          },
                                                icon: Icon(
                                                  completedAll
                                                      ? Icons.check_circle
                                                      : Icons.play_arrow,
                                                ),
                                                label: Text(
                                                  completedAll
                                                      ? 'Completado'
                                                      : 'Continuar N$nextLevel',
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
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
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool fullWidth;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment:
            fullWidth ? MainAxisAlignment.center : MainAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$label: $value',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoLivesDialog extends StatelessWidget {
  final String currentLivesText;
  final String nextHalfLifeText;
  final String nextFullLifeText;

  const _NoLivesDialog({
    required this.currentLivesText,
    required this.nextHalfLifeText,
    required this.nextFullLifeText,
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
              style: TextStyle(
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