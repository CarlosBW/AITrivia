import 'package:flutter/material.dart';

import '../../services/match_service.dart';
import 'live_matchmaking_screen.dart';
import 'match_lobby_screen.dart';

class CreateMatchScreen extends StatefulWidget {
  const CreateMatchScreen({super.key});

  @override
  State<CreateMatchScreen> createState() => _CreateMatchScreenState();
}

class _CreateMatchScreenState extends State<CreateMatchScreen> {
  final _service = MatchService();

  // ✅ defaults seguros
  String _categoryId = 'cine'; // puedes cambiar a 'random' si quieres
  int _difficulty = 1;
  int _timePerQuestionSec = 10;
  int _totalQuestions = 10;
  int _winReward = 2;

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
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final matchId = await _service.createFixedMatch(
        categoryId: _categoryId,
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveMatchmakingScreen(
          categoryId: _categoryId,
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
    final categories = <String>['cine', 'historia', 'videojuegos', 'random'];

    return Scaffold(
      appBar: AppBar(title: const Text('Crear sala (Tiempo real)')),
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
              decoration: const InputDecoration(
                labelText: 'Tu nombre (displayName)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: _categoryId,
              items: categories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: _loading ? null : (v) => setState(() => _categoryId = v ?? 'cine'),
              decoration: const InputDecoration(
                labelText: 'Categoría',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _difficulty,
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 (Fácil)')),
                      DropdownMenuItem(value: 2, child: Text('2 (Medio)')),
                      DropdownMenuItem(value: 3, child: Text('3 (Difícil)')),
                    ],
                    onChanged: _loading ? null : (v) => setState(() => _difficulty = v ?? 1),
                    decoration: const InputDecoration(
                      labelText: 'Dificultad',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _timePerQuestionSec,
                    items: const [
                      DropdownMenuItem(value: 8, child: Text('8s')),
                      DropdownMenuItem(value: 10, child: Text('10s')),
                      DropdownMenuItem(value: 12, child: Text('12s')),
                      DropdownMenuItem(value: 15, child: Text('15s')),
                    ],
                    onChanged: _loading ? null : (v) => setState(() => _timePerQuestionSec = v ?? 10),
                    decoration: const InputDecoration(
                      labelText: 'Tiempo/Pregunta',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _totalQuestions,
                    items: const [
                      DropdownMenuItem(value: 5, child: Text('5')),
                      DropdownMenuItem(value: 10, child: Text('10')),
                      DropdownMenuItem(value: 15, child: Text('15')),
                    ],
                    onChanged: _loading ? null : (v) => setState(() => _totalQuestions = v ?? 10),
                    decoration: const InputDecoration(
                      labelText: 'Preguntas',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _winReward,
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1 moneda')),
                      DropdownMenuItem(value: 2, child: Text('2 monedas')),
                      DropdownMenuItem(value: 3, child: Text('3 monedas')),
                      DropdownMenuItem(value: 5, child: Text('5 monedas')),
                    ],
                    onChanged: _loading ? null : (v) => setState(() => _winReward = v ?? 2),
                    decoration: const InputDecoration(
                      labelText: 'Recompensa',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),

            const Spacer(),

            // ✅ Matchmaking (auto)
            FilledButton(
              onPressed: _loading ? null : _goToMatchmaking,
              child: const Text('Buscar jugador automático'),
            ),
            const SizedBox(height: 12),

            // ✅ Crear sala manual
            FilledButton.tonal(
              onPressed: _loading ? null : _createRoom,
              child: _loading
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Crear sala'),
            ),
          ],
        ),
      ),
    );
  }
}
