import 'package:flutter/material.dart';

import 'live_menu_screen.dart';
import 'async_menu_screen.dart';

class FindOpponentScreen extends StatelessWidget {
  const FindOpponentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Buscar rival'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Tiempo real'),
              Tab(text: 'Asíncrono'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            LiveMenuScreen(),
            AsyncMenuScreen(),
          ],
        ),
      ),
    );
  }
}
