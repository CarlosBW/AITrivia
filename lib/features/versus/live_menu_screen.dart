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

  // ✅ Categorías fijas (luego las cargamos desde Firestore)
  final List<String> _fixedCategories = const [
    'cine',
    'historia',
    'videojuegos',
    'random',
  ];

  String _selectedCategoryId = 'cine';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tiempo real')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),

            // ======================================================
            // ✅ SWITCH IA / SIN IA
            // ======================================================
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
                  onChanged: (v) {
                    setState(() => _useAi = v);
                  },
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ======================================================
            // ✅ SOLO TEMAS FIJOS SI ES SIN IA
            // ======================================================
            if (!_useAi) ...[
              const Text(
                'Tema fijo',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),

              DropdownButtonFormField<String>(
                initialValue: _selectedCategoryId,
                items: _fixedCategories
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child: Text(c),
                      ),
                    )
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

              const SizedBox(height: 16),
            ] else ...[
              const Text(
                '⚡ Modo IA seleccionado (próximamente)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ======================================================
            // ✅ OPCIONES
            // ======================================================
            const Text(
              'Opciones',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            // ✅ Crear sala manual
            FilledButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const CreateMatchScreen(),
                  ),
                );
              },
              child: const Text('Crear sala'),
            ),

            const SizedBox(height: 12),

            // ✅ Unirse con código
            OutlinedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const JoinMatchScreen(),
                  ),
                );
              },
              child: const Text('Unirme con código'),
            ),

            const SizedBox(height: 12),

            // ✅ Buscar jugador automático
            FilledButton.tonal(
              onPressed: () {
                // 🚫 Si IA está activado, todavía no se implementa matchmaking IA
                if (_useAi) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Matchmaking con IA aún no está implementado.',
                      ),
                    ),
                  );
                  return;
                }

                // ✅ Solo Fixed matchmaking
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LiveMatchmakingScreen(
                      categoryId: _selectedCategoryId,
                    ),
                  ),
                );
              },
              child: const Text('Buscar jugador automático'),
            ),

            const Spacer(),

            const Text(
              'Buscar jugador automático: te empareja con alguien\n'
              'que esté buscando lo mismo en ese momento.',
              style: TextStyle(color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
