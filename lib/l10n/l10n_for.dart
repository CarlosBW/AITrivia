import 'generated/app_localizations.dart';
import 'generated/app_localizations_en.dart';
import 'generated/app_localizations_es.dart';

/// Builds an [AppLocalizations] instance for an arbitrary language code
/// without a BuildContext, for use in services (exceptions, notification
/// text) that run outside the widget tree.
AppLocalizations l10nFor(String? languageCode) {
  return languageCode == 'en' ? AppLocalizationsEn() : AppLocalizationsEs();
}
