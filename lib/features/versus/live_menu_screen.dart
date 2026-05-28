import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'create_match_screen.dart';
import 'join_match_screen.dart';
import 'live_matchmaking_screen.dart';

class LiveMenuScreen extends StatefulWidget {
  const LiveMenuScreen({super.key});

  @override
  State<LiveMenuScreen> createState() => _LiveMenuScreenState();
}

class _LiveMenuScreenState extends State<LiveMenuScreen> {
  bool _useAi = false;

  final List<String> _fixedCategories = const [
    'cine',
    'historia',
    'videojuegos',
    'random',
  ];

  String _selectedCategoryId = 'cine';

  String _tierForRating(int rating) {
    if (rating >= 1800) return 'Diamond';
    if (rating >= 1500) return 'Platinum';
    if (rating >= 1300) return 'Gold';
    if (rating >= 1100) return 'Silver';
    return 'Bronze';
  }

  void _goMatchmaking({required bool ranked}) {
    if (_useAi) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Matchmaking con IA aún no está implementado.'),
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveMatchmakingScreen(
          categoryId: _selectedCategoryId,
          ranked: ranked,
          winReward: ranked ? 2 : 0,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    return Scaffold(
      appBar: AppBar(title: const Text('Tiempo real')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: userRef.snapshots(),
            builder: (context, snap) {
              final data = snap.data?.data() ?? {};
              final rating = ((data['pvpRating'] ?? 1000) as num).toInt();
              final delta = ((data['pvpRatingDelta'] ?? 0) as num).toInt();
              final tier = _tierForRating(rating);

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.deepPurple.withOpacity(0.22),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.shield, size: 38),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$tier League',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('$rating MMR'),
                        ],
                      ),
                    ),
                    if (delta != 0)
                      Text(
                        delta > 0 ? '+$delta' : '$delta',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: delta > 0 ? Colors.green : Colors.red,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 18),

          Row(
            children: [
              const Expanded(
                child: Text(
                  'Modo de juego',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(_useAi ? 'Con IA' : 'Sin IA'),
              Switch(
                value: _useAi,
                onChanged: (v) => setState(() => _useAi = v),
              ),
            ],
          ),

          const SizedBox(height: 12),

          if (!_useAi) ...[
            const Text(
              'Tema fijo',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedCategoryId,
              items: _fixedCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() => _selectedCategoryId = v);
              },
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ] else ...[
            const Text(
              '⚡ Modo IA seleccionado (próximamente)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
          ],

          const SizedBox(height: 22),

          const Text(
            'Matchmaking público',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          FilledButton.icon(
            onPressed: () => _goMatchmaking(ranked: true),
            icon: const Icon(Icons.emoji_events),
            label: const Text('Ranked Match'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => _goMatchmaking(ranked: false),
            icon: const Icon(Icons.sports_esports),
            label: const Text('Casual Match'),
          ),

          const SizedBox(height: 22),

          const Text(
            'Partidas privadas',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const CreateMatchScreen(),
                ),
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Crear sala privada'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const JoinMatchScreen(),
                ),
              );
            },
            icon: const Icon(Icons.login),
            label: const Text('Unirme con código'),
          ),

          const SizedBox(height: 28),

          const Text(
            'Ranked afecta tu MMR. Casual y salas privadas son para jugar sin presión.',
            style: TextStyle(color: Colors.black54),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
