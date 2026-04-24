import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/match_service.dart';
import 'match_lobby_screen.dart';

class LiveMatchmakingScreen extends StatefulWidget {
  final String categoryId;
  final int difficulty;
  final int timePerQuestionSec;
  final int totalQuestions;
  final int winReward;
  final String displayName;

  const LiveMatchmakingScreen({
    super.key,
    required this.categoryId,
    this.difficulty = 1,
    this.timePerQuestionSec = 10,
    this.totalQuestions = 10,
    this.winReward = 2,
    this.displayName = 'Player',
  });

  @override
  State<LiveMatchmakingScreen> createState() => _LiveMatchmakingScreenState();
}

class _LiveMatchmakingScreenState extends State<LiveMatchmakingScreen> {
  final _service = MatchService();

  bool _searching = false;
  Timer? _pollTimer;
  String? _error;

  bool _starting = false; // evita doble tap en "Buscar"

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (_starting) return;

    setState(() {
      _starting = true;
      _error = null;
      _searching = true;
    });

    try {
      // 1) entra a cola (usa el nombre correcto: myDisplayName)
      await _service.startLiveSearch(
        categoryId: widget.categoryId,
        difficulty: widget.difficulty,
        totalQuestions: widget.totalQuestions,
        timePerQuestionSec: widget.timePerQuestionSec,
        winReward: widget.winReward,
        displayName: widget.displayName, // ✅ antes: displayName
      );

      // 2) intenta emparejar de inmediato (si encuentra crea match y setea matchId en cola)
      await _service.tryFindLiveOpponent(
        categoryId: widget.categoryId,
        difficulty: widget.difficulty,
        totalQuestions: widget.totalQuestions,
        timePerQuestionSec: widget.timePerQuestionSec,
        winReward: widget.winReward,
        myDisplayName: widget.displayName,
      );

      // 3) Poll suave: cada 1.2s intento emparejar
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) async {
        if (!mounted) return;
        if (!_searching) return;

        try {
          await _service.tryFindLiveOpponent(
            categoryId: widget.categoryId,
            difficulty: widget.difficulty,
            totalQuestions: widget.totalQuestions,
            timePerQuestionSec: widget.timePerQuestionSec,
            winReward: widget.winReward,
            myDisplayName: widget.displayName,
          );
        } catch (e) {
          // no spamear, solo guardar el último
          if (mounted) setState(() => _error = e.toString());
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _searching = false;
      });

      // si falla al entrar a cola / match, intenta limpiar
      try {
        await _service.stopLiveSearch();
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _cancel() async {
    _pollTimer?.cancel();
    if (mounted) setState(() => _searching = false);
    await _service.stopLiveSearch();
  }

  @override
  Widget build(BuildContext context) {
    final queueStream = _service.watchMyLiveQueue();

    return Scaffold(
      appBar: AppBar(title: const Text('Buscar jugadores')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: queueStream,
        builder: (context, snap) {
          final data = snap.data?.data();
          final status = (data?['status'] ?? '').toString();
          final matchId = data?['matchId'] as String?;

          // si ya tenemos matchId -> navegar
          if (matchId != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted) return;

              _pollTimer?.cancel();
              setState(() => _searching = false);

              // opcional: limpiar cola
              await _service.cleanupMyLiveQueueAfterMatch();

              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => MatchLobbyScreen(matchId: matchId),
                ),
              );
            });
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Categoría: ${widget.categoryId}'),
                Text('Dificultad: ${widget.difficulty}'),
                Text('Preguntas: ${widget.totalQuestions}'),
                Text('Tiempo/Pregunta: ${widget.timePerQuestionSec}s'),
                const SizedBox(height: 16),

                if (_error != null)
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),

                const SizedBox(height: 16),

                if (!_searching) ...[
                  FilledButton(
                    onPressed: _starting ? null : _start,
                    child: const Text('Buscar'),
                  ),
                ] else ...[
                  Row(
                    children: [
                      const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 3),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          status.isEmpty ? 'Buscando...' : 'Estado cola: $status',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _cancel,
                    child: const Text('Cancelar búsqueda'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
