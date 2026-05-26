import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'match_play_screen.dart';

class RealtimeMatchLobbyScreen extends StatefulWidget {
  final String matchId;

  const RealtimeMatchLobbyScreen({
    super.key,
    required this.matchId,
  });

  @override
  State<RealtimeMatchLobbyScreen> createState() =>
      _RealtimeMatchLobbyScreenState();
}

class _RealtimeMatchLobbyScreenState extends State<RealtimeMatchLobbyScreen> {
  final _uid = FirebaseAuth.instance.currentUser!.uid;

  bool _updatingReady = false;

  int? _countdown;
  Timer? _countdownTimer;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _setReady({
    required bool isPlayer1,
  }) async {
    if (_updatingReady) return;

    setState(() => _updatingReady = true);

    try {
      final ref =
          FirebaseFirestore.instance.collection('matches').doc(widget.matchId);

      await ref.update({
        isPlayer1 ? 'player1Ready' : 'player2Ready': true,
        'players.$_uid.ready': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } finally {
      if (mounted) {
        setState(() => _updatingReady = false);
      }
    }
  }

  Future<void> _startMatchCountdown() async {
    if (_countdown != null) return;

    setState(() {
      _countdown = 3;
    });

    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (timer) async {
        if (_countdown == null) {
          timer.cancel();
          return;
        }

        if (_countdown! <= 1) {
          timer.cancel();

          final ref = FirebaseFirestore.instance
              .collection('matches')
              .doc(widget.matchId);

          await ref.update({
            'status': 'playing',
            'startAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });

          if (!mounted) return;

          setState(() {
            _countdown = 0;
          });

          return;
        }

        if (!mounted) return;

        setState(() {
          _countdown = _countdown! - 1;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final matchRef =
        FirebaseFirestore.instance.collection('matches').doc(widget.matchId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Realtime Lobby'),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: matchRef.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error loading lobby:\n${snap.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snap.hasData || !snap.data!.exists) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          final data = snap.data!.data()!;

          final player1Uid = (data['player1Uid'] ?? '').toString();

          final player2Uid = (data['player2Uid'] ?? '').toString();

          final player1Name = (data['player1Name'] ?? 'Player 1').toString();

          final player2Name = (data['player2Name'] ?? 'Player 2').toString();

          final player1Ready = data['player1Ready'] == true;

          final player2Ready = data['player2Ready'] == true;

          final status = (data['status'] ?? 'waiting').toString();

          if (status == 'playing') {
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

          final isPlayer1 = player1Uid == _uid;
          final isPlayer2 = player2Uid == _uid;

          final myReady = isPlayer1 ? player1Ready : player2Ready;

          final bothReady = player1Ready && player2Ready;

          if (bothReady && status == 'realtime_lobby' && _countdown == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _startMatchCountdown();
            });
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.bolt,
                      size: 42,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Realtime Match Lobby',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Match ID: ${widget.matchId}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              _PlayerCard(
                playerName: player1Name,
                ready: player1Ready,
              ),
              const SizedBox(height: 12),
              _PlayerCard(
                playerName: player2Name,
                ready: player2Ready,
              ),
              const SizedBox(height: 28),
              if (!myReady)
                FilledButton.icon(
                  onPressed: _updatingReady
                      ? null
                      : () => _setReady(
                            isPlayer1: isPlayer1,
                          ),
                  icon: _updatingReady
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.check),
                  label: const Text('READY'),
                )
              else
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: Colors.green.withOpacity(0.45),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Colors.green,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'You are READY',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    if (_countdown == null)
                      const SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(),
                      )
                    else
                      Text(
                        '$_countdown',
                        style: const TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    const SizedBox(height: 14),
                    Text(
                      bothReady
                          ? 'Starting realtime match...'
                          : 'Waiting for both players...',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              if (!isPlayer1 && !isPlayer2)
                const Text(
                  'Warning: you are not a participant in this match.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.red,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _PlayerCard extends StatelessWidget {
  final String playerName;
  final bool ready;

  const _PlayerCard({
    required this.playerName,
    required this.ready,
  });

  @override
  Widget build(BuildContext context) {
    final color = ready ? Colors.green : Colors.orange;

    return Card(
      elevation: 0,
      color: color.withOpacity(0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: color.withOpacity(0.45),
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.18),
          child: Icon(
            ready ? Icons.check : Icons.schedule,
            color: color,
          ),
        ),
        title: Text(
          playerName,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          ready ? 'Ready' : 'Waiting...',
        ),
      ),
    );
  }
}
