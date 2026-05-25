import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'async_match_play_screen.dart';

class AsyncInboxScreen extends StatelessWidget {
  const AsyncInboxScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseFirestore.instance.collection('async_matches');

    final query = ref
        .where('challengedUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('Retos recibidos')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error cargando retos recibidos:\n${snap.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            );
          }

          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snap.data!.docs;

          if (docs.isEmpty) {
            return const Center(child: Text('No tienes retos recibidos.'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final doc = docs[i];
              final d = doc.data();

              final challengerName =
                  (d['challengerDisplayName'] ?? 'Player').toString();

              final myStatus = (d['challengedStatus'] ?? 'pending').toString();
              final status = (d['status'] ?? '').toString();

              final challengerScore =
                  ((d['challenger']?['score']) ?? 0) as int;
              final challengedScore =
                  ((d['challenged']?['score']) ?? 0) as int;

              final winnerUid = d['winnerUid'] as String?;
              final canPlay = myStatus != 'finished';

              String subtitle = 'De: $challengerName';

              if (status == 'completed') {
                if (winnerUid == null) {
                  subtitle += ' • Empate ($challengerScore-$challengedScore)';
                } else if (winnerUid == uid) {
                  subtitle += ' • Ganaste ($challengerScore-$challengedScore)';
                } else {
                  subtitle += ' • Perdiste ($challengerScore-$challengedScore)';
                }
              } else {
                if (myStatus == 'finished') {
                  subtitle += ' • Ya jugaste • Esperando rival';
                } else {
                  subtitle += ' • Pendiente de jugar';
                }
              }

              return Card(
                elevation: 0,
                color: Colors.black12,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    child: Icon(
                      canPlay ? Icons.play_arrow : Icons.check_circle_outline,
                    ),
                  ),
                  title: Text(
                    'Reto: ${d['categoryId'] ?? 'fixed'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    if (!canPlay) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Ya jugaste este reto.'),
                        ),
                      );
                      return;
                    }

                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AsyncMatchPlayScreen(
                          asyncMatchId: doc.id,
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}