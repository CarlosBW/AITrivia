import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es')
  ];

  /// No description provided for @langSwitchLabelEn.
  ///
  /// In es, this message translates to:
  /// **'EN'**
  String get langSwitchLabelEn;

  /// No description provided for @langSwitchLabelEs.
  ///
  /// In es, this message translates to:
  /// **'ES'**
  String get langSwitchLabelEs;

  /// No description provided for @navChallengeAcceptedTitle.
  ///
  /// In es, this message translates to:
  /// **'Reto aceptado'**
  String get navChallengeAcceptedTitle;

  /// No description provided for @navChallengeAcceptedBodyFallback.
  ///
  /// In es, this message translates to:
  /// **'Tu invitación fue aceptada.'**
  String get navChallengeAcceptedBodyFallback;

  /// No description provided for @navLater.
  ///
  /// In es, this message translates to:
  /// **'Luego'**
  String get navLater;

  /// No description provided for @navPlayNow.
  ///
  /// In es, this message translates to:
  /// **'Jugar ahora'**
  String get navPlayNow;

  /// No description provided for @navNewNotificationTitle.
  ///
  /// In es, this message translates to:
  /// **'Nueva notificación'**
  String get navNewNotificationTitle;

  /// No description provided for @navNewNotificationSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Revisa la campana'**
  String get navNewNotificationSubtitle;

  /// No description provided for @commonCancel.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get commonCancel;

  /// No description provided for @commonSave.
  ///
  /// In es, this message translates to:
  /// **'Guardar'**
  String get commonSave;

  /// No description provided for @commonRetry.
  ///
  /// In es, this message translates to:
  /// **'Reintentar'**
  String get commonRetry;

  /// No description provided for @commonLoading.
  ///
  /// In es, this message translates to:
  /// **'Cargando...'**
  String get commonLoading;

  /// No description provided for @commonSaving.
  ///
  /// In es, this message translates to:
  /// **'Guardando...'**
  String get commonSaving;

  /// No description provided for @homeActionTimeout.
  ///
  /// In es, this message translates to:
  /// **'La acción tardó demasiado.'**
  String get homeActionTimeout;

  /// No description provided for @homeCoins.
  ///
  /// In es, this message translates to:
  /// **'Monedas'**
  String get homeCoins;

  /// No description provided for @homeXp.
  ///
  /// In es, this message translates to:
  /// **'XP'**
  String get homeXp;

  /// No description provided for @homeFreeTopic.
  ///
  /// In es, this message translates to:
  /// **'Tema libre'**
  String get homeFreeTopic;

  /// No description provided for @homeAlreadyPlayedDaily.
  ///
  /// In es, this message translates to:
  /// **'Ya jugaste el Daily Challenge de hoy.'**
  String get homeAlreadyPlayedDaily;

  /// No description provided for @homeMoreWaysToPlay.
  ///
  /// In es, this message translates to:
  /// **'Más formas de jugar'**
  String get homeMoreWaysToPlay;

  /// No description provided for @homeWeeklyChallengeReward.
  ///
  /// In es, this message translates to:
  /// **'Weekly Challenge • ¡Recompensa!'**
  String get homeWeeklyChallengeReward;

  /// No description provided for @homeWeeklyChallenge.
  ///
  /// In es, this message translates to:
  /// **'Weekly Challenge'**
  String get homeWeeklyChallenge;

  /// No description provided for @homeTabsHint.
  ///
  /// In es, this message translates to:
  /// **'Usa las pestañas inferiores para jugar SOLO, competir en PvP, retar amigos y ver tu perfil.'**
  String get homeTabsHint;

  /// No description provided for @homeStreakUpTitle.
  ///
  /// In es, this message translates to:
  /// **'🔥 ¡RACHA!'**
  String get homeStreakUpTitle;

  /// No description provided for @homeStreakUpSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Sigue volviendo cada día'**
  String get homeStreakUpSubtitle;

  /// No description provided for @homeWelcomeBackTitle.
  ///
  /// In es, this message translates to:
  /// **'📅 ¡Volviste!'**
  String get homeWelcomeBackTitle;

  /// No description provided for @homeLoginStreakLabel.
  ///
  /// In es, this message translates to:
  /// **'Racha de sesión: {days} días'**
  String homeLoginStreakLabel(int days);

  /// No description provided for @homeLoginStreakCoins.
  ///
  /// In es, this message translates to:
  /// **'+{coins} monedas'**
  String homeLoginStreakCoins(int coins);

  /// No description provided for @homeLivesSuffix.
  ///
  /// In es, this message translates to:
  /// **'{lives} vidas'**
  String homeLivesSuffix(String lives);

  /// No description provided for @homeLivesFull.
  ///
  /// In es, this message translates to:
  /// **'Vidas al máximo'**
  String get homeLivesFull;

  /// No description provided for @homeAiTopicTitle.
  ///
  /// In es, this message translates to:
  /// **'Tema libre (IA)'**
  String get homeAiTopicTitle;

  /// No description provided for @homeAiTopicSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Crea tu propio tema y juega con tus monedas'**
  String get homeAiTopicSubtitle;

  /// No description provided for @homeWeeklyTopicUnavailable.
  ///
  /// In es, this message translates to:
  /// **'Weekly Topic no disponible'**
  String get homeWeeklyTopicUnavailable;

  /// No description provided for @homeWeeklyTopicNoneAvailable.
  ///
  /// In es, this message translates to:
  /// **'No hay Weekly Topic disponible'**
  String get homeWeeklyTopicNoneAvailable;

  /// No description provided for @homeWeeklyTopicCheckBack.
  ///
  /// In es, this message translates to:
  /// **'Vuelve pronto para un nuevo reto destacado.'**
  String get homeWeeklyTopicCheckBack;

  /// No description provided for @homeWeeklyTopicLoading.
  ///
  /// In es, this message translates to:
  /// **'Cargando Weekly Topic...'**
  String get homeWeeklyTopicLoading;

  /// No description provided for @homeOpenWeeklyTopic.
  ///
  /// In es, this message translates to:
  /// **'Abrir Weekly Topic'**
  String get homeOpenWeeklyTopic;

  /// No description provided for @homeWeeklyTopicRewardCoins.
  ///
  /// In es, this message translates to:
  /// **'+{coins} monedas'**
  String homeWeeklyTopicRewardCoins(int coins);

  /// No description provided for @homeDailyChallengeTitle.
  ///
  /// In es, this message translates to:
  /// **'Daily Challenge'**
  String get homeDailyChallengeTitle;

  /// No description provided for @homeDailyChallengeStreak.
  ///
  /// In es, this message translates to:
  /// **'Racha: {days} días'**
  String homeDailyChallengeStreak(int days);

  /// No description provided for @homeReward.
  ///
  /// In es, this message translates to:
  /// **'¡Recompensa!'**
  String get homeReward;

  /// No description provided for @profileTitle.
  ///
  /// In es, this message translates to:
  /// **'Perfil de jugador'**
  String get profileTitle;

  /// No description provided for @profileEditUsername.
  ///
  /// In es, this message translates to:
  /// **'Editar nombre de usuario'**
  String get profileEditUsername;

  /// No description provided for @profileEnterUsername.
  ///
  /// In es, this message translates to:
  /// **'Ingresa tu nombre de usuario'**
  String get profileEnterUsername;

  /// No description provided for @profileUsernameHelper.
  ///
  /// In es, this message translates to:
  /// **'Debe ser único. Usa 3 a 20 caracteres.'**
  String get profileUsernameHelper;

  /// No description provided for @profileUsernameLengthError.
  ///
  /// In es, this message translates to:
  /// **'El nombre de usuario debe tener entre 3 y 20 caracteres.'**
  String get profileUsernameLengthError;

  /// No description provided for @profileUsernameCharsError.
  ///
  /// In es, this message translates to:
  /// **'Usa solo letras, números y guion bajo.'**
  String get profileUsernameCharsError;

  /// No description provided for @profileUsernameTaken.
  ///
  /// In es, this message translates to:
  /// **'Ese nombre de usuario ya existe.'**
  String get profileUsernameTaken;

  /// No description provided for @profileUpdateError.
  ///
  /// In es, this message translates to:
  /// **'Error actualizando perfil: {error}'**
  String profileUpdateError(String error);

  /// No description provided for @profileUpdated.
  ///
  /// In es, this message translates to:
  /// **'Perfil actualizado'**
  String get profileUpdated;

  /// No description provided for @profileAvatarCollection.
  ///
  /// In es, this message translates to:
  /// **'Colección de avatares'**
  String get profileAvatarCollection;

  /// No description provided for @profileUnlockedCount.
  ///
  /// In es, this message translates to:
  /// **'Desbloqueados {count} / {total}'**
  String profileUnlockedCount(int count, int total);

  /// No description provided for @profileCurrentlyEquipped.
  ///
  /// In es, this message translates to:
  /// **'Equipado actualmente'**
  String get profileCurrentlyEquipped;

  /// No description provided for @profileChooseFrame.
  ///
  /// In es, this message translates to:
  /// **'Elegir marco'**
  String get profileChooseFrame;

  /// No description provided for @profileEquippedNotice.
  ///
  /// In es, this message translates to:
  /// **'{emoji} {name} equipado'**
  String profileEquippedNotice(String emoji, String name);

  /// No description provided for @profileAvatarUpdateError.
  ///
  /// In es, this message translates to:
  /// **'Error actualizando avatar: {error}'**
  String profileAvatarUpdateError(String error);

  /// No description provided for @profileLevel.
  ///
  /// In es, this message translates to:
  /// **'Nivel {level}'**
  String profileLevel(int level);

  /// No description provided for @profileWeeklyScore.
  ///
  /// In es, this message translates to:
  /// **'Puntaje semanal: {score}'**
  String profileWeeklyScore(int score);

  /// No description provided for @profileXpToNextLevel.
  ///
  /// In es, this message translates to:
  /// **'{current} / {required} XP para el siguiente nivel'**
  String profileXpToNextLevel(int current, int required);

  /// No description provided for @profileAchievements.
  ///
  /// In es, this message translates to:
  /// **'Logros'**
  String get profileAchievements;

  /// No description provided for @profileAchievementsSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Revisa tu progreso y recompensas'**
  String get profileAchievementsSubtitle;

  /// No description provided for @profileCoins.
  ///
  /// In es, this message translates to:
  /// **'Monedas'**
  String get profileCoins;

  /// No description provided for @profileFreeTopics.
  ///
  /// In es, this message translates to:
  /// **'Temas gratis'**
  String get profileFreeTopics;

  /// No description provided for @profileStreak.
  ///
  /// In es, this message translates to:
  /// **'Racha'**
  String get profileStreak;

  /// No description provided for @profileBestStreak.
  ///
  /// In es, this message translates to:
  /// **'Mejor racha'**
  String get profileBestStreak;

  /// No description provided for @profileStats.
  ///
  /// In es, this message translates to:
  /// **'Estadísticas'**
  String get profileStats;

  /// No description provided for @profileGamesPlayed.
  ///
  /// In es, this message translates to:
  /// **'Partidas jugadas'**
  String get profileGamesPlayed;

  /// No description provided for @profileCorrectAnswers.
  ///
  /// In es, this message translates to:
  /// **'Respuestas correctas'**
  String get profileCorrectAnswers;

  /// No description provided for @profileWrongAnswers.
  ///
  /// In es, this message translates to:
  /// **'Respuestas incorrectas'**
  String get profileWrongAnswers;

  /// No description provided for @profileAccuracy.
  ///
  /// In es, this message translates to:
  /// **'Precisión'**
  String get profileAccuracy;

  /// No description provided for @profileBestDailyScore.
  ///
  /// In es, this message translates to:
  /// **'Mejor puntaje diario'**
  String get profileBestDailyScore;

  /// No description provided for @profilePvpLeague.
  ///
  /// In es, this message translates to:
  /// **'Liga PvP {league}'**
  String profilePvpLeague(String league);

  /// No description provided for @profileRankedHint.
  ///
  /// In es, this message translates to:
  /// **'Ranked busca primero rivales de tu liga y amplía el rango si no hay jugadores disponibles.'**
  String get profileRankedHint;

  /// No description provided for @profile1v1Stats.
  ///
  /// In es, this message translates to:
  /// **'Estadísticas 1 vs 1'**
  String get profile1v1Stats;

  /// No description provided for @profileRankedMmr.
  ///
  /// In es, this message translates to:
  /// **'MMR clasificado'**
  String get profileRankedMmr;

  /// No description provided for @profileVictories.
  ///
  /// In es, this message translates to:
  /// **'Victorias'**
  String get profileVictories;

  /// No description provided for @profileDefeats.
  ///
  /// In es, this message translates to:
  /// **'Derrotas'**
  String get profileDefeats;

  /// No description provided for @profileDraws.
  ///
  /// In es, this message translates to:
  /// **'Empates'**
  String get profileDraws;

  /// No description provided for @profileMatchesPlayed.
  ///
  /// In es, this message translates to:
  /// **'Partidas jugadas'**
  String get profileMatchesPlayed;

  /// No description provided for @profileWinrate.
  ///
  /// In es, this message translates to:
  /// **'% de victorias'**
  String get profileWinrate;

  /// No description provided for @profileCurrentStreak.
  ///
  /// In es, this message translates to:
  /// **'Racha actual'**
  String get profileCurrentStreak;

  /// No description provided for @profileRecentMatches.
  ///
  /// In es, this message translates to:
  /// **'Partidas PvP recientes'**
  String get profileRecentMatches;

  /// No description provided for @profileNoMatches.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay partidas PvP.'**
  String get profileNoMatches;

  /// No description provided for @profileVsOpponent.
  ///
  /// In es, this message translates to:
  /// **'vs {opponent}'**
  String profileVsOpponent(String opponent);

  /// No description provided for @profileScore.
  ///
  /// In es, this message translates to:
  /// **'Puntaje'**
  String get profileScore;

  /// No description provided for @profileRanked.
  ///
  /// In es, this message translates to:
  /// **'Clasificado'**
  String get profileRanked;

  /// No description provided for @profileCasual.
  ///
  /// In es, this message translates to:
  /// **'Casual'**
  String get profileCasual;

  /// No description provided for @profileErrorLoading.
  ///
  /// In es, this message translates to:
  /// **'Error cargando perfil:\n{error}'**
  String profileErrorLoading(String error);

  /// No description provided for @matchResultVictory.
  ///
  /// In es, this message translates to:
  /// **'Victoria'**
  String get matchResultVictory;

  /// No description provided for @matchResultDefeat.
  ///
  /// In es, this message translates to:
  /// **'Derrota'**
  String get matchResultDefeat;

  /// No description provided for @matchResultDraw.
  ///
  /// In es, this message translates to:
  /// **'Empate'**
  String get matchResultDraw;

  /// No description provided for @matchResultMatch.
  ///
  /// In es, this message translates to:
  /// **'Partida'**
  String get matchResultMatch;

  /// No description provided for @avatarCategoryBase.
  ///
  /// In es, this message translates to:
  /// **'BASE'**
  String get avatarCategoryBase;

  /// No description provided for @avatarCategoryPvp.
  ///
  /// In es, this message translates to:
  /// **'PVP'**
  String get avatarCategoryPvp;

  /// No description provided for @avatarCategoryWeekly.
  ///
  /// In es, this message translates to:
  /// **'SEMANAL'**
  String get avatarCategoryWeekly;

  /// No description provided for @avatarCategoryAchievement.
  ///
  /// In es, this message translates to:
  /// **'LOGRO'**
  String get avatarCategoryAchievement;

  /// No description provided for @avatarCategoryAi.
  ///
  /// In es, this message translates to:
  /// **'IA'**
  String get avatarCategoryAi;

  /// No description provided for @avatarCategoryAiUnique.
  ///
  /// In es, this message translates to:
  /// **'IA ÚNICO'**
  String get avatarCategoryAiUnique;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
