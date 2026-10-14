import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/league_service.dart';
import 'package:trivia_ia_flutter/services/pvp_league_service.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';
import 'package:trivia_ia_flutter/widgets/tier_badge.dart';

/// El nombre de la liga se escribe en el color de la liga, sobre una
/// pastilla tenida de ese color. En Noche, Diamond — un violeta oscuro —
/// casi no se distinguia; en los temas claros pasaba lo contrario con
/// Silver y Gold, demasiado palidos para leerse sobre su propio tinte.
void main() {
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  // Las dos familias de ligas que pintan un TierBadge: PvP y semanal.
  final tiers = <String, int>{
    for (final league in PvpLeagueService.leagues)
      'pvp ${league.id}': league.colorValue,
    for (final league in LeagueService.leagues)
      'semanal ${league.id}': league.colorValue,
  };

  Future<Color> nameColor(
    WidgetTester tester,
    AppThemeSpec spec,
    int colorValue,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: spec.colorScheme),
        home: Scaffold(
          body: TierBadge(emoji: '🏅', name: 'Liga', colorValue: colorValue),
        ),
      ),
    );

    return tester.widget<Text>(find.text('Liga')).style!.color!;
  }

  for (final spec in AppThemes.all) {
    testWidgets('en ${spec.id} el nombre de cada liga se lee en su pastilla',
        (tester) async {
      for (final tier in tiers.entries) {
        final chip = Color.alphaBlend(
          Color(tier.value).withValues(alpha: 0.16),
          spec.colorScheme.surface,
        );

        expect(
          contrast(await nameColor(tester, spec, tier.value), chip),
          greaterThanOrEqualTo(4.5),
          reason: tier.key,
        );
      }
    });
  }

  testWidgets('una liga que ya se lee conserva su color', (tester) async {
    // Diamond, un violeta profundo, se lee sobre un tinte claro tal cual.
    final diamond = PvpLeagueService.leagues
        .firstWhere((league) => league.id == 'diamond')
        .colorValue;

    expect(
      await nameColor(tester, AppThemes.byId(AppThemes.defaultId), diamond),
      Color(diamond),
    );
  });
}
