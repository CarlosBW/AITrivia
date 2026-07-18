import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'async_find_players_screen.dart';
import 'async_inbox_screen.dart';
import 'async_outbox_screen.dart';

class AsyncMenuScreen extends StatefulWidget {
  final int difficulty;
  final int timePerQuestionSec;
  final int totalQuestions;
  final int winReward;

  const AsyncMenuScreen({
    super.key,
    this.difficulty = 1,
    this.timePerQuestionSec = 10,
    this.totalQuestions = 10,
    this.winReward = 2,
  });

  @override
  State<AsyncMenuScreen> createState() => _AsyncMenuScreenState();
}

class _AsyncMenuScreenState extends State<AsyncMenuScreen> {
  String? _selectedCategoryId;

  Stream<QuerySnapshot<Map<String, dynamic>>> _fixedCategoriesStream() {
    return FirebaseFirestore.instance
        .collection('fixed_categories')
        .where('isActive', isEqualTo: true)
        .snapshots();
  }

  void _goFindPlayersFixed() {
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un tema fijo primero.')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AsyncFindPlayersScreen(
          categoryId: _selectedCategoryId!,
          difficulty: widget.difficulty,
          totalQuestions: widget.totalQuestions,
          timePerQuestionSec: widget.timePerQuestionSec,
          winReward: widget.winReward,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canStart = _selectedCategoryId != null;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            const SizedBox(height: 8),
            const Text(
              'Configuración',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            const Text(
              'Temas fijos',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),

            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _fixedCategoriesStream(),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Text('No hay categorías activas.');
                }

                // Set default si aún no hay seleccionado
                _selectedCategoryId ??= docs.first.id;

                return DropdownButtonFormField<String>(
                  initialValue: _selectedCategoryId,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Selecciona un tema fijo',
                  ),
                  items: docs.map((d) {
                    final data = d.data();
                    final name = (data['name'] ?? d.id).toString();
                    return DropdownMenuItem(
                      value: d.id,
                      child: Text(name),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _selectedCategoryId = v),
                );
              },
            ),

            const SizedBox(height: 16),

            FilledButton(
              onPressed: canStart ? _goFindPlayersFixed : null,
              child: const Text('Buscar jugador para retar'),
            ),

            const SizedBox(height: 12),

            OutlinedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AsyncInboxScreen()),
                );
              },
              child: const Text('Retos recibidos'),
            ),

            const SizedBox(height: 12),

            OutlinedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AsyncOutboxScreen()),
                );
              },
              child: const Text('Retos enviados'),
            ),

            const Spacer(),

            const Text(
              'Tip: Retas a alguien, juegas inmediatamente y tu rival puede jugar luego.',
              style: TextStyle(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}
