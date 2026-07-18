import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/match_service.dart';
import '../../services/presence_service.dart';
import '../../services/avatar_service.dart';
import 'match_play_screen.dart';

class MatchLobbyScreen extends StatefulWidget {
  final String matchId;

  const MatchLobbyScreen({
    super.key,
    required this.matchId,
  });

  @override
  State<MatchLobbyScreen> createState() => _MatchLobbyScreenState();
}

class _MatchLobbyScreenState extends State<MatchLobbyScreen> {
  final _presenceService = PresenceService.instance;

  bool _navigatingToMatch = false;

  @override
  void initState() {
    super.initState();

    Future.microtask(() async {
      try {
        await _presenceService.setInMatch();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    if (!_navigatingToMatch) {
      _presenceService.setAvailable();
    }

    super.dispose();
  }

  Future<void> _leaveBecauseMatchUnavailable(String message) async {
    if (_navigatingToMatch) return;

    _navigatingToMatch = true;

    try {
      await _presenceService.setAvailable();
    } catch (_) {}

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );

    Navigator.pop(context);
  }

  String _displayCategory(String categoryId) {
    if (categoryId == 'random') return 'Random';
    if (categoryId.isEmpty) return 'Categoría';
    return categoryId[0].toUpperCase() + categoryId.substring(1);
  }

  String _statusText({
    required bool myReady,
    required bool opponentReady,
    required bool hasGuest,
  }) {
    if (!hasGuest) {
      return 'Esperando que tu amigo se una a la sala.';
    }

    if (myReady && opponentReady) {
      return 'Todo listo. La partida está iniciando...';
    }

    if (myReady && !opponentReady) {
      return 'Listo. Esperando que tu rival confirme.';
    }

    if (!myReady && opponentReady) {
      return 'Tu rival ya está listo. Confirma para empezar.';
    }

    return 'Esperando que ambos jugadores estén listos.';
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final service = MatchService();
    final ref =
        FirebaseFirestore.instance.collection('matches').doc(widget.matchId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sala 1 vs 1'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: ref.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snap.data!.data();

          if (data == null) {
            return const Center(child: Text('Sala no encontrada'));
          }

          final status = (data['status'] ?? 'waiting').toString();

          if ((status == 'cancelled' || status == 'expired') &&
              !_navigatingToMatch) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _leaveBecauseMatchUnavailable(
                'La sala ya no está disponible.',
              );
            });
          }

          if (status == 'playing' && !_navigatingToMatch) {
            _navigatingToMatch = true;

            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;

              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => MatchPlayScreen(
                    matchId: widget.matchId,
                  ),
                ),
              );
            });
          }

          final mode = (data['mode'] ?? 'fixed').toString();
          final categoryId = (data['categoryId'] ?? 'cine').toString();
          final code = (data['matchCode'] ?? widget.matchId).toString();

          final totalQuestions =
              ((data['totalQuestions'] ?? 10) as num).toInt();
          final timePerQuestionSec =
              ((data['timePerQuestionSec'] ?? 10) as num).toInt();

          final hostUid = (data['hostUid'] ?? '').toString();
          final guestUid = (data['guestUid'] ?? '').toString();

          final players = Map<String, dynamic>.from(data['players'] ?? {});

          final hostPlayer = Map<String, dynamic>.from(
            players[hostUid] ?? {},
          );
          final guestPlayer = Map<String, dynamic>.from(
            players[guestUid] ?? {},
          );
          final me = Map<String, dynamic>.from(players[uid] ?? {});

          final hostName =
              (hostPlayer['displayName'] ?? 'Jugador 1').toString();
          final guestName = guestUid.isEmpty
              ? 'Esperando rival'
              : (guestPlayer['displayName'] ?? 'Jugador 2').toString();

          final hostAvatarId =
              (hostPlayer['avatarId'] ?? 'avatar_1').toString();
          final guestAvatarId =
              (guestPlayer['avatarId'] ?? 'avatar_1').toString();

          final hostReady = hostPlayer['ready'] == true;
          final guestReady = guestPlayer['ready'] == true;
          final myReady = me['ready'] == true;

          final opponentReady = uid == hostUid ? guestReady : hostReady;
          final hasGuest = guestUid.isNotEmpty;

          final statusMessage = _statusText(
            myReady: myReady,
            opponentReady: opponentReady,
            hasGuest: hasGuest,
          );

          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.22),
                    ),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        '⚔️',
                        style: TextStyle(fontSize: 48),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '1 vs 1 Match',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        statusMessage,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.black.withOpacity(0.65),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _InfoCard(
                  children: [
                    _InfoRow(
                      icon: Icons.category,
                      label: 'Tema',
                      value: _displayCategory(categoryId),
                    ),
                    _InfoRow(
                      icon: Icons.auto_awesome,
                      label: 'Modo',
                      value: mode == 'fixed' ? 'Sin IA' : 'Con IA',
                    ),
                    _InfoRow(
                      icon: Icons.quiz,
                      label: 'Preguntas',
                      value: '$totalQuestions',
                    ),
                    _InfoRow(
                      icon: Icons.timer,
                      label: 'Tiempo',
                      value: '$timePerQuestionSec s por pregunta',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _PlayersCard(
                  hostName: hostName,
                  guestName: guestName,
                  hostAvatarId: hostAvatarId,
                  guestAvatarId: guestAvatarId,
                  hostReady: hostReady,
                  guestReady: guestReady,
                  hasGuest: hasGuest,
                ),
                const SizedBox(height: 16),
                _RoomCodeCard(
                  code: code,
                  onCopy: () async {
                    await Clipboard.setData(
                      ClipboardData(text: code),
                    );

                    if (!context.mounted) return;

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Código copiado'),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                if (status == 'waiting') ...[
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: !hasGuest || myReady
                          ? null
                          : () async {
                              await service.setReady(
                                widget.matchId,
                                true,
                              );
                            },
                      icon: Icon(
                        myReady ? Icons.hourglass_top : Icons.check_circle,
                      ),
                      label: Text(
                        !hasGuest
                            ? 'Esperando rival'
                            : myReady
                                ? 'Esperando rival...'
                                : 'Estoy listo',
                      ),
                    ),
                  ),
                  if (myReady) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: () async {
                          await service.setReady(
                            widget.matchId,
                            false,
                          );
                        },
                        child: const Text('Cancelar listo'),
                      ),
                    ),
                  ],
                ] else if (status != 'playing') ...[
                  Center(
                    child: Text(
                      'Estado de la sala: $status',
                      style: const TextStyle(color: Colors.black54),
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

class _InfoCard extends StatelessWidget {
  final List<Widget> children;

  const _InfoCard({
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        children: children,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 22, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlayersCard extends StatelessWidget {
  final String hostName;
  final String guestName;
  final String hostAvatarId;
  final String guestAvatarId;
  final bool hostReady;
  final bool guestReady;
  final bool hasGuest;

  const _PlayersCard({
    required this.hostName,
    required this.guestName,
    required this.hostAvatarId,
    required this.guestAvatarId,
    required this.hostReady,
    required this.guestReady,
    required this.hasGuest,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _PlayerStatusCard(
          name: hostName,
          avatarId: hostAvatarId,
          ready: hostReady,
          waiting: false,
        ),
        const SizedBox(height: 12),
        _PlayerStatusCard(
          name: guestName,
          avatarId: guestAvatarId,
          ready: hasGuest && guestReady,
          waiting: !hasGuest,
        ),
      ],
    );
  }
}

class _PlayerStatusCard extends StatelessWidget {
  final String name;
  final String avatarId;
  final bool ready;
  final bool waiting;

  const _PlayerStatusCard({
    required this.name,
    required this.avatarId,
    required this.ready,
    this.waiting = false,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = AvatarService.instance.avatarById(avatarId);

    final Color borderColor =
        ready ? Colors.green.shade300 : Colors.orange.shade300;

    final IconData icon = ready ? Icons.check_circle : Icons.access_time;

    final String statusText = waiting
        ? 'Esperando rival...'
        : ready
            ? 'Listo'
            : 'Esperando...';

    final Color statusColor = ready ? Colors.green : Colors.orange;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ready
            ? Colors.green.withOpacity(0.08)
            : Colors.orange.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: borderColor,
        ),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: ready
                    ? Colors.green.withOpacity(0.15)
                    : Colors.orange.withOpacity(0.15),
                child: Text(
                  avatar.emoji,
                  style: const TextStyle(fontSize: 25),
                ),
              ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: statusColor,
                    size: 16,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoomCodeCard extends StatelessWidget {
  final String code;
  final VoidCallback onCopy;

  const _RoomCodeCard({
    required this.code,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Código de sala',
            style: TextStyle(
              color: Colors.black54,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            code,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onCopy,
              icon: const Icon(Icons.copy),
              label: const Text('Copiar código'),
            ),
          ),
        ],
      ),
    );
  }
}
