import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/economy_service.dart';
import '../../services/match_service.dart';
import 'live_matchmaking_screen.dart';
import 'match_lobby_screen.dart';
import '../../l10n/generated/app_localizations.dart';

class _CategoryOption {
  final String id;
  final String name;

  const _CategoryOption({required this.id, required this.name});
}

class CreateMatchScreen extends StatefulWidget {
  const CreateMatchScreen({super.key});

  @override
  State<CreateMatchScreen> createState() => _CreateMatchScreenState();
}

class _CreateMatchScreenState extends State<CreateMatchScreen> {
  final _service = MatchService();

  late final Future<List<_CategoryOption>> _categoriesFuture =
      _loadCategories();

  // Placeholder until _categoriesFuture resolves and the dropdown swaps in
  // a real category id — matches live_menu_screen.dart's pattern.
  String? _categoryId;
  int _difficulty = 1;
  int _timePerQuestionSec = 10;
  int _totalQuestions = 10;

  // Mirrors live_menu_screen.dart's _loadCategories — reads the same
  // fixed_categories collection Solo/Live matchmaking use, instead of a
  // hand-maintained list that drifts as categories are added/renamed.
  Future<List<_CategoryOption>> _loadCategories() async {
    final snap = await FirebaseFirestore.instance
        .collection('fixed_categories')
        .where('isActive', isEqualTo: true)
        .get();

    final docs = snap.docs.toList()
      ..sort((a, b) {
        final ao = ((a.data()['order'] ?? 999) as num).toInt();
        final bo = ((b.data()['order'] ?? 999) as num).toInt();
        return ao.compareTo(bo);
      });

    final options = [
      for (final doc in docs)
        _CategoryOption(
          id: doc.id,
          name: (doc.data()['name'] ?? doc.id).toString(),
        ),
    ];

    if (options.isNotEmpty && mounted && _categoryId == null) {
      setState(() => _categoryId = options.first.id);
    }

    return options;
  }

  // Fijo, igual que el matchmaking público — evita que el jugador siempre
  // elija la recompensa máxima al crear su propia sala.
  static const int _winReward = EconomyService.defaultPvpWinReward;

  final TextEditingController _nameCtrl =
      TextEditingController(text: 'Host');

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _createRoom() async {
    if (_loading || _categoryId == null) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final matchId = await _service.createFixedMatch(
        categoryId: _categoryId!,
        difficulty: _difficulty,
        totalQuestions: _totalQuestions,
        timePerQuestionSec: _timePerQuestionSec,
        winReward: _winReward,
        displayName: _nameCtrl.text.trim().isEmpty ? 'Host' : _nameCtrl.text.trim(),
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => MatchLobbyScreen(matchId: matchId),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goToMatchmaking() {
    if (_categoryId == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveMatchmakingScreen(
          categoryId: _categoryId!,
          difficulty: _difficulty,
          totalQuestions: _totalQuestions,
          timePerQuestionSec: _timePerQuestionSec,
          winReward: _winReward,
          displayName: _nameCtrl.text.trim().isEmpty ? 'Player' : _nameCtrl.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.createMatchTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 12),
            ],

            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: l10n.createMatchYourName,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            FutureBuilder<List<_CategoryOption>>(
              future: _categoriesFuture,
              builder: (context, snap) {
                final options = [
                  _CategoryOption(
                    id: 'random',
                    name: l10n.friendChallengeCategoryRandom,
                  ),
                  ...?snap.data,
                ];

                return DropdownButtonFormField<String>(
                  // Re-keying once the real default (options.first.id) loads
                  // forces this FormField to re-read `initialValue` — it's
                  // otherwise only consulted on the field's first build.
                  key: ValueKey(_categoryId),
                  initialValue: _categoryId,
                  items: options
                      .map(
                        (c) => DropdownMenuItem(
                          value: c.id,
                          child: Text(c.name),
                        ),
                      )
                      .toList(),
                  onChanged: _loading || !snap.hasData
                      ? null
                      : (v) => setState(() => _categoryId = v),
                  decoration: InputDecoration(
                    labelText: l10n.createMatchCategory,
                    border: const OutlineInputBorder(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _difficulty,
                    items: [
                      DropdownMenuItem(value: 1, child: Text(l10n.createMatchDiffEasy)),
                      DropdownMenuItem(value: 2, child: Text(l10n.createMatchDiffMedium)),
                      DropdownMenuItem(value: 3, child: Text(l10n.createMatchDiffHard)),
                    ],
                    onChanged: _loading ? null : (v) => setState(() => _difficulty = v ?? 1),
                    decoration: InputDecoration(
                      labelText: l10n.createMatchDifficulty,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _timePerQuestionSec,
                    items: const [
                      DropdownMenuItem(value: 8, child: Text('8s')),
                      DropdownMenuItem(value: 10, child: Text('10s')),
                      DropdownMenuItem(value: 12, child: Text('12s')),
                      DropdownMenuItem(value: 15, child: Text('15s')),
                    ],
                    onChanged: _loading ? null : (v) => setState(() => _timePerQuestionSec = v ?? 10),
                    decoration: InputDecoration(
                      labelText: l10n.createMatchTimePerQuestion,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<int>(
              initialValue: _totalQuestions,
              items: const [
                DropdownMenuItem(value: 5, child: Text('5')),
                DropdownMenuItem(value: 10, child: Text('10')),
                DropdownMenuItem(value: 15, child: Text('15')),
              ],
              onChanged: _loading ? null : (v) => setState(() => _totalQuestions = v ?? 10),
              decoration: InputDecoration(
                labelText: l10n.createMatchQuestions,
                border: const OutlineInputBorder(),
              ),
            ),

            const Spacer(),

            // ✅ Matchmaking (auto)
            FilledButton(
              onPressed:
                  _loading || _categoryId == null ? null : _goToMatchmaking,
              child: Text(l10n.createMatchAutoSearch),
            ),
            const SizedBox(height: 12),

            // ✅ Crear sala manual
            FilledButton.tonal(
              onPressed:
                  _loading || _categoryId == null ? null : _createRoom,
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.createMatchCreateRoom),
            ),
          ],
        ),
      ),
    );
  }
}
