import 'package:flutter/material.dart';

import 'async_menu_screen.dart';
import 'live_menu_screen.dart';

class VersusMenuScreen extends StatelessWidget {
  const VersusMenuScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('1 vs 1')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            const Text(
              'Elige un modo',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            FilledButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const LiveMenuScreen()),
                );
              },
              child: const Text('Tiempo real'),
            ),
            const SizedBox(height: 12),

            OutlinedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AsyncMenuScreen()),
                );
              },
              child: const Text('Reto asíncrono'),
            ),

            const Spacer(),

            const Text(
              'Tiempo real: juegan al mismo tiempo.\n'
              'Reto asíncrono: retas y el otro juega cuando pueda.',
              style: TextStyle(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
