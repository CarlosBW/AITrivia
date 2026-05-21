import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/life_service.dart';
import 'level_play_screen.dart';
import 'level_select_screen.dart';

class SoloScreen extends StatefulWidget {
  const SoloScreen({super.key});

  @override
  State<SoloScreen> createState() => _SoloScreenState();
}

class _SoloScreenState extends State<SoloScreen> {
  bool _loading = true;
  bool _isNavigating = false;
  bool _buyingLife = false;
  String? _error;

  List<_SoloCategoryItem> _categories = [];

  static const int _buyLifeCost = 10;

  late final String uid;

  @override
  void initState() {
    super.initState();
    uid = FirebaseAuth.instance.currentUser!.uid;
    _loadCategoriesAndProgress();
  }

  Future<void> _loadCategoriesAndProgress() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final db = FirebaseFirestore.instance;

      final categoriesSnap = await db
          .collection('fixed_categories')
          .where('isActive', isEqualTo: true)
          .get();

      final docs = categoriesSnap.docs.toList()
        ..sort((a, b) {
          final ao = ((a.data()['order'] ?? 999) as num).toInt();
          final bo = ((b.data()['order'] ?? 999) as num).toInt();
          return ao.compareTo(bo);
        });

      final items = await Future.wait(
        docs.map((doc) async {
          final data = doc.data();
          final categoryId = doc.id;
          final name = (data['name'] ?? categoryId).toString();
          final levelCount = ((data['levelCount'] ?? 10) as num).toInt();

          final progressSnap = await db
              .collection('users')
              .doc(uid)
              .collection('progress_fixed')
              .doc(categoryId)
              .get();

          final progressData = progressSnap.data() ?? {};

          final completedLevels =
              (progressData['completedLevels'] as List<dynamic>? ?? [])
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

          final completedAll = progressData['completedAllLevels'] == true ||
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

          return _SoloCategoryItem(
            categoryId: categoryId,
            name: name,
            levelCount: levelCount,
            completedCount: completedCount,
            progress: progress,
            nextLevel: nextLevel,
            completedAll: completedAll,
            statusText: statusText,
            statusColor: statusColor,
          );
        }),
      );

      if (!mounted) return;

      setState(() {
        _categories = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _safeNavigate(Future<void> Function() action) async {
    if (_isNavigating || _buyingLife) return;

    setState(() => _isNavigating = true);

    try {
      await action();
    } finally {
      if (mounted) {
        setState(() => _isNavigating = false);
      }
    }
  }

  String _formatCountdown(int? totalSeconds) {
    if (totalSeconds == null) return '--:--';

    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _buyLifeFromDialog(BuildContext dialogContext) async {
    if (_buyingLife) return;

    Navigator.pop(dialogContext);

    setState(() => _buyingLife = true);

    try {
      final success = await LifeService.instance.buyFullLife(
        uid: uid,
        cost: _buyLifeCost,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? '❤️ Vida recuperada'
                : '❌ No tienes suficientes monedas',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _buyingLife = false);
      }
    }
  }

  Future<void> _showNoLivesDialog({
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
      builder: (dialogContext) => _NoLivesDialog(
        currentLivesText: currentLivesText,
        nextHalfLifeText: nextHalfLifeText,
        nextFullLifeText: nextFullLifeText,
        cost: _buyLifeCost,
        onBuyLife: _buyingLife ? null : () => _buyLifeFromDialog(dialogContext),
      ),
    );
  }

  Future<bool> _ensureHasLives() async {
    await LifeService.instance.ensureUserLifeDoc(uid);
    final lifeState = await LifeService.instance.refreshLives(uid);

    final lifeUnits = (lifeState['lifeUnits'] ?? 0) as int;
    final maxLifeUnits = (lifeState['maxLifeUnits'] ?? 10) as int;
    final secondsToNextHalfLife = lifeState['secondsToNextHalfLife'] as int?;

    if (lifeUnits < 2) {
      if (!mounted) return false;

      await _showNoLivesDialog(
        lifeUnits: lifeUnits,
        maxLifeUnits: maxLifeUnits,
        secondsToNextHalfLife: secondsToNextHalfLife,
      );

      return false;
    }

    return true;
  }

  Future<void> _openLevelSelect(_SoloCategoryItem item) async {
    final canPlay = await _ensureHasLives();
    if (!canPlay) return;

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LevelSelectScreen(
          categoryId: item.categoryId,
          categoryName: item.name,
        ),
      ),
    );

    if (!mounted) return;
    await _loadCategoriesAndProgress();
  }

  Future<void> _continueLevel(_SoloCategoryItem item) async {
    final canPlay = await _ensureHasLives();
    if (!canPlay) return;

    if (!mounted) return;

    if (item.completedAll) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LevelSelectScreen(
            categoryId: item.categoryId,
            categoryName: item.name,
          ),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LevelPlayScreen(
            categoryId: item.categoryId,
            levelNumber: item.nextLevel,
          ),
        ),
      );
    }

    if (!mounted) return;
    await _loadCategoriesAndProgress();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Solo'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadCategoriesAndProgress,
            child: _buildContent(),
          ),
          if (_isNavigating || _buyingLife)
            Container(
              color: Colors.black.withOpacity(0.35),
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

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 120),
          const Icon(Icons.error_outline, size: 42),
          const SizedBox(height: 12),
          Text(
            'Error al cargar categorías:\n$_error',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _loadCategoriesAndProgress,
            icon: const Icon(Icons.refresh),
            label: const Text('Reintentar'),
          ),
        ],
      );
    }

    if (_categories.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: const [
          SizedBox(height: 120),
          Icon(Icons.info_outline, size: 42),
          SizedBox(height: 12),
          Text(
            'No hay categorías activas en Firestore.',
            textAlign: TextAlign.center,
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _categories.length + 1,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i == 0) {
          return const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'Temas fijos',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }

        final item = _categories[i - 1];

        return _CategoryCard(
          item: item,
          disabled: _isNavigating || _buyingLife,
          onOpenLevels: () {
            _safeNavigate(() => _openLevelSelect(item));
          },
          onContinue: () {
            _safeNavigate(() => _continueLevel(item));
          },
        );
      },
    );
  }
}

class _SoloCategoryItem {
  final String categoryId;
  final String name;
  final int levelCount;
  final int completedCount;
  final double progress;
  final int nextLevel;
  final bool completedAll;
  final String statusText;
  final Color statusColor;

  const _SoloCategoryItem({
    required this.categoryId,
    required this.name,
    required this.levelCount,
    required this.completedCount,
    required this.progress,
    required this.nextLevel,
    required this.completedAll,
    required this.statusText,
    required this.statusColor,
  });
}

class _CategoryCard extends StatelessWidget {
  final _SoloCategoryItem item;
  final bool disabled;
  final VoidCallback onOpenLevels;
  final VoidCallback onContinue;

  const _CategoryCard({
    required this.item,
    required this.disabled,
    required this.onOpenLevels,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: disabled ? null : onOpenLevels,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: item.statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      item.statusText,
                      style: TextStyle(
                        color: item.statusColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Progreso: ${item.completedCount} / ${item.levelCount} niveles',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: item.progress,
                  minHeight: 10,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: disabled ? null : onOpenLevels,
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('Ver niveles'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: disabled ? null : onContinue,
                      icon: Icon(
                        item.completedAll
                            ? Icons.check_circle
                            : Icons.play_arrow,
                      ),
                      label: Text(
                        item.completedAll
                            ? 'Completado'
                            : 'Continuar N${item.nextLevel}',
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
            const Text(
              'Necesitas al menos 1 vida completa para entrar a un nivel.',
              textAlign: TextAlign.center,
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
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}