import 'package:flutter/material.dart';

import 'live_menu_screen.dart';
import 'async_menu_screen.dart';

class FindOpponentScreen extends StatelessWidget {
  const FindOpponentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Find Opponent'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LiveMenuScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.bolt),
              label: const Text('Real-time Matchmaking'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const AsyncMenuScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.schedule),
              label: const Text('Async Challenge'),
            ),
          ],
        ),
      ),
    );
  }
}