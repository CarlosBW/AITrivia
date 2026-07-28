import 'package:flutter/material.dart';

import 'live_menu_screen.dart';
import 'async_menu_screen.dart';
import '../../l10n/generated/app_localizations.dart';

class FindOpponentScreen extends StatelessWidget {
  const FindOpponentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.findOpponentTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.findOpponentLiveTab),
              Tab(text: l10n.findOpponentAsyncTab),
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
