import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../features/auth/auth_gate.dart';
import '../features/onboarding/language_picker_screen.dart';
import '../l10n/generated/app_localizations.dart';
import '../services/locale_controller.dart';
import '../services/theme_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_themes.dart';

class TriviaIAApp extends StatelessWidget {
  const TriviaIAApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale>(
      valueListenable: LocaleController.instance.locale,
      builder: (context, locale, _) {
        return ValueListenableBuilder<String>(
          // Nested rather than merged into one listenable: the theme has to
          // be applied above every screen, and this is the only place that
          // is true. Equipping a theme repaints the app from here without
          // any screen knowing a theme exists.
          valueListenable: ThemeService.instance.equippedThemeId,
          builder: (context, themeId, _) => _buildApp(locale, themeId),
        );
      },
    );
  }

  Widget _buildApp(Locale locale, String themeId) {
    return MaterialApp(
      title: 'TriviaIA',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(AppThemes.byId(themeId)),
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const LanguageGate(),
    );
  }
}

/// Shows the first-launch language picker before anything else in the app
/// (including auth) if the player has never explicitly chosen a language;
/// otherwise goes straight to [AuthGate].
class LanguageGate extends StatefulWidget {
  const LanguageGate({super.key});

  @override
  State<LanguageGate> createState() => _LanguageGateState();
}

class _LanguageGateState extends State<LanguageGate> {
  bool? _needsPicker;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final hasChoice = await LocaleController.instance.hasExplicitChoice();
    if (!mounted) return;
    setState(() => _needsPicker = !hasChoice);
  }

  @override
  Widget build(BuildContext context) {
    if (_needsPicker == null) {
      return const Scaffold(body: SizedBox.shrink());
    }

    if (_needsPicker!) {
      return LanguagePickerScreen(
        onSelected: () => setState(() => _needsPicker = false),
      );
    }

    return const AuthGate();
  }
}
