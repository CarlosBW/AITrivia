import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../services/match_service.dart';
import '../../services/presence_service.dart';
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

class _LiveMatchmakingScreenState extends State<LiveMatchmakingScreen>
    with WidgetsBindingObserver {
  final _service = MatchService();
  final _presenceService = PresenceService.instance;

  static const Duration _pollInterval = Duration(seconds: 5);
  static const Duration _queueHeartbeatInterval = Duration(seconds: 10);
  static const Duration _searchTimeout = Duration(seconds: 90);

  bool _searching = false;
  bool _starting = false;
  bool _matchAttemptRunning = false;
  bool _navigatingToLobby = false;

  Timer? _pollTimer;
  Timer? _queueHeartbeatTimer;
  Timer? _timeoutTimer;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _cancel(silent: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _queueHeartbeatTimer?.cancel();
    _timeoutTimer?.cancel();

    // No se espera el Future para evitar bloquear dispose.
    // Si ya navegamos al lobby, cleanupMyLiveQueueAfterMatch se encarga del reset.
    if (_searching && !_navigatingToLobby) {
      _service.stopLiveSearch();
      _presenceService.setAvailable();
    }

    super.dispose();
  }

  Future<void> _start() async {
    if (_starting || _searching) return;

    setState(() {
      _starting = true;
      _searching = true;
      _error = null;
    });

    try {
      await _presenceService.setSearchingMatch();
      await _service.startLiveSearch(
        categoryId: widget.categoryId,
        difficulty: widget.difficulty,
        totalQuestions: widget.totalQuestions,
        timePerQuestionSec: widget.timePerQuestionSec,
        winReward: widget.winReward,
        displayName: widget.displayName,
      );

      await _service.updateLiveSearchHeartbeat();
      await _tryFindOpponentOnce();

      _queueHeartbeatTimer?.cancel();
      _queueHeartbeatTimer = Timer.periodic(_queueHeartbeatInterval, (_) async {
        if (!_searching || _navigatingToLobby) return;

        try {
          await _presenceService.refreshHeartbeatNow();
          await _service.updateLiveSearchHeartbeat();
        } catch (_) {}
      });

      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(_pollInterval, (_) {
        _tryFindOpponentOnce();
      });

      _timeoutTimer?.cancel();
      _timeoutTimer = Timer(_searchTimeout, () async {
        if (!mounted || !_searching || _navigatingToLobby) return;

        await _cancel(silent: true);

        if (!mounted) return;
        setState(() {
          _error = 'No se encontró rival por ahora. Intenta nuevamente.';
        });
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _searching = false;
      });

      try {
        await _service.stopLiveSearch();
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _tryFindOpponentOnce() async {
    if (!mounted) return;
    if (!_searching) return;
    if (_matchAttemptRunning) return;
    if (_navigatingToLobby) return;

    _matchAttemptRunning = true;

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
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      _matchAttemptRunning = false;
    }
  }

  Future<void> _cancel({bool silent = false}) async {
    _pollTimer?.cancel();
    _queueHeartbeatTimer?.cancel();
    _timeoutTimer?.cancel();

    if (mounted) {
      setState(() {
        _searching = false;
        _starting = false;
      });
    }

    try {
      await _service.stopLiveSearch();
      await _presenceService.setAvailable();
    } catch (e) {
      if (!silent && mounted) {
        setState(() => _error = e.toString());
      }
    }
  }

  Future<void> _goToLobby(String matchId) async {
    if (_navigatingToLobby) return;

    _navigatingToLobby = true;
    _pollTimer?.cancel();
    _queueHeartbeatTimer?.cancel();
    _timeoutTimer?.cancel();

    if (mounted) {
      setState(() => _searching = false);
    }

    try {
      await _service.cleanupMyLiveQueueAfterMatch();
      await _presenceService.setInMatch();
    } catch (_) {}

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => MatchLobbyScreen(matchId: matchId),
      ),
    );
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

          if (matchId != null && !_navigatingToLobby) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _goToLobby(matchId);
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
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                ],
                if (!_searching) ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _starting ? null : _start,
                      child: _starting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Buscar'),
                    ),
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
                          status.isEmpty
                              ? 'Buscando...'
                              : status == 'searching'
                                  ? 'Buscando rival...'
                                  : 'Estado cola: $status',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Esto puede tardar unos segundos.',
                    style: TextStyle(color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => _cancel(),
                      child: const Text('Cancelar búsqueda'),
                    ),
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
