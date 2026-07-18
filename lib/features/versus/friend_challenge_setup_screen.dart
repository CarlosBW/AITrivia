import 'package:flutter/material.dart';

import '../../services/match_service.dart';
import '../../services/realtime_invite_service.dart';
import 'async_match_play_screen.dart';

class FriendChallengeSetupScreen extends StatefulWidget {
  final String friendUid;
  final String friendName;
  final bool isOnline;

  const FriendChallengeSetupScreen({
    super.key,
    required this.friendUid,
    required this.friendName,
    required this.isOnline,
  });

  @override
  State<FriendChallengeSetupScreen> createState() =>
      _FriendChallengeSetupScreenState();
}

class _FriendChallengeSetupScreenState
    extends State<FriendChallengeSetupScreen> {
  final _matchService = MatchService();
  final _realtimeInviteService = RealtimeInviteService.instance;

  bool _loading = false;
  String? _error;

  String _challengeType = 'realtime';
  String _categoryId = 'random';
  int _difficulty = 1;
  int _totalQuestions = 10;
  int _timePerQuestionSec = 10;

  final List<String> _categories = const [
    'random',
    'cine',
    'historia',
    'videojuegos',
  ];

  Future<void> _sendChallenge() async {
    if (_loading) return;

    if (_challengeType == 'realtime' && !widget.isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tu amigo no está conectado para jugar en tiempo real.'),
        ),
      );
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final myName = await _matchService.getMyDisplayNameFallback('Player');

      if (_challengeType == 'realtime') {
        await _realtimeInviteService.createInvite(
          toUid: widget.friendUid,
          toName: widget.friendName,
          fromName: myName,
          categoryId: _categoryId,
          difficulty: _difficulty,
          totalQuestions: _totalQuestions,
          timePerQuestionSec: _timePerQuestionSec,
          winReward: 2,
        );

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reto en tiempo real enviado a ${widget.friendName}'),
          ),
        );

        Navigator.pop(context);
        return;
      }

      final matchId = await _matchService.createAsyncFixedMatch(
        challengedUid: widget.friendUid,
        categoryId: _categoryId,
        difficulty: _difficulty,
        totalQuestions: _totalQuestions,
        timePerQuestionSec: _timePerQuestionSec,
        winReward: 2,
        challengerDisplayName: myName,
        challengedDisplayName: widget.friendName,
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AsyncMatchPlayScreen(asyncMatchId: matchId),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final onlineText = widget.isOnline ? 'Online' : 'Offline';
    final onlineColor = widget.isOnline ? Colors.green : Colors.grey;

    final canSendRealtime = widget.isOnline;
    final sendButtonText =
        _challengeType == 'realtime' ? 'Enviar reto en tiempo real' : 'Crear reto asíncrono';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configurar reto'),
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.25),
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.sports_esports, size: 42),
                    const SizedBox(height: 12),
                    Text(
                      widget.friendName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: onlineColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          onlineText,
                          style: TextStyle(
                            color: onlineColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Tipo de reto',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'realtime',
                    icon: Icon(
                      widget.isOnline ? Icons.bolt : Icons.lock,
                    ),
                    label: const Text('Tiempo real'),
                  ),
                  const ButtonSegment(
                    value: 'async',
                    icon: Icon(Icons.schedule),
                    label: Text('Asíncrono'),
                  ),
                ],
                selected: {_challengeType},
                onSelectionChanged: (values) {
                  setState(() {
                    _challengeType = values.first;
                  });
                },
              ),
              if (_challengeType == 'realtime' && !canSendRealtime) ...[
                const SizedBox(height: 8),
                const Text(
                  'Tu amigo debe estar online para jugar en tiempo real.',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
              const SizedBox(height: 20),
              const Text(
                'Configuración del match',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _categoryId,
                decoration: const InputDecoration(
                  labelText: 'Categoría',
                  border: OutlineInputBorder(),
                ),
                items: _categories
                    .map(
                      (category) => DropdownMenuItem(
                        value: category,
                        child: Text(
                          category == 'random' ? 'Random' : category,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _loading
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _categoryId = value);
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _difficulty,
                decoration: const InputDecoration(
                  labelText: 'Dificultad',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Fácil')),
                  DropdownMenuItem(value: 2, child: Text('Media')),
                  DropdownMenuItem(value: 3, child: Text('Difícil')),
                ],
                onChanged: _loading
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _difficulty = value);
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _totalQuestions,
                decoration: const InputDecoration(
                  labelText: 'Cantidad de preguntas',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 5, child: Text('5 preguntas')),
                  DropdownMenuItem(value: 10, child: Text('10 preguntas')),
                  DropdownMenuItem(value: 15, child: Text('15 preguntas')),
                ],
                onChanged: _loading
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _totalQuestions = value);
                      },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                value: _timePerQuestionSec,
                decoration: const InputDecoration(
                  labelText: 'Tiempo por pregunta',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 10, child: Text('10 segundos')),
                  DropdownMenuItem(value: 15, child: Text('15 segundos')),
                  DropdownMenuItem(value: 20, child: Text('20 segundos')),
                ],
                onChanged: _loading
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _timePerQuestionSec = value);
                      },
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed:
                    _loading || (_challengeType == 'realtime' && !canSendRealtime)
                        ? null
                        : _sendChallenge,
                icon: Icon(
                  _challengeType == 'realtime'
                      ? Icons.bolt
                      : Icons.schedule,
                ),
                label: Text(sendButtonText),
              ),
              const SizedBox(height: 12),
              Text(
                _challengeType == 'realtime'
                    ? 'Tiempo real requiere que ambos estén online. Las partidas con amigos son casuales y no afectan MMR.'
                    : 'Asíncrono permite que tu amigo juegue cuando pueda. No afecta MMR.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
            ],
          ),
          if (_loading)
            Container(
              color: Colors.black.withOpacity(0.25),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}