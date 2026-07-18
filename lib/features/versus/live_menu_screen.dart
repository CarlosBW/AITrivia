import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/pvp_league_service.dart';
import 'create_match_screen.dart';
import 'join_match_screen.dart';
import 'live_matchmaking_screen.dart';

class LiveMenuScreen extends StatefulWidget {
  const LiveMenuScreen({super.key});

  @override
  State<LiveMenuScreen> createState() => _LiveMenuScreenState();
}

class _LiveMenuScreenState extends State<LiveMenuScreen> {
  final List<String> _fixedCategories = const [
    'cine',
    'historia',
    'videojuegos',
    'random',
  ];

  String _selectedCategoryId = 'cine';

  void _goMatchmaking() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LiveMatchmakingScreen(
          categoryId: _selectedCategoryId,
          ranked: true,
          winReward: 2,
        ),
      ),
    );
  }

  Widget _buildPvpLeagueCard({
    required int rating,
    required int delta,
  }) {
    final leagueService = PvpLeagueService.instance;
    final league = leagueService.leagueForRating(rating);
    final color = Color(league.colorValue);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: color.withOpacity(0.28),
        ),
      ),
      child: Row(
        children: [
          Text(
            league.emoji,
            style: const TextStyle(fontSize: 36),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${league.name} League',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 4),
                Text('$rating MMR'),
                const SizedBox(height: 4),
                const Text(
                  'Buscar rival afecta tu MMR y tu liga PvP.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                  ),
                ),
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
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: userRef.snapshots(),
            builder: (context, snap) {
              final data = snap.data?.data() ?? {};
              final rating =
                  ((data['pvpRating'] ?? PvpLeagueService.defaultRating)
                          as num)
                      .toInt();
              final delta = ((data['pvpRatingDelta'] ?? 0) as num).toInt();

              return _buildPvpLeagueCard(
                rating: rating,
                delta: delta,
              );
            },
          ),
          const SizedBox(height: 18),
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
          const SizedBox(height: 22),
          const Text(
            'Matchmaking público',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _goMatchmaking,
            icon: const Icon(Icons.emoji_events),
            label: const Text('Buscar rival'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Buscar rival afecta tu MMR, liga y estadísticas PvP.',
            style: TextStyle(color: Colors.black54, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
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
            'Las partidas privadas son amistosas y no afectan tu ranking.',
            style: TextStyle(color: Colors.black54),
            textAlign: TextAlign.center,
          ),
      ],
    );
  }
}