import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/pvp_league_service.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';
import 'package:trivia_ia_flutter/widgets/tier_badge.dart';

/// El nombre de la liga se escribe en el color de la liga, y esos colores
/// se eligieron sobre blanco. En Noche, "Liga Silver" quedaba en un gris
/// azulado apagado y Diamond, un violeta oscuro, casi no se distinguia.
void main() {
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  Future<Color> nameColor(
    WidgetTester tester,
    AppThemeSpec spec,
    PvpLeagueInfo league,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: spec.colorScheme),
        home: Scaffold(
          body: TierBadge(
            emoji: league.emoji,
            name: league.name,
            colorValue: league.colorValue,
          ),
        ),
      ),
    );

    return tester.widget<Text>(find.text(league.name)).style!.color!;
  }

  testWidgets('en el clasico el nombre lleva el color de su liga',
      (tester) async {
    final classic = AppThemes.byId(AppThemes.defaultId);

    for (final league in PvpLeagueService.leagues) {
      expect(
        await nameColor(tester, classic, league),
        Color(league.colorValue),
        reason: league.id,
      );
    }
  });

  testWidgets('en noche el nombre de cada liga se lee sobre una tarjeta',
      (tester) async {
    final night = AppThemes.byId(AppThemes.nightId);

    for (final league in PvpLeagueService.leagues) {
      expect(
        contrast(
          await nameColor(tester, night, league),
          night.colorScheme.surface,
        ),
        greaterThanOrEqualTo(4.5),
        reason: league.id,
      );
    }
  });
}
