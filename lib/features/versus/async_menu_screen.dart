import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'async_find_players_screen.dart';
import '../../l10n/generated/app_localizations.dart';

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
        SnackBar(content: Text(AppLocalizations.of(context).asyncMenuSelectTopicFirst)),
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
    final l10n = AppLocalizations.of(context);
    final canStart = _selectedCategoryId != null;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
            const SizedBox(height: 8),
            Text(
              l10n.asyncMenuConfigTitle,
              style: GoogleFonts.baloo2(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),

            Text(
              l10n.asyncMenuFixedTopicsLabel,
              style: const TextStyle(fontWeight: FontWeight.bold),
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
                  return Text(l10n.asyncMenuNoActiveCategories);
                }

                // Set default si aún no hay seleccionado
                _selectedCategoryId ??= docs.first.id;

                return DropdownButtonFormField<String>(
                  initialValue: _selectedCategoryId,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: l10n.asyncMenuSelectTopicLabel,
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
              child: Text(l10n.asyncMenuFindPlayerButton),
            ),

            const Spacer(),

            Text(
              l10n.asyncMenuTip,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}
