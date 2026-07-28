import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../features/auth/auth_gate.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/locale_controller.dart';
import '../theme/app_theme.dart';

class TriviaIAApp extends StatelessWidget {
  const TriviaIAApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LocaleController.instance.locale,
      builder: (context, locale, _) {
        return MaterialApp(
          title: 'TriviaIA',
          debugShowCheckedModeBanner: false,
          theme: buildAppTheme(),
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const AuthGate(),
        );
      },
    );
  }
}
