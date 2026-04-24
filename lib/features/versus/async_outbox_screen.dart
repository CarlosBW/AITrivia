import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class AsyncOutboxScreen extends StatelessWidget {
  const AsyncOutboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseFirestore.instance.collection('async_matches');

    // Outbox = retos donde yo soy el challenger
    final query =
        ref.where('challengerUid', isEqualTo: uid).orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('Retos enviados')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return const Center(child: Text('No tienes retos enviados.'));
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final d = doc.data();

              final challengedName =
                  (d['challengedDisplayName'] ?? 'Player').toString();

              final myStatus = (d['challengerStatus'] ?? 'pending').toString();
              final otherStatus =
                  (d['challengedStatus'] ?? 'pending').toString();

              final status = (d['status'] ?? '').toString();
              final winnerUid = d['winnerUid'] as String?;

              final challengerScore =
                  ((d['challenger']?['score']) ?? 0) as int;
              final challengedScore =
                  ((d['challenged']?['score']) ?? 0) as int;

              String subtitle = 'Para: $challengedName';
              if (status == 'completed') {
                if (winnerUid == null) {
                  subtitle += ' • Empate ($challengerScore-$challengedScore)';
                } else if (winnerUid == uid) {
                  subtitle += ' • Ganaste ($challengerScore-$challengedScore)';
                } else {
                  subtitle += ' • Perdiste ($challengerScore-$challengedScore)';
                }
              } else {
                if (myStatus != 'finished') {
                  subtitle += ' • Te falta jugar';
                } else if (otherStatus != 'finished') {
                  subtitle += ' • Esperando que juegue rival';
                } else {
                  subtitle += ' • Listo para finalizar';
                }
              }

              return ListTile(
                title: Text('Reto: ${d['categoryId'] ?? 'fixed'}'),
                subtitle: Text(subtitle),
                trailing: status == 'completed'
                    ? const Icon(Icons.emoji_events_outlined)
                    : const Icon(Icons.hourglass_bottom),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Detalle del reto'),
                      content: Text(
                        'matchId: ${doc.id}\n'
                        'Rival: $challengedName\n'
                        'Tu score: $challengerScore\n'
                        'Score rival: $challengedScore\n'
                        'Status: $status\n',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cerrar'),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
