import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class RealtimeMatchLobbyScreen extends StatelessWidget {
  final String matchId;

  const RealtimeMatchLobbyScreen({
    super.key,
    required this.matchId,
  });

  @override
  Widget build(BuildContext context) {
    final matchRef = FirebaseFirestore.instance
        .collection('matches')
        .doc(matchId);

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

          final player1Name =
              (data['player1Name'] ?? 'Player 1').toString();

          final player2Name =
              (data['player2Name'] ?? 'Player 2').toString();

          final player1Ready = data['player1Ready'] == true;
          final player2Ready = data['player2Ready'] == true;

          final status = (data['status'] ?? 'waiting').toString();

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
                      'Match ID: $matchId',
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

              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  children: [
                    const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      status == 'ready'
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