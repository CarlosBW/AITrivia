import '../services/life_service.dart';
import 'generated/app_localizations.dart';

/// Lives as the player's language writes them: 4,5 in Spanish, 4.5 in
/// English.
extension LivesFormat on AppLocalizations {
  String lives(int units) {
    return LifeService.instance.formatLives(
      units,
      decimalSeparator: localeName.startsWith('es') ? ',' : '.',
    );
  }
}
