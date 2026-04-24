import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../../services/match_service.dart';
import 'match_play_screen.dart';

class MatchLobbyScreen extends StatelessWidget {
  final String matchId;
  const MatchLobbyScreen({super.key, required this.matchId});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final service = MatchService();
    final ref = FirebaseFirestore.instance.collection('matches').doc(matchId);

    return Scaffold(
      appBar: AppBar(title: const Text('Sala 1 vs 1')),
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
          final mode = (data['mode'] ?? 'fixed').toString();
          final categoryId = (data['categoryId'] ?? 'cine').toString();

          final code = (data['matchCode'] ?? matchId).toString();

          final hostUid = data['hostUid'] as String?;
          final guestUid = data['guestUid'] as String?;

          final players = Map<String, dynamic>.from(data['players'] ?? {});
          final me = Map<String, dynamic>.from(players[uid] ?? {});
          final myReady = me['ready'] == true;

          final hasGuest = guestUid != null;

          // Evita navegar múltiples veces por rebuilds
          if (status == 'playing') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => MatchPlayScreen(matchId: matchId),
                ),
              );
            });
          }

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  'Código: $code',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  'ID: $matchId',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 12),

                Text('Modo: ${mode == 'fixed' ? 'Sin IA' : 'Con IA'}'),
                Text('Categoría: ${categoryId == 'random' ? 'Random' : categoryId}'),
                const SizedBox(height: 16),

                Text('Estado: $status'),
                const SizedBox(height: 16),

                Text('Jugador 1 (Host): ${hostUid ?? '(desconocido)'}'),
                Text('Jugador 2 (Guest): ${hasGuest ? guestUid : '(esperando...)'}'),

                const SizedBox(height: 16),

                if (mode == 'ai') ...[
                  Text('Tema IA: ${(data['aiTopic'] ?? '').toString()}'),
                  Text('Costo: ${(data['entryFee'] ?? 0)} monedas por jugador'),
                  Text('Recompensa ganador: ${(data['winReward'] ?? 0)} monedas'),
                  const SizedBox(height: 12),
                  const Text(
                    'Nota: por ahora esta sala AI no inicia hasta que implementemos Cloud Functions.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],

                const Spacer(),

                if (status == 'waiting') ...[
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: !hasGuest
                          ? null
                          : () async {
                              await service.setReady(matchId, !myReady);
                              // IMPORTANTE: si tu setReady no llama tryStartMatchIfReady,
                              // lo agregaremos ahí (mejor lugar). Por ahora no lo duplico aquí.
                            },
                      child: Text(myReady ? 'Quitar listo' : 'Estoy listo'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    !hasGuest
                        ? 'Comparte el código con tu amigo para que se una.'
                        : 'Cuando ambos estén listos, empieza automáticamente.',
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
