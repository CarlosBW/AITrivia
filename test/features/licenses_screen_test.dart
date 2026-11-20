import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/features/profile/licenses_screen.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';

void main() {
  const mit = LicenseEntryWithLineBreaks(['zebra', 'alpha'], 'MIT\n\nPermiso');
  const bsd = LicenseEntryWithLineBreaks(['alpha'], 'BSD');
  const font = LicenseEntryWithLineBreaks(['Baloo 2'], 'OFL');

  group('groupLicensesByPackage', () {
    test('junta las licencias de cada paquete y ordena por nombre', () {
      final grouped = groupLicensesByPackage([mit, bsd, font]);

      expect(grouped.map((p) => p.name), ['alpha', 'Baloo 2', 'zebra']);
      expect(grouped.first.entries, [mit, bsd]);
      expect(grouped.last.entries, [mit]);
    });

    test('sin licencias no hay paquetes', () {
      expect(groupLicensesByPackage(const []), isEmpty);
    });

    test('la misma licencia repetida en un paquete cuenta una vez', () {
      final grouped = groupLicensesByPackage([bsd, bsd]);
      expect(grouped.single.entries, [bsd]);
    });
  });

  group('LicensesScreen', () {
    Widget app() => MaterialApp(
          locale: const Locale('es'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LicensesScreen(
            licenses: Stream.fromIterable(const [mit, bsd, font]),
          ),
        );

    testWidgets('lista los paquetes con cuántas licencias trae cada uno',
        (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('2 licencias'), findsOneWidget);
      expect(find.text('Baloo 2'), findsOneWidget);
      expect(find.text('1 licencia'), findsNWidgets(2));
    });

    testWidgets('tocar un paquete abre el texto de su licencia',
        (tester) async {
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();

      await tester.tap(find.text('zebra'));
      await tester.pumpAndSettle();

      expect(find.text('MIT'), findsOneWidget);
      expect(find.text('Permiso'), findsOneWidget);
    });

    testWidgets('cabe en un teléfono estrecho con letra grande',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: app(),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
