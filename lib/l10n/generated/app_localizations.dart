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

  /// No description provided for @homeWeeklyResetsIn.
  ///
  /// In es, this message translates to:
  /// **'Termina en {time}'**
  String homeWeeklyResetsIn(String time);

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

  /// No description provided for @homeAchievementUnlockedTitle.
  ///
  /// In es, this message translates to:
  /// **'🏆 ¡Logro desbloqueado!'**
  String get homeAchievementUnlockedTitle;

  /// No description provided for @homeAchievementUnlockedSubtitle.
  ///
  /// In es, this message translates to:
  /// **'{icon} {title}'**
  String homeAchievementUnlockedSubtitle(String icon, String title);

  /// No description provided for @homeAchievementUnlockedRewards.
  ///
  /// In es, this message translates to:
  /// **'Recompensa lista: +{coins} monedas · +{xp} XP — reclámala en Logros'**
  String homeAchievementUnlockedRewards(int coins, int xp);

  /// No description provided for @homeAvatarUnlockedTitle.
  ///
  /// In es, this message translates to:
  /// **'🎁 ¡Nuevo avatar desbloqueado!'**
  String get homeAvatarUnlockedTitle;

  /// No description provided for @homeAvatarUnlockedSubtitle.
  ///
  /// In es, this message translates to:
  /// **'{emoji} {name}'**
  String homeAvatarUnlockedSubtitle(String emoji, String name);

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

  /// No description provided for @homeStatsErrorLoading.
  ///
  /// In es, this message translates to:
  /// **'Error cargando tus monedas y XP:\n{error}'**
  String homeStatsErrorLoading(String error);

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

  /// No description provided for @homeWeeklyTopicDefaultDescription.
  ///
  /// In es, this message translates to:
  /// **'Completa niveles y gana recompensas.'**
  String get homeWeeklyTopicDefaultDescription;

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

  /// No description provided for @usernamePickerTitle.
  ///
  /// In es, this message translates to:
  /// **'Elige tu nombre de usuario'**
  String get usernamePickerTitle;

  /// No description provided for @usernamePickerSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Tus amigos te encontrarán por este nombre. No podrás cambiarlo después.'**
  String get usernamePickerSubtitle;

  /// No description provided for @usernamePickerHint.
  ///
  /// In es, this message translates to:
  /// **'Nombre de usuario'**
  String get usernamePickerHint;

  /// No description provided for @usernamePickerContinue.
  ///
  /// In es, this message translates to:
  /// **'Continuar'**
  String get usernamePickerContinue;

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

  /// No description provided for @profileLegalSectionTitle.
  ///
  /// In es, this message translates to:
  /// **'Legal'**
  String get profileLegalSectionTitle;

  /// No description provided for @profilePrivacyPolicy.
  ///
  /// In es, this message translates to:
  /// **'Política de Privacidad'**
  String get profilePrivacyPolicy;

  /// No description provided for @profileTermsOfService.
  ///
  /// In es, this message translates to:
  /// **'Términos de Servicio'**
  String get profileTermsOfService;

  /// No description provided for @profileLinkOpenFailed.
  ///
  /// In es, this message translates to:
  /// **'No se pudo abrir el enlace.'**
  String get profileLinkOpenFailed;

  /// No description provided for @profileDangerZoneTitle.
  ///
  /// In es, this message translates to:
  /// **'Zona peligrosa'**
  String get profileDangerZoneTitle;

  /// No description provided for @profileDeleteAccount.
  ///
  /// In es, this message translates to:
  /// **'Eliminar cuenta'**
  String get profileDeleteAccount;

  /// No description provided for @profileDeleteAccountConfirmTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Eliminar tu cuenta?'**
  String get profileDeleteAccountConfirmTitle;

  /// No description provided for @profileDeleteAccountConfirmBody.
  ///
  /// In es, this message translates to:
  /// **'Esto borra tu perfil, progreso, monedas, amigos y temas creados de forma permanente. No se puede deshacer.'**
  String get profileDeleteAccountConfirmBody;

  /// No description provided for @profileDeleteAccountConfirmAction.
  ///
  /// In es, this message translates to:
  /// **'Eliminar permanentemente'**
  String get profileDeleteAccountConfirmAction;

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

  /// No description provided for @avatarNameBrain.
  ///
  /// In es, this message translates to:
  /// **'Cerebro'**
  String get avatarNameBrain;

  /// No description provided for @avatarNameRocket.
  ///
  /// In es, this message translates to:
  /// **'Cohete'**
  String get avatarNameRocket;

  /// No description provided for @avatarNameGamer.
  ///
  /// In es, this message translates to:
  /// **'Gamer'**
  String get avatarNameGamer;

  /// No description provided for @avatarNameFire.
  ///
  /// In es, this message translates to:
  /// **'Fuego'**
  String get avatarNameFire;

  /// No description provided for @avatarNameStar.
  ///
  /// In es, this message translates to:
  /// **'Estrella'**
  String get avatarNameStar;

  /// No description provided for @avatarNameCat.
  ///
  /// In es, this message translates to:
  /// **'Gato'**
  String get avatarNameCat;

  /// No description provided for @avatarNameRobot.
  ///
  /// In es, this message translates to:
  /// **'Robot'**
  String get avatarNameRobot;

  /// No description provided for @avatarNameTrophy.
  ///
  /// In es, this message translates to:
  /// **'Trofeo'**
  String get avatarNameTrophy;

  /// No description provided for @avatarUnlockDefault.
  ///
  /// In es, this message translates to:
  /// **'Avatar por defecto'**
  String get avatarUnlockDefault;

  /// No description provided for @avatarNamePvpBronze.
  ///
  /// In es, this message translates to:
  /// **'Retador de Bronce'**
  String get avatarNamePvpBronze;

  /// No description provided for @avatarNamePvpSilver.
  ///
  /// In es, this message translates to:
  /// **'Retador de Plata'**
  String get avatarNamePvpSilver;

  /// No description provided for @avatarNamePvpGold.
  ///
  /// In es, this message translates to:
  /// **'Campeón de Oro'**
  String get avatarNamePvpGold;

  /// No description provided for @avatarNamePvpPlatinum.
  ///
  /// In es, this message translates to:
  /// **'Élite de Platino'**
  String get avatarNamePvpPlatinum;

  /// No description provided for @avatarNamePvpDiamond.
  ///
  /// In es, this message translates to:
  /// **'Élite de Diamante'**
  String get avatarNamePvpDiamond;

  /// No description provided for @avatarNamePvpMaster.
  ///
  /// In es, this message translates to:
  /// **'Campeón Maestro'**
  String get avatarNamePvpMaster;

  /// No description provided for @avatarUnlockReachBronze.
  ///
  /// In es, this message translates to:
  /// **'Alcanza la Liga Bronce'**
  String get avatarUnlockReachBronze;

  /// No description provided for @avatarUnlockReachSilver.
  ///
  /// In es, this message translates to:
  /// **'Alcanza la Liga Plata'**
  String get avatarUnlockReachSilver;

  /// No description provided for @avatarUnlockReachGold.
  ///
  /// In es, this message translates to:
  /// **'Alcanza la Liga Oro'**
  String get avatarUnlockReachGold;

  /// No description provided for @avatarUnlockReachPlatinum.
  ///
  /// In es, this message translates to:
  /// **'Alcanza la Liga Platino'**
  String get avatarUnlockReachPlatinum;

  /// No description provided for @avatarUnlockReachDiamond.
  ///
  /// In es, this message translates to:
  /// **'Alcanza la Liga Diamante'**
  String get avatarUnlockReachDiamond;

  /// No description provided for @avatarUnlockReachMaster.
  ///
  /// In es, this message translates to:
  /// **'Alcanza la Liga Maestro'**
  String get avatarUnlockReachMaster;

  /// No description provided for @avatarNameWeeklyCine.
  ///
  /// In es, this message translates to:
  /// **'Experto en Cine'**
  String get avatarNameWeeklyCine;

  /// No description provided for @avatarNameWeeklyHistory.
  ///
  /// In es, this message translates to:
  /// **'Erudito de Historia'**
  String get avatarNameWeeklyHistory;

  /// No description provided for @avatarNameWeeklyScience.
  ///
  /// In es, this message translates to:
  /// **'Mente Científica'**
  String get avatarNameWeeklyScience;

  /// No description provided for @avatarNameWeeklySports.
  ///
  /// In es, this message translates to:
  /// **'Campeón Deportivo'**
  String get avatarNameWeeklySports;

  /// No description provided for @avatarNameWeeklyMusic.
  ///
  /// In es, this message translates to:
  /// **'Maestro Musical'**
  String get avatarNameWeeklyMusic;

  /// No description provided for @avatarNameWeeklyArt.
  ///
  /// In es, this message translates to:
  /// **'Conocedor de Arte'**
  String get avatarNameWeeklyArt;

  /// No description provided for @avatarNameWeeklyGeography.
  ///
  /// In es, this message translates to:
  /// **'Trotamundos'**
  String get avatarNameWeeklyGeography;

  /// No description provided for @avatarNameWeeklyVideogames.
  ///
  /// In es, this message translates to:
  /// **'Maestro de Juegos'**
  String get avatarNameWeeklyVideogames;

  /// No description provided for @avatarNameWeeklyBooks.
  ///
  /// In es, this message translates to:
  /// **'Ratón de Biblioteca'**
  String get avatarNameWeeklyBooks;

  /// No description provided for @avatarUnlockWeeklyCine.
  ///
  /// In es, this message translates to:
  /// **'Completa un Tema Semanal de Cine'**
  String get avatarUnlockWeeklyCine;

  /// No description provided for @avatarUnlockWeeklyHistory.
  ///
  /// In es, this message translates to:
  /// **'Completa un Tema Semanal de Historia'**
  String get avatarUnlockWeeklyHistory;

  /// No description provided for @avatarUnlockWeeklyScience.
  ///
  /// In es, this message translates to:
  /// **'Completa un Tema Semanal de Ciencia'**
  String get avatarUnlockWeeklyScience;

  /// No description provided for @avatarUnlockWeeklySports.
  ///
  /// In es, this message translates to:
  /// **'Completa un Tema Semanal de Deportes'**
  String get avatarUnlockWeeklySports;

  /// No description provided for @avatarUnlockWeeklyMusic.
  ///
  /// In es, this message translates to:
  /// **'Completa un Tema Semanal de Música'**
  String get avatarUnlockWeeklyMusic;

  /// No description provided for @avatarUnlockWeeklyArt.
  ///
  /// In es, this message translates to:
  /// **'Completa un Tema Semanal de Arte'**
  String get avatarUnlockWeeklyArt;

  /// No description provided for @avatarUnlockWeeklyGeography.
  ///
  /// In es, this message translates to:
  /// **'Completa un Tema Semanal de Geografía'**
  String get avatarUnlockWeeklyGeography;

  /// No description provided for @avatarUnlockWeeklyVideogames.
  ///
  /// In es, this message translates to:
  /// **'Completa un Tema Semanal de Videojuegos'**
  String get avatarUnlockWeeklyVideogames;

  /// No description provided for @avatarUnlockWeeklyBooks.
  ///
  /// In es, this message translates to:
  /// **'Completa un Tema Semanal de Libros'**
  String get avatarUnlockWeeklyBooks;

  /// No description provided for @avatarName100Questions.
  ///
  /// In es, this message translates to:
  /// **'100 Respuestas'**
  String get avatarName100Questions;

  /// No description provided for @avatarUnlock100Questions.
  ///
  /// In es, this message translates to:
  /// **'Responde 100 preguntas'**
  String get avatarUnlock100Questions;

  /// No description provided for @avatarName1000Questions.
  ///
  /// In es, this message translates to:
  /// **'Leyenda del Trivia'**
  String get avatarName1000Questions;

  /// No description provided for @avatarUnlock1000Questions.
  ///
  /// In es, this message translates to:
  /// **'Responde 1000 preguntas'**
  String get avatarUnlock1000Questions;

  /// No description provided for @avatarNameAiTopicMaster.
  ///
  /// In es, this message translates to:
  /// **'Maestro de Temas IA'**
  String get avatarNameAiTopicMaster;

  /// No description provided for @avatarUnlockAiTopicMaster.
  ///
  /// In es, this message translates to:
  /// **'Completa un tema generado por IA'**
  String get avatarUnlockAiTopicMaster;

  /// No description provided for @frameNameBronze.
  ///
  /// In es, this message translates to:
  /// **'Marco de Bronce'**
  String get frameNameBronze;

  /// No description provided for @frameNameSilver.
  ///
  /// In es, this message translates to:
  /// **'Marco de Plata'**
  String get frameNameSilver;

  /// No description provided for @frameNameGold.
  ///
  /// In es, this message translates to:
  /// **'Marco de Oro'**
  String get frameNameGold;

  /// No description provided for @frameNamePlatinum.
  ///
  /// In es, this message translates to:
  /// **'Marco de Platino'**
  String get frameNamePlatinum;

  /// No description provided for @frameNameDiamond.
  ///
  /// In es, this message translates to:
  /// **'Marco de Diamante'**
  String get frameNameDiamond;

  /// No description provided for @frameNameMaster.
  ///
  /// In es, this message translates to:
  /// **'Marco Maestro'**
  String get frameNameMaster;

  /// No description provided for @livesNoLivesTitle.
  ///
  /// In es, this message translates to:
  /// **'Sin vidas suficientes'**
  String get livesNoLivesTitle;

  /// No description provided for @livesNoLivesMessage.
  ///
  /// In es, this message translates to:
  /// **'Necesitas al menos 1 vida completa para entrar a un nivel.'**
  String get livesNoLivesMessage;

  /// No description provided for @livesYourLives.
  ///
  /// In es, this message translates to:
  /// **'Tus vidas'**
  String get livesYourLives;

  /// No description provided for @livesNextHalf.
  ///
  /// In es, this message translates to:
  /// **'Próx. media vida'**
  String get livesNextHalf;

  /// No description provided for @livesNextFull.
  ///
  /// In es, this message translates to:
  /// **'Para 1 vida completa'**
  String get livesNextFull;

  /// No description provided for @livesGoBack.
  ///
  /// In es, this message translates to:
  /// **'Volver'**
  String get livesGoBack;

  /// No description provided for @livesWait.
  ///
  /// In es, this message translates to:
  /// **'Esperar'**
  String get livesWait;

  /// No description provided for @livesRecoverButton.
  ///
  /// In es, this message translates to:
  /// **'Recuperar 1 vida ({cost} monedas)'**
  String livesRecoverButton(int cost);

  /// No description provided for @soloTabTitle.
  ///
  /// In es, this message translates to:
  /// **'Solo'**
  String get soloTabTitle;

  /// No description provided for @soloErrorLoadingCategories.
  ///
  /// In es, this message translates to:
  /// **'Error al cargar categorías:\n{error}'**
  String soloErrorLoadingCategories(String error);

  /// No description provided for @soloNoCategoriesAvailable.
  ///
  /// In es, this message translates to:
  /// **'No hay categorías activas en Firestore.'**
  String get soloNoCategoriesAvailable;

  /// No description provided for @soloFixedTopics.
  ///
  /// In es, this message translates to:
  /// **'Temas fijos'**
  String get soloFixedTopics;

  /// No description provided for @soloAllCompletedTitle.
  ///
  /// In es, this message translates to:
  /// **'¡Completaste todo el modo Solo!'**
  String get soloAllCompletedTitle;

  /// No description provided for @soloAllCompletedBody.
  ///
  /// In es, this message translates to:
  /// **'Sigue ganando monedas y XP en el Daily Challenge o retando a otros jugadores en PvP.'**
  String get soloAllCompletedBody;

  /// No description provided for @soloAllCompletedDailyButton.
  ///
  /// In es, this message translates to:
  /// **'Ir al Daily Challenge'**
  String get soloAllCompletedDailyButton;

  /// No description provided for @soloAllCompletedPvpButton.
  ///
  /// In es, this message translates to:
  /// **'Ir a PvP'**
  String get soloAllCompletedPvpButton;

  /// No description provided for @soloLifeRecovered.
  ///
  /// In es, this message translates to:
  /// **'❤️ Vida recuperada'**
  String get soloLifeRecovered;

  /// No description provided for @soloNotEnoughCoins.
  ///
  /// In es, this message translates to:
  /// **'❌ No tienes suficientes monedas'**
  String get soloNotEnoughCoins;

  /// No description provided for @soloProgressLevels.
  ///
  /// In es, this message translates to:
  /// **'Progreso: {completed} / {total} niveles'**
  String soloProgressLevels(int completed, int total);

  /// No description provided for @soloViewLevels.
  ///
  /// In es, this message translates to:
  /// **'Ver niveles'**
  String get soloViewLevels;

  /// No description provided for @soloStatusCompleted.
  ///
  /// In es, this message translates to:
  /// **'Completado'**
  String get soloStatusCompleted;

  /// No description provided for @soloStatusInProgress.
  ///
  /// In es, this message translates to:
  /// **'En curso'**
  String get soloStatusInProgress;

  /// No description provided for @soloStatusNew.
  ///
  /// In es, this message translates to:
  /// **'Nuevo'**
  String get soloStatusNew;

  /// No description provided for @soloContinueLevel.
  ///
  /// In es, this message translates to:
  /// **'Continuar N{level}'**
  String soloContinueLevel(int level);

  /// No description provided for @levelSelectNoLevelsYet.
  ///
  /// In es, this message translates to:
  /// **'Esta categoría aún no tiene niveles disponibles.'**
  String get levelSelectNoLevelsYet;

  /// No description provided for @levelSelectChooseLevel.
  ///
  /// In es, this message translates to:
  /// **'Selecciona un nivel'**
  String get levelSelectChooseLevel;

  /// No description provided for @levelSelectAiTopicApproved.
  ///
  /// In es, this message translates to:
  /// **'Tema IA aprobado'**
  String get levelSelectAiTopicApproved;

  /// No description provided for @levelSelectCategoryApproved.
  ///
  /// In es, this message translates to:
  /// **'Categoría aprobada'**
  String get levelSelectCategoryApproved;

  /// No description provided for @levelSelectAiTopicProgressApproved.
  ///
  /// In es, this message translates to:
  /// **'Tu progreso aprobado en este tema IA'**
  String get levelSelectAiTopicProgressApproved;

  /// No description provided for @levelSelectCategoryProgressApproved.
  ///
  /// In es, this message translates to:
  /// **'Tu progreso aprobado en esta categoría'**
  String get levelSelectCategoryProgressApproved;

  /// No description provided for @levelSelectApprovedCount.
  ///
  /// In es, this message translates to:
  /// **'Aprobados: {completed} / {total}'**
  String levelSelectApprovedCount(int completed, int total);

  /// No description provided for @levelSelectPlayLastLevel.
  ///
  /// In es, this message translates to:
  /// **'Jugar último nivel'**
  String get levelSelectPlayLastLevel;

  /// No description provided for @levelSelectContinueAtLevel.
  ///
  /// In es, this message translates to:
  /// **'Continuar en nivel {level}'**
  String levelSelectContinueAtLevel(int level);

  /// No description provided for @levelSelectAvailable.
  ///
  /// In es, this message translates to:
  /// **'Disponible'**
  String get levelSelectAvailable;

  /// No description provided for @levelSelectLocked.
  ///
  /// In es, this message translates to:
  /// **'Bloqueado'**
  String get levelSelectLocked;

  /// No description provided for @levelSelectLevelNumber.
  ///
  /// In es, this message translates to:
  /// **'Nivel {level}'**
  String levelSelectLevelNumber(int level);

  /// No description provided for @levelSelectNextBadge.
  ///
  /// In es, this message translates to:
  /// **'Siguiente'**
  String get levelSelectNextBadge;

  /// No description provided for @levelSelectLoadFailedTitle.
  ///
  /// In es, this message translates to:
  /// **'No se pudo cargar la categoría.'**
  String get levelSelectLoadFailedTitle;

  /// No description provided for @levelPlayAiTopicLabel.
  ///
  /// In es, this message translates to:
  /// **'Tema IA'**
  String get levelPlayAiTopicLabel;

  /// No description provided for @levelPlayAppBarTitle.
  ///
  /// In es, this message translates to:
  /// **'{name} - Nivel {level}'**
  String levelPlayAppBarTitle(String name, int level);

  /// No description provided for @levelPlayTimeUp.
  ///
  /// In es, this message translates to:
  /// **'⏰ Se acabó el tiempo'**
  String get levelPlayTimeUp;

  /// No description provided for @levelPlayTimeUpNoLives.
  ///
  /// In es, this message translates to:
  /// **'⏰ Se acabó el tiempo - te quedaste sin vidas'**
  String get levelPlayTimeUpNoLives;

  /// No description provided for @levelPlayTimeUpLostHalfLife.
  ///
  /// In es, this message translates to:
  /// **'⏰ Se acabó el tiempo - perdiste media vida'**
  String get levelPlayTimeUpLostHalfLife;

  /// No description provided for @levelPlayTimeUpNoLifeLoss.
  ///
  /// In es, this message translates to:
  /// **'⏰ Se acabó el tiempo - no perdiste vida'**
  String get levelPlayTimeUpNoLifeLoss;

  /// No description provided for @levelPlayWrongNoLives.
  ///
  /// In es, this message translates to:
  /// **'❌ Incorrecto - te quedaste sin vidas'**
  String get levelPlayWrongNoLives;

  /// No description provided for @levelPlayWrongLostHalfLife.
  ///
  /// In es, this message translates to:
  /// **'❌ Incorrecto - perdiste media vida'**
  String get levelPlayWrongLostHalfLife;

  /// No description provided for @levelPlayWrongNoLifeLoss.
  ///
  /// In es, this message translates to:
  /// **'❌ Incorrecto - no perdiste vida'**
  String get levelPlayWrongNoLifeLoss;

  /// No description provided for @aiReportQuestionTooltip.
  ///
  /// In es, this message translates to:
  /// **'Reportar esta pregunta'**
  String get aiReportQuestionTooltip;

  /// No description provided for @aiReportDialogTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Qué pasa con esta pregunta?'**
  String get aiReportDialogTitle;

  /// No description provided for @aiReportDialogDetailsHint.
  ///
  /// In es, this message translates to:
  /// **'Detalles adicionales (opcional)'**
  String get aiReportDialogDetailsHint;

  /// No description provided for @aiReportDialogCancel.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get aiReportDialogCancel;

  /// No description provided for @aiReportDialogSubmit.
  ///
  /// In es, this message translates to:
  /// **'Enviar reporte'**
  String get aiReportDialogSubmit;

  /// No description provided for @aiReportReasonWrongAnswer.
  ///
  /// In es, this message translates to:
  /// **'La respuesta marcada está mal'**
  String get aiReportReasonWrongAnswer;

  /// No description provided for @aiReportReasonConfusing.
  ///
  /// In es, this message translates to:
  /// **'Pregunta confusa o ambigua'**
  String get aiReportReasonConfusing;

  /// No description provided for @aiReportReasonInappropriate.
  ///
  /// In es, this message translates to:
  /// **'Contenido inapropiado'**
  String get aiReportReasonInappropriate;

  /// No description provided for @aiReportReasonOther.
  ///
  /// In es, this message translates to:
  /// **'Otro motivo'**
  String get aiReportReasonOther;

  /// No description provided for @aiReportSent.
  ///
  /// In es, this message translates to:
  /// **'Gracias, reportamos la pregunta.'**
  String get aiReportSent;

  /// No description provided for @levelPlayNeedFullLife.
  ///
  /// In es, this message translates to:
  /// **'Necesitas 1 vida completa para entrar a este nivel.'**
  String get levelPlayNeedFullLife;

  /// No description provided for @levelPlayLifeCheckError.
  ///
  /// In es, this message translates to:
  /// **'Error verificando vidas: {error}'**
  String levelPlayLifeCheckError(String error);

  /// No description provided for @levelPlaySessionCreateErrorTitle.
  ///
  /// In es, this message translates to:
  /// **'Error creando sesión'**
  String get levelPlaySessionCreateErrorTitle;

  /// No description provided for @levelPlayGeneratingQuestions.
  ///
  /// In es, this message translates to:
  /// **'Generando preguntas del nivel...'**
  String get levelPlayGeneratingQuestions;

  /// No description provided for @levelPlaySessionNotFound.
  ///
  /// In es, this message translates to:
  /// **'Sesión no encontrada.'**
  String get levelPlaySessionNotFound;

  /// No description provided for @levelPlaySessionNoQuestions.
  ///
  /// In es, this message translates to:
  /// **'Esta sesión no tiene preguntas.'**
  String get levelPlaySessionNoQuestions;

  /// No description provided for @levelPlayLivesMax.
  ///
  /// In es, this message translates to:
  /// **'MAX'**
  String get levelPlayLivesMax;

  /// No description provided for @levelPlayOutOfLivesTitle.
  ///
  /// In es, this message translates to:
  /// **'Te quedaste sin vidas'**
  String get levelPlayOutOfLivesTitle;

  /// No description provided for @levelPlayOutOfLivesMessage.
  ///
  /// In es, this message translates to:
  /// **'No puedes continuar este nivel hasta recuperar vidas.'**
  String get levelPlayOutOfLivesMessage;

  /// No description provided for @levelPlayLivesHeader.
  ///
  /// In es, this message translates to:
  /// **'Vidas: {lives}'**
  String levelPlayLivesHeader(String lives);

  /// No description provided for @levelPlayHalfLifeIn.
  ///
  /// In es, this message translates to:
  /// **'+0.5 en {time}'**
  String levelPlayHalfLifeIn(String time);

  /// No description provided for @levelPlayQuestionOfTotal.
  ///
  /// In es, this message translates to:
  /// **'Pregunta {current} de {total}'**
  String levelPlayQuestionOfTotal(int current, int total);

  /// No description provided for @levelPlayRankExpert.
  ///
  /// In es, this message translates to:
  /// **'Experto'**
  String get levelPlayRankExpert;

  /// No description provided for @levelPlayRankAdvanced.
  ///
  /// In es, this message translates to:
  /// **'Avanzado'**
  String get levelPlayRankAdvanced;

  /// No description provided for @levelPlayRankIntermediate.
  ///
  /// In es, this message translates to:
  /// **'Intermedio'**
  String get levelPlayRankIntermediate;

  /// No description provided for @levelPlayRankBeginner.
  ///
  /// In es, this message translates to:
  /// **'Novato'**
  String get levelPlayRankBeginner;

  /// No description provided for @levelPlayLevelPassed.
  ///
  /// In es, this message translates to:
  /// **'¡Nivel aprobado!'**
  String get levelPlayLevelPassed;

  /// No description provided for @levelPlayLevelFinished.
  ///
  /// In es, this message translates to:
  /// **'Nivel finalizado'**
  String get levelPlayLevelFinished;

  /// No description provided for @levelPlayScoreLine.
  ///
  /// In es, this message translates to:
  /// **'Puntaje: {correct} / {total} ({pct})'**
  String levelPlayScoreLine(int correct, int total, String pct);

  /// No description provided for @levelPlayRankLine.
  ///
  /// In es, this message translates to:
  /// **'Rango: {rank}'**
  String levelPlayRankLine(String rank);

  /// No description provided for @levelPlayRewardsTitle.
  ///
  /// In es, this message translates to:
  /// **'Recompensas'**
  String get levelPlayRewardsTitle;

  /// No description provided for @levelPlayAlreadyPassedBefore.
  ///
  /// In es, this message translates to:
  /// **'Este nivel ya había sido aprobado antes.'**
  String get levelPlayAlreadyPassedBefore;

  /// No description provided for @levelPlayNeed40Percent.
  ///
  /// In es, this message translates to:
  /// **'Necesitas al menos 40% de aciertos para aprobar este nivel.'**
  String get levelPlayNeed40Percent;

  /// No description provided for @levelPlaySavingProgress.
  ///
  /// In es, this message translates to:
  /// **'Guardando progreso...'**
  String get levelPlaySavingProgress;

  /// No description provided for @levelPlaySaveError.
  ///
  /// In es, this message translates to:
  /// **'Error guardando: {error}'**
  String levelPlaySaveError(String error);

  /// No description provided for @levelPlayRetrySave.
  ///
  /// In es, this message translates to:
  /// **'Reintentar guardado'**
  String get levelPlayRetrySave;

  /// No description provided for @levelPlayProgressSaved.
  ///
  /// In es, this message translates to:
  /// **'✅ Progreso guardado'**
  String get levelPlayProgressSaved;

  /// No description provided for @levelPlayContinueNextLevel.
  ///
  /// In es, this message translates to:
  /// **'Continuar (Nivel {level})'**
  String levelPlayContinueNextLevel(int level);

  /// No description provided for @levelPlayPlayerLevel.
  ///
  /// In es, this message translates to:
  /// **'Nivel de jugador {level}'**
  String levelPlayPlayerLevel(int level);

  /// No description provided for @levelPlayTotalXp.
  ///
  /// In es, this message translates to:
  /// **'XP total: {xp}'**
  String levelPlayTotalXp(int xp);

  /// No description provided for @levelPlayLevelUp.
  ///
  /// In es, this message translates to:
  /// **'¡SUBISTE! Nivel {level}'**
  String levelPlayLevelUp(int level);

  /// No description provided for @levelPlayLeveledUpTo.
  ///
  /// In es, this message translates to:
  /// **'¡Subiste al nivel {level}!'**
  String levelPlayLeveledUpTo(int level);

  /// No description provided for @levelPlayXpInLevel.
  ///
  /// In es, this message translates to:
  /// **'{current} / {total} XP en este nivel'**
  String levelPlayXpInLevel(int current, int total);

  /// No description provided for @pvpHubTitle.
  ///
  /// In es, this message translates to:
  /// **'PvP'**
  String get pvpHubTitle;

  /// No description provided for @pvpHubHeading.
  ///
  /// In es, this message translates to:
  /// **'Centro competitivo'**
  String get pvpHubHeading;

  /// No description provided for @pvpHubSubheading.
  ///
  /// In es, this message translates to:
  /// **'Elige cómo quieres competir.'**
  String get pvpHubSubheading;

  /// No description provided for @pvpActiveMatchesTitle.
  ///
  /// In es, this message translates to:
  /// **'Partidas Activas'**
  String get pvpActiveMatchesTitle;

  /// No description provided for @pvpActiveMatchesTitleAlert.
  ///
  /// In es, this message translates to:
  /// **'Partidas Activas • ¡Tu turno!'**
  String get pvpActiveMatchesTitleAlert;

  /// No description provided for @pvpActiveMatchesSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Turnos pendientes, partidas en vivo y resultados recientes.'**
  String get pvpActiveMatchesSubtitle;

  /// No description provided for @pvpActiveMatchesSubtitleAlert.
  ///
  /// In es, this message translates to:
  /// **'Tienes partidas pendientes esperando tu jugada.'**
  String get pvpActiveMatchesSubtitleAlert;

  /// No description provided for @pvpRealtimeInvitesTitle.
  ///
  /// In es, this message translates to:
  /// **'Invitaciones en Vivo'**
  String get pvpRealtimeInvitesTitle;

  /// No description provided for @pvpRealtimeInvitesTitleAlert.
  ///
  /// In es, this message translates to:
  /// **'Invitaciones en Vivo • ¡Nuevo!'**
  String get pvpRealtimeInvitesTitleAlert;

  /// No description provided for @pvpRealtimeInvitesSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Acepta o rechaza retos en vivo. Para retar a un amigo, ve a la pestaña Friends.'**
  String get pvpRealtimeInvitesSubtitle;

  /// No description provided for @pvpRealtimeInvitesSubtitleAlert.
  ///
  /// In es, this message translates to:
  /// **'Tienes retos en vivo esperando.'**
  String get pvpRealtimeInvitesSubtitleAlert;

  /// No description provided for @pvpFindOpponentTitle.
  ///
  /// In es, this message translates to:
  /// **'Buscar Rival'**
  String get pvpFindOpponentTitle;

  /// No description provided for @pvpFindOpponentSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Juega contra cualquier retador disponible.'**
  String get pvpFindOpponentSubtitle;

  /// No description provided for @pvpSeasonTitle.
  ///
  /// In es, this message translates to:
  /// **'Temporada PvP'**
  String get pvpSeasonTitle;

  /// No description provided for @pvpSeasonSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Consulta tu liga ranked, progreso de temporada, leaderboard y recompensas.'**
  String get pvpSeasonSubtitle;

  /// No description provided for @activeMatchesTitle.
  ///
  /// In es, this message translates to:
  /// **'Partidas Activas'**
  String get activeMatchesTitle;

  /// No description provided for @activeMatchesReconnecting.
  ///
  /// In es, this message translates to:
  /// **'Reconectando...'**
  String get activeMatchesReconnecting;

  /// No description provided for @activeMatchesYourTurn.
  ///
  /// In es, this message translates to:
  /// **'Tu turno'**
  String get activeMatchesYourTurn;

  /// No description provided for @activeMatchesLoadingYourMatches.
  ///
  /// In es, this message translates to:
  /// **'Cargando tus partidas...'**
  String get activeMatchesLoadingYourMatches;

  /// No description provided for @activeMatchesNoneWaitingForYou.
  ///
  /// In es, this message translates to:
  /// **'No tienes partidas asíncronas pendientes.'**
  String get activeMatchesNoneWaitingForYou;

  /// No description provided for @activeMatchesWaitingForOpponent.
  ///
  /// In es, this message translates to:
  /// **'Esperando al rival'**
  String get activeMatchesWaitingForOpponent;

  /// No description provided for @activeMatchesLoadingMatches.
  ///
  /// In es, this message translates to:
  /// **'Cargando partidas...'**
  String get activeMatchesLoadingMatches;

  /// No description provided for @activeMatchesNoneWaitingForOpponent.
  ///
  /// In es, this message translates to:
  /// **'No hay partidas esperando a tu rival.'**
  String get activeMatchesNoneWaitingForOpponent;

  /// No description provided for @activeMatchesRecentlyFinished.
  ///
  /// In es, this message translates to:
  /// **'Finalizadas recientemente'**
  String get activeMatchesRecentlyFinished;

  /// No description provided for @activeMatchesLoadingResults.
  ///
  /// In es, this message translates to:
  /// **'Cargando resultados...'**
  String get activeMatchesLoadingResults;

  /// No description provided for @activeMatchesNoneFinished.
  ///
  /// In es, this message translates to:
  /// **'No hay partidas finalizadas recientes.'**
  String get activeMatchesNoneFinished;

  /// No description provided for @activeMatchesYourTurnSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Tu turno • {category}'**
  String activeMatchesYourTurnSubtitle(String category);

  /// No description provided for @activeMatchesWaitingSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Esperando • Tu puntaje: {score}'**
  String activeMatchesWaitingSubtitle(int score);

  /// No description provided for @activeMatchesDrawSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Empate • {a}-{b}'**
  String activeMatchesDrawSubtitle(int a, int b);

  /// No description provided for @activeMatchesVictorySubtitle.
  ///
  /// In es, this message translates to:
  /// **'Victoria • {a}-{b}'**
  String activeMatchesVictorySubtitle(int a, int b);

  /// No description provided for @activeMatchesDefeatSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Derrota • {a}-{b}'**
  String activeMatchesDefeatSubtitle(int a, int b);

  /// No description provided for @activeMatchesPlay.
  ///
  /// In es, this message translates to:
  /// **'Jugar'**
  String get activeMatchesPlay;

  /// No description provided for @activeMatchesView.
  ///
  /// In es, this message translates to:
  /// **'Ver'**
  String get activeMatchesView;

  /// No description provided for @activeMatchesResult.
  ///
  /// In es, this message translates to:
  /// **'Resultado'**
  String get activeMatchesResult;

  /// No description provided for @findOpponentTitle.
  ///
  /// In es, this message translates to:
  /// **'Buscar rival'**
  String get findOpponentTitle;

  /// No description provided for @findOpponentLiveTab.
  ///
  /// In es, this message translates to:
  /// **'Tiempo real'**
  String get findOpponentLiveTab;

  /// No description provided for @findOpponentAsyncTab.
  ///
  /// In es, this message translates to:
  /// **'Asíncrono'**
  String get findOpponentAsyncTab;

  /// No description provided for @liveMenuLeagueTitle.
  ///
  /// In es, this message translates to:
  /// **'Liga {name}'**
  String liveMenuLeagueTitle(String name);

  /// No description provided for @liveMenuMmrHint1.
  ///
  /// In es, this message translates to:
  /// **'Buscar rival afecta tu MMR y tu liga PvP.'**
  String get liveMenuMmrHint1;

  /// No description provided for @liveMenuFixedTopicLabel.
  ///
  /// In es, this message translates to:
  /// **'Tema fijo'**
  String get liveMenuFixedTopicLabel;

  /// No description provided for @liveMenuPublicMatchmaking.
  ///
  /// In es, this message translates to:
  /// **'Matchmaking público'**
  String get liveMenuPublicMatchmaking;

  /// No description provided for @liveMenuMmrHint2.
  ///
  /// In es, this message translates to:
  /// **'Buscar rival afecta tu MMR, liga y estadísticas PvP.'**
  String get liveMenuMmrHint2;

  /// No description provided for @liveMenuPrivateMatches.
  ///
  /// In es, this message translates to:
  /// **'Partidas privadas'**
  String get liveMenuPrivateMatches;

  /// No description provided for @liveMenuCreatePrivateRoom.
  ///
  /// In es, this message translates to:
  /// **'Crear sala privada'**
  String get liveMenuCreatePrivateRoom;

  /// No description provided for @liveMenuJoinWithCode.
  ///
  /// In es, this message translates to:
  /// **'Unirme con código'**
  String get liveMenuJoinWithCode;

  /// No description provided for @liveMenuPrivateMatchesHint.
  ///
  /// In es, this message translates to:
  /// **'Las partidas privadas son amistosas y no afectan tu ranking.'**
  String get liveMenuPrivateMatchesHint;

  /// No description provided for @asyncMenuSelectTopicFirst.
  ///
  /// In es, this message translates to:
  /// **'Selecciona un tema fijo primero.'**
  String get asyncMenuSelectTopicFirst;

  /// No description provided for @asyncMenuConfigTitle.
  ///
  /// In es, this message translates to:
  /// **'Configuración'**
  String get asyncMenuConfigTitle;

  /// No description provided for @asyncMenuFixedTopicsLabel.
  ///
  /// In es, this message translates to:
  /// **'Temas fijos'**
  String get asyncMenuFixedTopicsLabel;

  /// No description provided for @asyncMenuNoActiveCategories.
  ///
  /// In es, this message translates to:
  /// **'No hay categorías activas.'**
  String get asyncMenuNoActiveCategories;

  /// No description provided for @asyncMenuSelectTopicLabel.
  ///
  /// In es, this message translates to:
  /// **'Selecciona un tema fijo'**
  String get asyncMenuSelectTopicLabel;

  /// No description provided for @asyncMenuFindPlayerButton.
  ///
  /// In es, this message translates to:
  /// **'Buscar jugador para retar'**
  String get asyncMenuFindPlayerButton;

  /// No description provided for @asyncMenuTip.
  ///
  /// In es, this message translates to:
  /// **'Tip: Retas a alguien, juegas inmediatamente y tu rival puede jugar luego. Revisa Active Matches para ver tus retos pendientes.'**
  String get asyncMenuTip;

  /// No description provided for @createMatchTitle.
  ///
  /// In es, this message translates to:
  /// **'Crear sala (Tiempo real)'**
  String get createMatchTitle;

  /// No description provided for @createMatchYourName.
  ///
  /// In es, this message translates to:
  /// **'Tu nombre (displayName)'**
  String get createMatchYourName;

  /// No description provided for @createMatchCategory.
  ///
  /// In es, this message translates to:
  /// **'Categoría'**
  String get createMatchCategory;

  /// No description provided for @createMatchDifficulty.
  ///
  /// In es, this message translates to:
  /// **'Dificultad'**
  String get createMatchDifficulty;

  /// No description provided for @createMatchDiffEasy.
  ///
  /// In es, this message translates to:
  /// **'1 (Fácil)'**
  String get createMatchDiffEasy;

  /// No description provided for @createMatchDiffMedium.
  ///
  /// In es, this message translates to:
  /// **'2 (Medio)'**
  String get createMatchDiffMedium;

  /// No description provided for @createMatchDiffHard.
  ///
  /// In es, this message translates to:
  /// **'3 (Difícil)'**
  String get createMatchDiffHard;

  /// No description provided for @createMatchTimePerQuestion.
  ///
  /// In es, this message translates to:
  /// **'Tiempo/Pregunta'**
  String get createMatchTimePerQuestion;

  /// No description provided for @createMatchQuestions.
  ///
  /// In es, this message translates to:
  /// **'Preguntas'**
  String get createMatchQuestions;

  /// No description provided for @createMatchAutoSearch.
  ///
  /// In es, this message translates to:
  /// **'Buscar jugador automático'**
  String get createMatchAutoSearch;

  /// No description provided for @createMatchCreateRoom.
  ///
  /// In es, this message translates to:
  /// **'Crear sala'**
  String get createMatchCreateRoom;

  /// No description provided for @joinMatchTitle.
  ///
  /// In es, this message translates to:
  /// **'Unirme'**
  String get joinMatchTitle;

  /// No description provided for @joinMatchCodeLabel.
  ///
  /// In es, this message translates to:
  /// **'Código de sala (ej: A7KQ2)'**
  String get joinMatchCodeLabel;

  /// No description provided for @liveMatchmakingRankedTitle.
  ///
  /// In es, this message translates to:
  /// **'Matchmaking Ranked'**
  String get liveMatchmakingRankedTitle;

  /// No description provided for @liveMatchmakingCasualTitle.
  ///
  /// In es, this message translates to:
  /// **'Matchmaking Casual'**
  String get liveMatchmakingCasualTitle;

  /// No description provided for @liveMatchmakingTypeLine.
  ///
  /// In es, this message translates to:
  /// **'Tipo: {type}'**
  String liveMatchmakingTypeLine(String type);

  /// No description provided for @liveMatchmakingCategoryLine.
  ///
  /// In es, this message translates to:
  /// **'Categoría: {category}'**
  String liveMatchmakingCategoryLine(String category);

  /// No description provided for @liveMatchmakingDifficultyLine.
  ///
  /// In es, this message translates to:
  /// **'Dificultad: {difficulty}'**
  String liveMatchmakingDifficultyLine(int difficulty);

  /// No description provided for @liveMatchmakingQuestionsLine.
  ///
  /// In es, this message translates to:
  /// **'Preguntas: {total}'**
  String liveMatchmakingQuestionsLine(int total);

  /// No description provided for @liveMatchmakingTimePerQuestionLine.
  ///
  /// In es, this message translates to:
  /// **'Tiempo/Pregunta: {seconds}s'**
  String liveMatchmakingTimePerQuestionLine(int seconds);

  /// No description provided for @liveMatchmakingNoOpponentFound.
  ///
  /// In es, this message translates to:
  /// **'No se encontró rival por ahora. Intenta nuevamente.'**
  String get liveMatchmakingNoOpponentFound;

  /// No description provided for @liveMatchmakingTryAsyncInstead.
  ///
  /// In es, this message translates to:
  /// **'Jugar asíncrono en su lugar'**
  String get liveMatchmakingTryAsyncInstead;

  /// No description provided for @liveMatchmakingSearchButton.
  ///
  /// In es, this message translates to:
  /// **'Buscar'**
  String get liveMatchmakingSearchButton;

  /// No description provided for @liveMatchmakingSearching.
  ///
  /// In es, this message translates to:
  /// **'Buscando...'**
  String get liveMatchmakingSearching;

  /// No description provided for @liveMatchmakingSearchingOpponent.
  ///
  /// In es, this message translates to:
  /// **'Buscando rival...'**
  String get liveMatchmakingSearchingOpponent;

  /// No description provided for @liveMatchmakingQueueStatus.
  ///
  /// In es, this message translates to:
  /// **'Estado cola: {status}'**
  String liveMatchmakingQueueStatus(String status);

  /// No description provided for @liveMatchmakingRankedHint.
  ///
  /// In es, this message translates to:
  /// **'Primero busca rivales cercanos a tu MMR; si tarda, amplía el rango automáticamente.'**
  String get liveMatchmakingRankedHint;

  /// No description provided for @liveMatchmakingCasualHint.
  ///
  /// In es, this message translates to:
  /// **'Casual no afecta tu MMR. Se prioriza encontrar rival rápido.'**
  String get liveMatchmakingCasualHint;

  /// No description provided for @liveMatchmakingCancelSearch.
  ///
  /// In es, this message translates to:
  /// **'Cancelar búsqueda'**
  String get liveMatchmakingCancelSearch;

  /// No description provided for @asyncFindPlayersCannotChallengeSelf.
  ///
  /// In es, this message translates to:
  /// **'No puedes retarte a ti mismo.'**
  String get asyncFindPlayersCannotChallengeSelf;

  /// No description provided for @asyncFindPlayersTitle.
  ///
  /// In es, this message translates to:
  /// **'Buscar jugador (asíncrono)'**
  String get asyncFindPlayersTitle;

  /// No description provided for @asyncFindPlayersSearchLabel.
  ///
  /// In es, this message translates to:
  /// **'Buscar por nombre'**
  String get asyncFindPlayersSearchLabel;

  /// No description provided for @asyncFindPlayersSearchPrompt.
  ///
  /// In es, this message translates to:
  /// **'Escribe un nombre de usuario para buscar jugadores.'**
  String get asyncFindPlayersSearchPrompt;

  /// No description provided for @asyncFindPlayersNoneToShow.
  ///
  /// In es, this message translates to:
  /// **'No hay jugadores para mostrar.'**
  String get asyncFindPlayersNoneToShow;

  /// No description provided for @asyncFindPlayersChallengeButton.
  ///
  /// In es, this message translates to:
  /// **'Retar'**
  String get asyncFindPlayersChallengeButton;

  /// No description provided for @realtimeInvitesDeclined.
  ///
  /// In es, this message translates to:
  /// **'Invitación rechazada'**
  String get realtimeInvitesDeclined;

  /// No description provided for @realtimeInvitesErrorLoading.
  ///
  /// In es, this message translates to:
  /// **'Error cargando invitaciones:\n{error}'**
  String realtimeInvitesErrorLoading(String error);

  /// No description provided for @realtimeInvitesInvitedYou.
  ///
  /// In es, this message translates to:
  /// **'{name} te invitó'**
  String realtimeInvitesInvitedYou(String name);

  /// No description provided for @realtimeInvitesSubtitle.
  ///
  /// In es, this message translates to:
  /// **'1 vs 1 en vivo • Categoría: {category}'**
  String realtimeInvitesSubtitle(String category);

  /// No description provided for @realtimeInvitesDecline.
  ///
  /// In es, this message translates to:
  /// **'Rechazar'**
  String get realtimeInvitesDecline;

  /// No description provided for @realtimeInvitesAccept.
  ///
  /// In es, this message translates to:
  /// **'Aceptar'**
  String get realtimeInvitesAccept;

  /// No description provided for @realtimeInvitesEmpty.
  ///
  /// In es, this message translates to:
  /// **'No tienes invitaciones en vivo por ahora.'**
  String get realtimeInvitesEmpty;

  /// No description provided for @realtimeInvitesReceivedTab.
  ///
  /// In es, this message translates to:
  /// **'Recibidas'**
  String get realtimeInvitesReceivedTab;

  /// No description provided for @realtimeInvitesSentTab.
  ///
  /// In es, this message translates to:
  /// **'Enviadas'**
  String get realtimeInvitesSentTab;

  /// No description provided for @realtimeInvitesSentTo.
  ///
  /// In es, this message translates to:
  /// **'Invitaste a {name}'**
  String realtimeInvitesSentTo(String name);

  /// No description provided for @realtimeInvitesWaitingResponse.
  ///
  /// In es, this message translates to:
  /// **'Esperando respuesta...'**
  String get realtimeInvitesWaitingResponse;

  /// No description provided for @realtimeInvitesCancel.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get realtimeInvitesCancel;

  /// No description provided for @realtimeInvitesCancelled.
  ///
  /// In es, this message translates to:
  /// **'Invitación cancelada'**
  String get realtimeInvitesCancelled;

  /// No description provided for @realtimeInvitesSentEmpty.
  ///
  /// In es, this message translates to:
  /// **'No tienes invitaciones enviadas por ahora.'**
  String get realtimeInvitesSentEmpty;

  /// No description provided for @friendChallengeNotOnline.
  ///
  /// In es, this message translates to:
  /// **'Tu amigo no está conectado para jugar en tiempo real.'**
  String get friendChallengeNotOnline;

  /// No description provided for @friendChallengeRealtimeSent.
  ///
  /// In es, this message translates to:
  /// **'Reto en tiempo real enviado a {name}'**
  String friendChallengeRealtimeSent(String name);

  /// No description provided for @friendChallengeOnline.
  ///
  /// In es, this message translates to:
  /// **'Online'**
  String get friendChallengeOnline;

  /// No description provided for @friendChallengeOffline.
  ///
  /// In es, this message translates to:
  /// **'Offline'**
  String get friendChallengeOffline;

  /// No description provided for @friendChallengeSendRealtime.
  ///
  /// In es, this message translates to:
  /// **'Enviar reto en tiempo real'**
  String get friendChallengeSendRealtime;

  /// No description provided for @friendChallengeCreateAsync.
  ///
  /// In es, this message translates to:
  /// **'Crear reto asíncrono'**
  String get friendChallengeCreateAsync;

  /// No description provided for @friendChallengeTitle.
  ///
  /// In es, this message translates to:
  /// **'Configurar reto'**
  String get friendChallengeTitle;

  /// No description provided for @friendChallengeTypeLabel.
  ///
  /// In es, this message translates to:
  /// **'Tipo de reto'**
  String get friendChallengeTypeLabel;

  /// No description provided for @friendChallengeNeedOnlineHint.
  ///
  /// In es, this message translates to:
  /// **'Tu amigo debe estar online para jugar en tiempo real.'**
  String get friendChallengeNeedOnlineHint;

  /// No description provided for @friendChallengeMatchConfig.
  ///
  /// In es, this message translates to:
  /// **'Configuración del match'**
  String get friendChallengeMatchConfig;

  /// No description provided for @friendChallengeCategoryRandom.
  ///
  /// In es, this message translates to:
  /// **'Aleatorio'**
  String get friendChallengeCategoryRandom;

  /// No description provided for @friendChallengeDiffEasy.
  ///
  /// In es, this message translates to:
  /// **'Fácil'**
  String get friendChallengeDiffEasy;

  /// No description provided for @friendChallengeDiffMedium.
  ///
  /// In es, this message translates to:
  /// **'Media'**
  String get friendChallengeDiffMedium;

  /// No description provided for @friendChallengeDiffHard.
  ///
  /// In es, this message translates to:
  /// **'Difícil'**
  String get friendChallengeDiffHard;

  /// No description provided for @friendChallengeQuestionCountLabel.
  ///
  /// In es, this message translates to:
  /// **'Cantidad de preguntas'**
  String get friendChallengeQuestionCountLabel;

  /// No description provided for @friendChallengeQuestionsCount.
  ///
  /// In es, this message translates to:
  /// **'{count} preguntas'**
  String friendChallengeQuestionsCount(int count);

  /// No description provided for @friendChallengeTimePerQuestionLabel.
  ///
  /// In es, this message translates to:
  /// **'Tiempo por pregunta'**
  String get friendChallengeTimePerQuestionLabel;

  /// No description provided for @friendChallengeSeconds.
  ///
  /// In es, this message translates to:
  /// **'{seconds} segundos'**
  String friendChallengeSeconds(int seconds);

  /// No description provided for @friendChallengeRealtimeHint.
  ///
  /// In es, this message translates to:
  /// **'Tiempo real requiere que ambos estén online. Las partidas con amigos son casuales y no afectan MMR.'**
  String get friendChallengeRealtimeHint;

  /// No description provided for @friendChallengeAsyncHint.
  ///
  /// In es, this message translates to:
  /// **'Asíncrono permite que tu amigo juegue cuando pueda. No afecta MMR.'**
  String get friendChallengeAsyncHint;

  /// No description provided for @matchLobbyWaitingFriendJoin.
  ///
  /// In es, this message translates to:
  /// **'Esperando que tu amigo se una a la sala.'**
  String get matchLobbyWaitingFriendJoin;

  /// No description provided for @matchLobbyAllReadyStarting.
  ///
  /// In es, this message translates to:
  /// **'Todo listo. La partida está iniciando...'**
  String get matchLobbyAllReadyStarting;

  /// No description provided for @matchLobbyReadyWaitingOpponent.
  ///
  /// In es, this message translates to:
  /// **'Listo. Esperando que tu rival confirme.'**
  String get matchLobbyReadyWaitingOpponent;

  /// No description provided for @matchLobbyOpponentReadyConfirm.
  ///
  /// In es, this message translates to:
  /// **'Tu rival ya está listo. Confirma para empezar.'**
  String get matchLobbyOpponentReadyConfirm;

  /// No description provided for @matchLobbyWaitingBothReady.
  ///
  /// In es, this message translates to:
  /// **'Esperando que ambos jugadores estén listos.'**
  String get matchLobbyWaitingBothReady;

  /// No description provided for @matchLobbyTitle.
  ///
  /// In es, this message translates to:
  /// **'Sala 1 vs 1'**
  String get matchLobbyTitle;

  /// No description provided for @matchLobbyNotFound.
  ///
  /// In es, this message translates to:
  /// **'Sala no encontrada'**
  String get matchLobbyNotFound;

  /// No description provided for @matchLobbyNoLongerAvailable.
  ///
  /// In es, this message translates to:
  /// **'La sala ya no está disponible.'**
  String get matchLobbyNoLongerAvailable;

  /// No description provided for @matchLobbyHeading.
  ///
  /// In es, this message translates to:
  /// **'Partida 1 vs 1'**
  String get matchLobbyHeading;

  /// No description provided for @matchLobbyTopicLabel.
  ///
  /// In es, this message translates to:
  /// **'Tema'**
  String get matchLobbyTopicLabel;

  /// No description provided for @matchLobbyModeLabel.
  ///
  /// In es, this message translates to:
  /// **'Modo'**
  String get matchLobbyModeLabel;

  /// No description provided for @matchLobbyModeFixed.
  ///
  /// In es, this message translates to:
  /// **'Sin IA'**
  String get matchLobbyModeFixed;

  /// No description provided for @matchLobbyModeAi.
  ///
  /// In es, this message translates to:
  /// **'Con IA'**
  String get matchLobbyModeAi;

  /// No description provided for @matchLobbyTimeLabel.
  ///
  /// In es, this message translates to:
  /// **'Tiempo'**
  String get matchLobbyTimeLabel;

  /// No description provided for @matchLobbySecondsPerQuestion.
  ///
  /// In es, this message translates to:
  /// **'{seconds} s por pregunta'**
  String matchLobbySecondsPerQuestion(int seconds);

  /// No description provided for @matchLobbyCodeCopied.
  ///
  /// In es, this message translates to:
  /// **'Código copiado'**
  String get matchLobbyCodeCopied;

  /// No description provided for @matchLobbyWaitingOpponentButton.
  ///
  /// In es, this message translates to:
  /// **'Esperando rival'**
  String get matchLobbyWaitingOpponentButton;

  /// No description provided for @matchLobbyWaitingOpponentEllipsis.
  ///
  /// In es, this message translates to:
  /// **'Esperando rival...'**
  String get matchLobbyWaitingOpponentEllipsis;

  /// No description provided for @matchLobbyImReady.
  ///
  /// In es, this message translates to:
  /// **'Estoy listo'**
  String get matchLobbyImReady;

  /// No description provided for @matchLobbyCancelReady.
  ///
  /// In es, this message translates to:
  /// **'Cancelar listo'**
  String get matchLobbyCancelReady;

  /// No description provided for @matchLobbyRoomStatus.
  ///
  /// In es, this message translates to:
  /// **'Estado de la sala: {status}'**
  String matchLobbyRoomStatus(String status);

  /// No description provided for @matchLobbyPlayer1.
  ///
  /// In es, this message translates to:
  /// **'Jugador 1'**
  String get matchLobbyPlayer1;

  /// No description provided for @matchLobbyPlayer2.
  ///
  /// In es, this message translates to:
  /// **'Jugador 2'**
  String get matchLobbyPlayer2;

  /// No description provided for @matchLobbyReadyLabel.
  ///
  /// In es, this message translates to:
  /// **'Listo'**
  String get matchLobbyReadyLabel;

  /// No description provided for @matchLobbyWaitingLabel.
  ///
  /// In es, this message translates to:
  /// **'Esperando...'**
  String get matchLobbyWaitingLabel;

  /// No description provided for @matchLobbyRoomCodeLabel.
  ///
  /// In es, this message translates to:
  /// **'Código de sala'**
  String get matchLobbyRoomCodeLabel;

  /// No description provided for @matchLobbyCopyCodeButton.
  ///
  /// In es, this message translates to:
  /// **'Copiar código'**
  String get matchLobbyCopyCodeButton;

  /// No description provided for @pvpResultPerfectDraw.
  ///
  /// In es, this message translates to:
  /// **'Empate perfecto'**
  String get pvpResultPerfectDraw;

  /// No description provided for @pvpResultWonByPoints.
  ///
  /// In es, this message translates to:
  /// **'Ganaste por +{diff} puntos'**
  String pvpResultWonByPoints(int diff);

  /// No description provided for @pvpResultLostByPoints.
  ///
  /// In es, this message translates to:
  /// **'Perdiste por {diff} puntos'**
  String pvpResultLostByPoints(int diff);

  /// No description provided for @pvpResultFinalResult.
  ///
  /// In es, this message translates to:
  /// **'Resultado final'**
  String get pvpResultFinalResult;

  /// No description provided for @pvpResultVs.
  ///
  /// In es, this message translates to:
  /// **'VS'**
  String get pvpResultVs;

  /// No description provided for @pvpResultMatchSummary.
  ///
  /// In es, this message translates to:
  /// **'Resumen del match'**
  String get pvpResultMatchSummary;

  /// No description provided for @pvpResultYourScore.
  ///
  /// In es, this message translates to:
  /// **'Tu score'**
  String get pvpResultYourScore;

  /// No description provided for @pvpResultOpponent.
  ///
  /// In es, this message translates to:
  /// **'Rival'**
  String get pvpResultOpponent;

  /// No description provided for @pvpResultPerformance.
  ///
  /// In es, this message translates to:
  /// **'Rendimiento'**
  String get pvpResultPerformance;

  /// No description provided for @pvpResultBefore.
  ///
  /// In es, this message translates to:
  /// **'Antes'**
  String get pvpResultBefore;

  /// No description provided for @pvpResultNow.
  ///
  /// In es, this message translates to:
  /// **'Ahora'**
  String get pvpResultNow;

  /// No description provided for @pvpResultCurrentStreak.
  ///
  /// In es, this message translates to:
  /// **'🔥 Racha actual: {count} victorias'**
  String pvpResultCurrentStreak(int count);

  /// No description provided for @matchPlayRematchRequestTitle.
  ///
  /// In es, this message translates to:
  /// **'Solicitud de revancha'**
  String get matchPlayRematchRequestTitle;

  /// No description provided for @matchPlayRematchRequestBody.
  ///
  /// In es, this message translates to:
  /// **'{name} quiere jugar una revancha.'**
  String matchPlayRematchRequestBody(String name);

  /// No description provided for @matchPlayTitle.
  ///
  /// In es, this message translates to:
  /// **'1 vs 1'**
  String get matchPlayTitle;

  /// No description provided for @matchPlayNotFound.
  ///
  /// In es, this message translates to:
  /// **'Match no encontrado'**
  String get matchPlayNotFound;

  /// No description provided for @matchPlayWaitingToStart.
  ///
  /// In es, this message translates to:
  /// **'Esperando que inicie...'**
  String get matchPlayWaitingToStart;

  /// No description provided for @matchPlayNoQuestions.
  ///
  /// In es, this message translates to:
  /// **'Este match no tiene preguntas.'**
  String get matchPlayNoQuestions;

  /// No description provided for @matchPlayYourScoreLabel.
  ///
  /// In es, this message translates to:
  /// **'Tu puntaje'**
  String get matchPlayYourScoreLabel;

  /// No description provided for @matchPlayWaitingFinalResult.
  ///
  /// In es, this message translates to:
  /// **'Esperando resultado final...'**
  String get matchPlayWaitingFinalResult;

  /// No description provided for @matchPlayOpponentStillAnswering.
  ///
  /// In es, this message translates to:
  /// **'Tu rival todavía está respondiendo preguntas.'**
  String get matchPlayOpponentStillAnswering;

  /// No description provided for @matchPlayYourScoreLine.
  ///
  /// In es, this message translates to:
  /// **'Tu puntaje: {score}'**
  String matchPlayYourScoreLine(int score);

  /// No description provided for @matchPlayDrawTitle.
  ///
  /// In es, this message translates to:
  /// **'Empate'**
  String get matchPlayDrawTitle;

  /// No description provided for @matchPlayDrawSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Ambos terminaron con el mismo puntaje.'**
  String get matchPlayDrawSubtitle;

  /// No description provided for @matchPlayVictoryTitle.
  ///
  /// In es, this message translates to:
  /// **'¡Ganaste!'**
  String get matchPlayVictoryTitle;

  /// No description provided for @matchPlayVictoryRankedSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Buen duelo. Tu rating competitivo fue actualizado.'**
  String get matchPlayVictoryRankedSubtitle;

  /// No description provided for @matchPlayVictoryCasualSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Buen duelo. Sumaste una victoria 1 vs 1.'**
  String get matchPlayVictoryCasualSubtitle;

  /// No description provided for @matchPlayDefeatTitle.
  ///
  /// In es, this message translates to:
  /// **'Perdiste'**
  String get matchPlayDefeatTitle;

  /// No description provided for @matchPlayDefeatRankedSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Estuviste cerca. Tu rating competitivo fue actualizado.'**
  String get matchPlayDefeatRankedSubtitle;

  /// No description provided for @matchPlayDefeatCasualSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Estuviste cerca. Intenta una revancha.'**
  String get matchPlayDefeatCasualSubtitle;

  /// No description provided for @matchPlayRematch.
  ///
  /// In es, this message translates to:
  /// **'Revancha'**
  String get matchPlayRematch;

  /// No description provided for @matchPlaySendingRequest.
  ///
  /// In es, this message translates to:
  /// **'Enviando solicitud...'**
  String get matchPlaySendingRequest;

  /// No description provided for @matchPlayRequestSent.
  ///
  /// In es, this message translates to:
  /// **'Solicitud enviada ✓'**
  String get matchPlayRequestSent;

  /// No description provided for @matchPlayCreatingRematch.
  ///
  /// In es, this message translates to:
  /// **'Creando revancha...'**
  String get matchPlayCreatingRematch;

  /// No description provided for @matchPlayExit.
  ///
  /// In es, this message translates to:
  /// **'Salir'**
  String get matchPlayExit;

  /// No description provided for @asyncMatchPlayTitle.
  ///
  /// In es, this message translates to:
  /// **'Reto asíncrono'**
  String get asyncMatchPlayTitle;

  /// No description provided for @asyncMatchPlayNotFound.
  ///
  /// In es, this message translates to:
  /// **'Reto no encontrado'**
  String get asyncMatchPlayNotFound;

  /// No description provided for @asyncMatchPlayNoQuestions.
  ///
  /// In es, this message translates to:
  /// **'Este reto no tiene preguntas.'**
  String get asyncMatchPlayNoQuestions;

  /// No description provided for @asyncMatchPlayYouFallback.
  ///
  /// In es, this message translates to:
  /// **'Tú'**
  String get asyncMatchPlayYouFallback;

  /// No description provided for @asyncMatchPlayOpponentFallback.
  ///
  /// In es, this message translates to:
  /// **'Rival'**
  String get asyncMatchPlayOpponentFallback;

  /// No description provided for @asyncMatchPlayCorrectLabel.
  ///
  /// In es, this message translates to:
  /// **'Aciertos'**
  String get asyncMatchPlayCorrectLabel;

  /// No description provided for @asyncMatchPlayChallengeCompletedTitle.
  ///
  /// In es, this message translates to:
  /// **'Reto completado'**
  String get asyncMatchPlayChallengeCompletedTitle;

  /// No description provided for @asyncMatchPlaySendingResultSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Enviando tu resultado. Luego esperaremos a tu rival.'**
  String get asyncMatchPlaySendingResultSubtitle;

  /// No description provided for @asyncMatchPlayAlreadyPlayedTitle.
  ///
  /// In es, this message translates to:
  /// **'Ya jugaste este reto'**
  String get asyncMatchPlayAlreadyPlayedTitle;

  /// No description provided for @asyncMatchPlayCalculatingFinal.
  ///
  /// In es, this message translates to:
  /// **'Tu resultado fue enviado. Calculando resultado final.'**
  String get asyncMatchPlayCalculatingFinal;

  /// No description provided for @asyncMatchPlayWaitingOpponentPlay.
  ///
  /// In es, this message translates to:
  /// **'Tu resultado fue enviado. Esperando que tu rival juegue.'**
  String get asyncMatchPlayWaitingOpponentPlay;

  /// No description provided for @asyncMatchPlaySendingRematch.
  ///
  /// In es, this message translates to:
  /// **'Enviando revancha...'**
  String get asyncMatchPlaySendingRematch;

  /// No description provided for @pvpSeasonTabSeason.
  ///
  /// In es, this message translates to:
  /// **'Temporada'**
  String get pvpSeasonTabSeason;

  /// No description provided for @pvpSeasonTabLeaderboard.
  ///
  /// In es, this message translates to:
  /// **'Clasificación'**
  String get pvpSeasonTabLeaderboard;

  /// No description provided for @pvpSeasonTabRewards.
  ///
  /// In es, this message translates to:
  /// **'Recompensas'**
  String get pvpSeasonTabRewards;

  /// No description provided for @pvpSeasonLabel.
  ///
  /// In es, this message translates to:
  /// **'Temporada: {id}'**
  String pvpSeasonLabel(String id);

  /// No description provided for @pvpSeasonEndsIn.
  ///
  /// In es, this message translates to:
  /// **'Termina en: {time}'**
  String pvpSeasonEndsIn(String time);

  /// No description provided for @pvpSeasonProjectedReward.
  ///
  /// In es, this message translates to:
  /// **'Recompensa proyectada: +{coins} monedas'**
  String pvpSeasonProjectedReward(int coins);

  /// No description provided for @pvpSeasonRankedHint.
  ///
  /// In es, this message translates to:
  /// **'Ranked usa matchmaking flexible: primero busca cerca de tu liga, luego amplía el rango para que nadie se quede esperando.'**
  String get pvpSeasonRankedHint;

  /// No description provided for @pvpSeasonHowItWorksTitle.
  ///
  /// In es, this message translates to:
  /// **'Cómo funcionan las Temporadas PvP'**
  String get pvpSeasonHowItWorksTitle;

  /// No description provided for @pvpSeasonHowItWorksBullet1.
  ///
  /// In es, this message translates to:
  /// **'• Juega partidas Ranked para subir tu MMR.'**
  String get pvpSeasonHowItWorksBullet1;

  /// No description provided for @pvpSeasonHowItWorksBullet2.
  ///
  /// In es, this message translates to:
  /// **'• Tu liga se calcula según tu MMR actual.'**
  String get pvpSeasonHowItWorksBullet2;

  /// No description provided for @pvpSeasonHowItWorksBullet3.
  ///
  /// In es, this message translates to:
  /// **'• Las clasificaciones ordenan a los jugadores por MMR.'**
  String get pvpSeasonHowItWorksBullet3;

  /// No description provided for @pvpSeasonHowItWorksBullet4.
  ///
  /// In es, this message translates to:
  /// **'• Las recompensas se basan en tu liga final cuando termina la temporada.'**
  String get pvpSeasonHowItWorksBullet4;

  /// No description provided for @pvpSeasonFriendsTab.
  ///
  /// In es, this message translates to:
  /// **'Amigos'**
  String get pvpSeasonFriendsTab;

  /// No description provided for @pvpSeasonGlobalTab.
  ///
  /// In es, this message translates to:
  /// **'Global'**
  String get pvpSeasonGlobalTab;

  /// No description provided for @pvpSeasonAllTab.
  ///
  /// In es, this message translates to:
  /// **'Todas'**
  String get pvpSeasonAllTab;

  /// No description provided for @pvpSeasonErrorLoadingFriends.
  ///
  /// In es, this message translates to:
  /// **'Error cargando clasificación de amigos:\n{error}'**
  String pvpSeasonErrorLoadingFriends(String error);

  /// No description provided for @pvpSeasonNoFriendsTitle.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay amigos en la clasificación'**
  String get pvpSeasonNoFriendsTitle;

  /// No description provided for @pvpSeasonNoFriendsEmptyHint.
  ///
  /// In es, this message translates to:
  /// **'Juega partidas Ranked y agrega amigos para comparar tu rating PvP.'**
  String get pvpSeasonNoFriendsEmptyHint;

  /// No description provided for @pvpSeasonNoFriendsHint.
  ///
  /// In es, this message translates to:
  /// **'Agrega amigos para comparar tu rating PvP con gente que conoces.'**
  String get pvpSeasonNoFriendsHint;

  /// No description provided for @pvpSeasonYouSuffix.
  ///
  /// In es, this message translates to:
  /// **'{name} (Tú)'**
  String pvpSeasonYouSuffix(String name);

  /// No description provided for @pvpSeasonMatchesCount.
  ///
  /// In es, this message translates to:
  /// **'{count} partidas'**
  String pvpSeasonMatchesCount(int count);

  /// No description provided for @pvpSeasonWinLossDraw.
  ///
  /// In es, this message translates to:
  /// **'{wins} G / {losses} P / {draws} E'**
  String pvpSeasonWinLossDraw(int wins, int losses, int draws);

  /// No description provided for @pvpSeasonErrorLoadingLeaderboard.
  ///
  /// In es, this message translates to:
  /// **'Error cargando clasificación:\n{error}'**
  String pvpSeasonErrorLoadingLeaderboard(String error);

  /// No description provided for @pvpSeasonNoRankedPlayers.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay jugadores ranked.\nJuega una partida Ranked para entrar en esta clasificación.'**
  String get pvpSeasonNoRankedPlayers;

  /// No description provided for @pvpSeasonRewardsTitle.
  ///
  /// In es, this message translates to:
  /// **'Recompensas de Temporada'**
  String get pvpSeasonRewardsTitle;

  /// No description provided for @pvpSeasonRewardsSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Las recompensas se basan en tu mejor liga PvP de cada temporada finalizada.'**
  String get pvpSeasonRewardsSubtitle;

  /// No description provided for @pvpSeasonCurrentProjectedReward.
  ///
  /// In es, this message translates to:
  /// **'Recompensa proyectada actual'**
  String get pvpSeasonCurrentProjectedReward;

  /// No description provided for @pvpSeasonEndsInLine.
  ///
  /// In es, this message translates to:
  /// **'La temporada termina en {time}'**
  String pvpSeasonEndsInLine(String time);

  /// No description provided for @pvpSeasonCheckingRewards.
  ///
  /// In es, this message translates to:
  /// **'Verificando recompensas de temporada PvP pendientes...'**
  String get pvpSeasonCheckingRewards;

  /// No description provided for @pvpSeasonCouldNotLoad.
  ///
  /// In es, this message translates to:
  /// **'No se pudieron cargar las recompensas'**
  String get pvpSeasonCouldNotLoad;

  /// No description provided for @pvpSeasonNoRewardYetTitle.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay recompensa disponible'**
  String get pvpSeasonNoRewardYetTitle;

  /// No description provided for @pvpSeasonNoRewardYetHint.
  ///
  /// In es, this message translates to:
  /// **'Juega partidas Ranked esta temporada. Cuando termine, tu recompensa PvP aparecerá aquí.'**
  String get pvpSeasonNoRewardYetHint;

  /// No description provided for @pvpSeasonPendingSingle.
  ///
  /// In es, this message translates to:
  /// **'{count} recompensa de temporada pendiente'**
  String pvpSeasonPendingSingle(int count);

  /// No description provided for @pvpSeasonPendingMultiple.
  ///
  /// In es, this message translates to:
  /// **'{count} recompensas de temporada pendientes'**
  String pvpSeasonPendingMultiple(int count);

  /// No description provided for @pvpSeasonMorePending.
  ///
  /// In es, this message translates to:
  /// **'+{count} temporada(s) pendiente(s) más'**
  String pvpSeasonMorePending(int count);

  /// No description provided for @pvpSeasonClaiming.
  ///
  /// In es, this message translates to:
  /// **'Reclamando...'**
  String get pvpSeasonClaiming;

  /// No description provided for @pvpSeasonClaimAllButton.
  ///
  /// In es, this message translates to:
  /// **'Reclamar todas las recompensas'**
  String get pvpSeasonClaimAllButton;

  /// No description provided for @pvpSeasonNoPendingRewards.
  ///
  /// In es, this message translates to:
  /// **'No hay recompensas de temporada PvP pendientes.'**
  String get pvpSeasonNoPendingRewards;

  /// No description provided for @pvpSeasonClaimedRewards.
  ///
  /// In es, this message translates to:
  /// **'¡Reclamaste {count} recompensa(s) de temporada PvP: +{coins} monedas!'**
  String pvpSeasonClaimedRewards(int count, int coins);

  /// No description provided for @dailyResultTitle.
  ///
  /// In es, this message translates to:
  /// **'Resultado del Daily Challenge'**
  String get dailyResultTitle;

  /// No description provided for @dailyResultComplete.
  ///
  /// In es, this message translates to:
  /// **'¡Daily Challenge completado!'**
  String get dailyResultComplete;

  /// No description provided for @dailyResultCorrectAnswers.
  ///
  /// In es, this message translates to:
  /// **'Respuestas correctas'**
  String get dailyResultCorrectAnswers;

  /// No description provided for @dailyResultTotalAnswered.
  ///
  /// In es, this message translates to:
  /// **'Total respondidas'**
  String get dailyResultTotalAnswered;

  /// No description provided for @dailyResultCoinsEarned.
  ///
  /// In es, this message translates to:
  /// **'Monedas ganadas'**
  String get dailyResultCoinsEarned;

  /// No description provided for @dailyResultStreakLabel.
  ///
  /// In es, this message translates to:
  /// **'Racha diaria'**
  String get dailyResultStreakLabel;

  /// No description provided for @dailyResultDaysValue.
  ///
  /// In es, this message translates to:
  /// **'{days} días'**
  String dailyResultDaysValue(int days);

  /// No description provided for @dailyResultStreakBonus.
  ///
  /// In es, this message translates to:
  /// **'Bono de racha'**
  String get dailyResultStreakBonus;

  /// No description provided for @dailyResultAlreadyPlayed.
  ///
  /// In es, this message translates to:
  /// **'Ya jugaste hoy. No se otorgaron monedas nuevamente.'**
  String get dailyResultAlreadyPlayed;

  /// No description provided for @dailyResultBackHome.
  ///
  /// In es, this message translates to:
  /// **'Volver al inicio'**
  String get dailyResultBackHome;

  /// No description provided for @dailyResultNextChallengeIn.
  ///
  /// In es, this message translates to:
  /// **'Próximo desafío en {time}'**
  String dailyResultNextChallengeIn(String time);

  /// No description provided for @dailyResultViewLeaderboard.
  ///
  /// In es, this message translates to:
  /// **'Ver ranking de hoy'**
  String get dailyResultViewLeaderboard;

  /// No description provided for @weeklyRewardsTitle.
  ///
  /// In es, this message translates to:
  /// **'Recompensas semanales'**
  String get weeklyRewardsTitle;

  /// No description provided for @weeklyRewardsNoPending.
  ///
  /// In es, this message translates to:
  /// **'No hay recompensas semanales pendientes.'**
  String get weeklyRewardsNoPending;

  /// No description provided for @weeklyRewardsClaimed.
  ///
  /// In es, this message translates to:
  /// **'¡Reclamaste {count} recompensa(s): +{coins} monedas!'**
  String weeklyRewardsClaimed(int count, int coins);

  /// No description provided for @weeklyRewardsChecking.
  ///
  /// In es, this message translates to:
  /// **'Verificando recompensas semanales pendientes...'**
  String get weeklyRewardsChecking;

  /// No description provided for @weeklyRewardsNoPendingTitle.
  ///
  /// In es, this message translates to:
  /// **'No hay recompensas semanales pendientes'**
  String get weeklyRewardsNoPendingTitle;

  /// No description provided for @weeklyRewardsKeepPlayingHint.
  ///
  /// In es, this message translates to:
  /// **'Sigue jugando el Weekly Challenge para ganar recompensas semanales.'**
  String get weeklyRewardsKeepPlayingHint;

  /// No description provided for @weeklyRewardsPendingSingle.
  ///
  /// In es, this message translates to:
  /// **'{count} recompensa pendiente'**
  String weeklyRewardsPendingSingle(int count);

  /// No description provided for @weeklyRewardsPendingMultiple.
  ///
  /// In es, this message translates to:
  /// **'{count} recompensas pendientes'**
  String weeklyRewardsPendingMultiple(int count);

  /// No description provided for @weeklyRewardsTotalAvailable.
  ///
  /// In es, this message translates to:
  /// **'Total disponible: +{coins} monedas'**
  String weeklyRewardsTotalAvailable(int coins);

  /// No description provided for @weeklyRewardsMiniTile.
  ///
  /// In es, this message translates to:
  /// **'{seasonId} • {leagueName} • Puesto #{rank} • {message}'**
  String weeklyRewardsMiniTile(
      String seasonId, String leagueName, int rank, String message);

  /// No description provided for @weeklyRewardsHistoryTitle.
  ///
  /// In es, this message translates to:
  /// **'Historial de recompensas semanales'**
  String get weeklyRewardsHistoryTitle;

  /// No description provided for @weeklyRewardsNoHistory.
  ///
  /// In es, this message translates to:
  /// **'Aún no has reclamado recompensas de temporada.'**
  String get weeklyRewardsNoHistory;

  /// No description provided for @weeklyRewardsHistoryTitleLine.
  ///
  /// In es, this message translates to:
  /// **'{seasonId} • {leagueName}'**
  String weeklyRewardsHistoryTitleLine(String seasonId, String leagueName);

  /// No description provided for @weeklyRewardsHistorySubtitle.
  ///
  /// In es, this message translates to:
  /// **'Puesto #{rank} • Puntaje {score} • {message}'**
  String weeklyRewardsHistorySubtitle(int rank, int score, String message);

  /// No description provided for @weeklyRewardsLeagueFallback.
  ///
  /// In es, this message translates to:
  /// **'Liga'**
  String get weeklyRewardsLeagueFallback;

  /// No description provided for @weeklyRewardsMessageFallback.
  ///
  /// In es, this message translates to:
  /// **'Recompensa semanal reclamada'**
  String get weeklyRewardsMessageFallback;

  /// No description provided for @weeklyRewardsErrorLoadingHistory.
  ///
  /// In es, this message translates to:
  /// **'Error cargando historial:\n{error}'**
  String weeklyRewardsErrorLoadingHistory(String error);

  /// No description provided for @dailyLeaderboardTitle.
  ///
  /// In es, this message translates to:
  /// **'Clasificación Diaria'**
  String get dailyLeaderboardTitle;

  /// No description provided for @dailyLeaderboardErrorLoading.
  ///
  /// In es, this message translates to:
  /// **'Error cargando clasificación:\n{error}'**
  String dailyLeaderboardErrorLoading(String error);

  /// No description provided for @dailyLeaderboardNoData.
  ///
  /// In es, this message translates to:
  /// **'No hay datos de clasificación disponibles.'**
  String get dailyLeaderboardNoData;

  /// No description provided for @dailyLeaderboardNoScoresYet.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay puntajes hoy.\n¡Juega el Daily Challenge primero!'**
  String get dailyLeaderboardNoScoresYet;

  /// No description provided for @dailyLeaderboardRankingTitle.
  ///
  /// In es, this message translates to:
  /// **'Clasificación'**
  String get dailyLeaderboardRankingTitle;

  /// No description provided for @dailyLeaderboardPtsSuffix.
  ///
  /// In es, this message translates to:
  /// **'{score} pts'**
  String dailyLeaderboardPtsSuffix(int score);

  /// No description provided for @dailyLeaderboardNameWithYou.
  ///
  /// In es, this message translates to:
  /// **'{name}  (Tú)'**
  String dailyLeaderboardNameWithYou(String name);

  /// No description provided for @dailyLeaderboardCorrectStreakLine.
  ///
  /// In es, this message translates to:
  /// **'Correctas: {correct} / {total}  •  Racha: {streak}'**
  String dailyLeaderboardCorrectStreakLine(int correct, int total, int streak);

  /// No description provided for @dailyLeaderboardScoreLabel.
  ///
  /// In es, this message translates to:
  /// **'Puntaje'**
  String get dailyLeaderboardScoreLabel;

  /// No description provided for @dailyChallengeCoinsPopup.
  ///
  /// In es, this message translates to:
  /// **'+5 Monedas 🎉'**
  String get dailyChallengeCoinsPopup;

  /// No description provided for @dailyChallengeErrorSaving.
  ///
  /// In es, this message translates to:
  /// **'Error guardando resultados: {error}'**
  String dailyChallengeErrorSaving(String error);

  /// No description provided for @dailyChallengeNoQuestions.
  ///
  /// In es, this message translates to:
  /// **'No hay preguntas disponibles'**
  String get dailyChallengeNoQuestions;

  /// No description provided for @dailyChallengeTimeLabel.
  ///
  /// In es, this message translates to:
  /// **'Tiempo'**
  String get dailyChallengeTimeLabel;

  /// No description provided for @dailyChallengeDifficultyLine.
  ///
  /// In es, this message translates to:
  /// **'Dificultad: {level}'**
  String dailyChallengeDifficultyLine(String level);

  /// No description provided for @dailyChallengeAnsweredCount.
  ///
  /// In es, this message translates to:
  /// **'Respondidas: {count}'**
  String dailyChallengeAnsweredCount(int count);

  /// No description provided for @dailyChallengeCompletedTitle.
  ///
  /// In es, this message translates to:
  /// **'¡Daily completado!'**
  String get dailyChallengeCompletedTitle;

  /// No description provided for @dailyChallengeSavingResults.
  ///
  /// In es, this message translates to:
  /// **'Guardando tus resultados...'**
  String get dailyChallengeSavingResults;

  /// No description provided for @weeklyTopicScreenTitle.
  ///
  /// In es, this message translates to:
  /// **'Weekly Topic'**
  String get weeklyTopicScreenTitle;

  /// No description provided for @weeklyTopicCoinsClaimed.
  ///
  /// In es, this message translates to:
  /// **'¡{coins} monedas reclamadas!'**
  String weeklyTopicCoinsClaimed(int coins);

  /// No description provided for @weeklyTopicRewardUnavailable.
  ///
  /// In es, this message translates to:
  /// **'La recompensa ya fue reclamada o aún no está disponible.'**
  String get weeklyTopicRewardUnavailable;

  /// No description provided for @weeklyTopicNoExclusiveReward.
  ///
  /// In es, this message translates to:
  /// **'No hay recompensa exclusiva configurada para esta semana.'**
  String get weeklyTopicNoExclusiveReward;

  /// No description provided for @weeklyTopicAvatarUnlocked.
  ///
  /// In es, this message translates to:
  /// **'¡{emoji} {name} desbloqueado!'**
  String weeklyTopicAvatarUnlocked(String emoji, String name);

  /// No description provided for @weeklyTopicFeaturedBadge.
  ///
  /// In es, this message translates to:
  /// **'Tema Semanal Destacado'**
  String get weeklyTopicFeaturedBadge;

  /// No description provided for @weeklyTopicProgressTitle.
  ///
  /// In es, this message translates to:
  /// **'Progreso'**
  String get weeklyTopicProgressTitle;

  /// No description provided for @weeklyTopicRewardsTitle.
  ///
  /// In es, this message translates to:
  /// **'Recompensas'**
  String get weeklyTopicRewardsTitle;

  /// No description provided for @weeklyTopicCoinRewardClaimed.
  ///
  /// In es, this message translates to:
  /// **'Recompensa de monedas reclamada'**
  String get weeklyTopicCoinRewardClaimed;

  /// No description provided for @weeklyTopicExclusiveClaimed.
  ///
  /// In es, this message translates to:
  /// **'Recompensa exclusiva reclamada.'**
  String get weeklyTopicExclusiveClaimed;

  /// No description provided for @weeklyTopicExclusiveReady.
  ///
  /// In es, this message translates to:
  /// **'Recompensa exclusiva lista para reclamar.'**
  String get weeklyTopicExclusiveReady;

  /// No description provided for @weeklyTopicExclusiveClaimedButton.
  ///
  /// In es, this message translates to:
  /// **'Recompensa exclusiva reclamada'**
  String get weeklyTopicExclusiveClaimedButton;

  /// No description provided for @weeklyTopicCategoryMissing.
  ///
  /// In es, this message translates to:
  /// **'Falta la categoría del Weekly Topic.'**
  String get weeklyTopicCategoryMissing;

  /// No description provided for @weeklyTopicPlayButton.
  ///
  /// In es, this message translates to:
  /// **'Jugar Weekly Topic'**
  String get weeklyTopicPlayButton;

  /// No description provided for @weeklyTopicCorrectAnswersProgress.
  ///
  /// In es, this message translates to:
  /// **'{correct} / {total} respuestas correctas'**
  String weeklyTopicCorrectAnswersProgress(int correct, int total);

  /// No description provided for @weeklyTopicCoinRewardDescription.
  ///
  /// In es, this message translates to:
  /// **'{threshold} respuestas correctas: +{coins} monedas'**
  String weeklyTopicCoinRewardDescription(int threshold, int coins);

  /// No description provided for @weeklyTopicClaimCoinReward.
  ///
  /// In es, this message translates to:
  /// **'Reclamar recompensa de monedas'**
  String get weeklyTopicClaimCoinReward;

  /// No description provided for @weeklyTopicCompletionRewardDescription.
  ///
  /// In es, this message translates to:
  /// **'{threshold} respuestas correctas: {emoji} {name}'**
  String weeklyTopicCompletionRewardDescription(
      int threshold, String emoji, String name);

  /// No description provided for @weeklyTopicClaimCompletionReward.
  ///
  /// In es, this message translates to:
  /// **'Reclamar recompensa exclusiva'**
  String get weeklyTopicClaimCompletionReward;

  /// No description provided for @weeklyTopicExclusiveLockedRounds.
  ///
  /// In es, this message translates to:
  /// **'Consigue {threshold} respuestas correctas para desbloquear esta recompensa.'**
  String weeklyTopicExclusiveLockedRounds(int threshold);

  /// No description provided for @weeklyTopicRoundResultTitle.
  ///
  /// In es, this message translates to:
  /// **'Ronda completada'**
  String get weeklyTopicRoundResultTitle;

  /// No description provided for @weeklyTopicRoundResultBody.
  ///
  /// In es, this message translates to:
  /// **'Respondiste correctamente {correct} de {total} preguntas.'**
  String weeklyTopicRoundResultBody(int correct, int total);

  /// No description provided for @weeklyTopicRoundResultButton.
  ///
  /// In es, this message translates to:
  /// **'Continuar'**
  String get weeklyTopicRoundResultButton;

  /// No description provided for @weeklyTopicRoundQuestionCount.
  ///
  /// In es, this message translates to:
  /// **'Pregunta {current} de {total}'**
  String weeklyTopicRoundQuestionCount(int current, int total);

  /// No description provided for @weeklyTopicRoundCorrectCount.
  ///
  /// In es, this message translates to:
  /// **'Correctas: {correct}'**
  String weeklyTopicRoundCorrectCount(int correct);

  /// No description provided for @weeklyLeagueScreenTitle.
  ///
  /// In es, this message translates to:
  /// **'Weekly Challenge'**
  String get weeklyLeagueScreenTitle;

  /// No description provided for @weeklyLeagueErrorLoading.
  ///
  /// In es, this message translates to:
  /// **'Error cargando el desafío semanal:\n{error}'**
  String weeklyLeagueErrorLoading(String error);

  /// No description provided for @weeklyLeagueNoScoresYet.
  ///
  /// In es, this message translates to:
  /// **'Aún no hay puntajes semanales.\nJuega un Daily Challenge para entrar en esta clasificación semanal.'**
  String get weeklyLeagueNoScoresYet;

  /// No description provided for @weeklyLeagueRankingTitle.
  ///
  /// In es, this message translates to:
  /// **'Clasificación Semanal'**
  String get weeklyLeagueRankingTitle;

  /// No description provided for @weeklyLeagueTierSuffix.
  ///
  /// In es, this message translates to:
  /// **'Nivel {name}'**
  String weeklyLeagueTierSuffix(String name);

  /// No description provided for @weeklyLeagueScoreLabel.
  ///
  /// In es, this message translates to:
  /// **'Puntaje semanal: {score}'**
  String weeklyLeagueScoreLabel(int score);

  /// No description provided for @weeklyLeagueResetIn.
  ///
  /// In es, this message translates to:
  /// **'Reinicio semanal en {time}'**
  String weeklyLeagueResetIn(String time);

  /// No description provided for @weeklyLeagueRewardHistoryButton.
  ///
  /// In es, this message translates to:
  /// **'Historial de recompensas'**
  String get weeklyLeagueRewardHistoryButton;

  /// No description provided for @weeklyLeaguePendingSeasonRewards.
  ///
  /// In es, this message translates to:
  /// **'Recompensas de temporada pendientes'**
  String get weeklyLeaguePendingSeasonRewards;

  /// No description provided for @weeklyLeagueOpenToSeeDetails.
  ///
  /// In es, this message translates to:
  /// **'Abre Recompensas Semanales para ver tu puesto y monedas exactas.'**
  String get weeklyLeagueOpenToSeeDetails;

  /// No description provided for @weeklyLeagueViewDetails.
  ///
  /// In es, this message translates to:
  /// **'Ver detalles'**
  String get weeklyLeagueViewDetails;

  /// No description provided for @weeklyLeagueClaim.
  ///
  /// In es, this message translates to:
  /// **'Reclamar'**
  String get weeklyLeagueClaim;

  /// No description provided for @weeklyLeagueWeeklyRewardsTitle.
  ///
  /// In es, this message translates to:
  /// **'Recompensas Semanales'**
  String get weeklyLeagueWeeklyRewardsTitle;

  /// No description provided for @weeklyLeagueTop1Reward.
  ///
  /// In es, this message translates to:
  /// **'Top 1: {coins} monedas + bono de ascenso'**
  String weeklyLeagueTop1Reward(int coins);

  /// No description provided for @weeklyLeagueTop3Reward.
  ///
  /// In es, this message translates to:
  /// **'Top 2-3: {coins} monedas'**
  String weeklyLeagueTop3Reward(int coins);

  /// No description provided for @weeklyLeagueTop10Reward.
  ///
  /// In es, this message translates to:
  /// **'Top 10: {coins} monedas'**
  String weeklyLeagueTop10Reward(int coins);

  /// No description provided for @weeklyLeagueResetHint.
  ///
  /// In es, this message translates to:
  /// **'Al final de la semana, la clasificación se reinicia y las recompensas se pueden reclamar.'**
  String get weeklyLeagueResetHint;

  /// No description provided for @weeklyLeagueLevelStreak.
  ///
  /// In es, this message translates to:
  /// **'Nivel {level}  •  Racha {streak}'**
  String weeklyLeagueLevelStreak(int level, int streak);

  /// No description provided for @weeklyLeagueWeeklyLabel.
  ///
  /// In es, this message translates to:
  /// **'Semanal'**
  String get weeklyLeagueWeeklyLabel;

  /// No description provided for @weeklyLeagueClaimedRewards.
  ///
  /// In es, this message translates to:
  /// **'¡Reclamaste {count} recompensas: +{coins} monedas!'**
  String weeklyLeagueClaimedRewards(int count, int coins);

  /// No description provided for @authGateError.
  ///
  /// In es, this message translates to:
  /// **'Error: {error}'**
  String authGateError(String error);

  /// No description provided for @achievementsTitle.
  ///
  /// In es, this message translates to:
  /// **'Logros'**
  String get achievementsTitle;

  /// No description provided for @achievementsRewardClaimed.
  ///
  /// In es, this message translates to:
  /// **'🎉 Recompensa reclamada: +{coins} monedas, +{xp} XP'**
  String achievementsRewardClaimed(int coins, int xp);

  /// No description provided for @achievementsErrorLoading.
  ///
  /// In es, this message translates to:
  /// **'Error cargando logros:\n{error}'**
  String achievementsErrorLoading(String error);

  /// No description provided for @achievementsProgressTitle.
  ///
  /// In es, this message translates to:
  /// **'Progreso de Logros'**
  String get achievementsProgressTitle;

  /// No description provided for @achievementsCompletedCount.
  ///
  /// In es, this message translates to:
  /// **'{completed} / {total} completados'**
  String achievementsCompletedCount(int completed, int total);

  /// No description provided for @achievementsClaimed.
  ///
  /// In es, this message translates to:
  /// **'Reclamado'**
  String get achievementsClaimed;

  /// No description provided for @achievementsClaimReward.
  ///
  /// In es, this message translates to:
  /// **'Reclamar recompensa'**
  String get achievementsClaimReward;

  /// No description provided for @achievementsInProgress.
  ///
  /// In es, this message translates to:
  /// **'En progreso'**
  String get achievementsInProgress;

  /// No description provided for @achievementsCoinsPill.
  ///
  /// In es, this message translates to:
  /// **'+{coins} monedas'**
  String achievementsCoinsPill(int coins);

  /// No description provided for @aiTopicsStatusReady.
  ///
  /// In es, this message translates to:
  /// **'Listo'**
  String get aiTopicsStatusReady;

  /// No description provided for @aiTopicsStatusFailed.
  ///
  /// In es, this message translates to:
  /// **'Falló'**
  String get aiTopicsStatusFailed;

  /// No description provided for @aiTopicsStatusDeleted.
  ///
  /// In es, this message translates to:
  /// **'Eliminado'**
  String get aiTopicsStatusDeleted;

  /// No description provided for @aiTopicsStatusInvalid.
  ///
  /// In es, this message translates to:
  /// **'Necesita reparación'**
  String get aiTopicsStatusInvalid;

  /// No description provided for @aiTopicsStatusBlocked.
  ///
  /// In es, this message translates to:
  /// **'Bloqueado'**
  String get aiTopicsStatusBlocked;

  /// No description provided for @aiTopicsStatusPreparing.
  ///
  /// In es, this message translates to:
  /// **'Preparando'**
  String get aiTopicsStatusPreparing;

  /// No description provided for @aiTopicsTitle.
  ///
  /// In es, this message translates to:
  /// **'Temas IA'**
  String get aiTopicsTitle;

  /// No description provided for @aiTopicsCreateTopic.
  ///
  /// In es, this message translates to:
  /// **'Crear tema'**
  String get aiTopicsCreateTopic;

  /// No description provided for @aiTopicsErrorLoading.
  ///
  /// In es, this message translates to:
  /// **'Error cargando temas IA:\n{error}'**
  String aiTopicsErrorLoading(String error);

  /// No description provided for @aiTopicsUntitled.
  ///
  /// In es, this message translates to:
  /// **'Tema sin título'**
  String get aiTopicsUntitled;

  /// No description provided for @aiTopicsDeleteTitle.
  ///
  /// In es, this message translates to:
  /// **'¿Eliminar tema?'**
  String get aiTopicsDeleteTitle;

  /// No description provided for @aiTopicsDeleteBody.
  ///
  /// In es, this message translates to:
  /// **'¿Quieres quitar \"{title}\" de tus temas IA?'**
  String aiTopicsDeleteBody(String title);

  /// No description provided for @aiTopicsCancel.
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get aiTopicsCancel;

  /// No description provided for @aiTopicsDelete.
  ///
  /// In es, this message translates to:
  /// **'Eliminar'**
  String get aiTopicsDelete;

  /// No description provided for @aiTopicsLevelsQuestions.
  ///
  /// In es, this message translates to:
  /// **'{levels} niveles • {questions} preguntas'**
  String aiTopicsLevelsQuestions(int levels, int questions);

  /// No description provided for @aiTopicsUnavailableSubtitle.
  ///
  /// In es, this message translates to:
  /// **'No se pudo generar este tema. Desliza para eliminarlo y recuperar tu costo.'**
  String get aiTopicsUnavailableSubtitle;

  /// No description provided for @aiTopicsFree.
  ///
  /// In es, this message translates to:
  /// **'Gratis'**
  String get aiTopicsFree;

  /// No description provided for @aiTopicsCoinsCost.
  ///
  /// In es, this message translates to:
  /// **'{cost} monedas'**
  String aiTopicsCoinsCost(int cost);

  /// No description provided for @aiTopicsExpandMenuItem.
  ///
  /// In es, this message translates to:
  /// **'Ampliar tema (+10 niveles) — {cost} monedas'**
  String aiTopicsExpandMenuItem(int cost);

  /// No description provided for @aiTopicsRegenerateMenuItemPlain.
  ///
  /// In es, this message translates to:
  /// **'Añadir más preguntas'**
  String get aiTopicsRegenerateMenuItemPlain;

  /// No description provided for @aiTopicsRegenerateAllFull.
  ///
  /// In es, this message translates to:
  /// **'Ya añadiste el máximo de preguntas a este tema.'**
  String get aiTopicsRegenerateAllFull;

  /// No description provided for @aiTopicsRegenerateDialogTitle.
  ///
  /// In es, this message translates to:
  /// **'Añadir más preguntas'**
  String get aiTopicsRegenerateDialogTitle;

  /// No description provided for @aiTopicsRegenerateDialogBody.
  ///
  /// In es, this message translates to:
  /// **'Esto genera preguntas nuevas para \"{title}\" y las suma a las que ya tiene, para que al rejugar cada nivel te toquen preguntas distintas.\n\nCosto: {cost} monedas\nTienes: {coins} monedas'**
  String aiTopicsRegenerateDialogBody(String title, int cost, int coins);

  /// No description provided for @aiTopicsRegenerateSuccess.
  ///
  /// In es, this message translates to:
  /// **'Preguntas añadidas'**
  String get aiTopicsRegenerateSuccess;

  /// No description provided for @aiTopicsExpandDialogTitle.
  ///
  /// In es, this message translates to:
  /// **'Ampliar tema'**
  String get aiTopicsExpandDialogTitle;

  /// No description provided for @aiTopicsExpandDialogBody.
  ///
  /// In es, this message translates to:
  /// **'Agrega 10 niveles más a \"{title}\".\n\nCosto: {cost} monedas\nTienes: {coins} monedas'**
  String aiTopicsExpandDialogBody(String title, int cost, int coins);

  /// No description provided for @aiTopicsExpandSuccess.
  ///
  /// In es, this message translates to:
  /// **'Tema ampliado'**
  String get aiTopicsExpandSuccess;

  /// No description provided for @aiTopicsConfirm.
  ///
  /// In es, this message translates to:
  /// **'Confirmar'**
  String get aiTopicsConfirm;

  /// No description provided for @aiTopicsEmptyTitle.
  ///
  /// In es, this message translates to:
  /// **'Crea tu propio tema de trivia'**
  String get aiTopicsEmptyTitle;

  /// No description provided for @aiTopicsEmptySubtitle.
  ///
  /// In es, this message translates to:
  /// **'Elige cualquier tema que te guste. Las preguntas generadas por IA se conectarán en el siguiente paso.'**
  String get aiTopicsEmptySubtitle;

  /// No description provided for @aiTopicsEmptyButton.
  ///
  /// In es, this message translates to:
  /// **'Crear Tema IA'**
  String get aiTopicsEmptyButton;

  /// No description provided for @createAiTopicEnterTopic.
  ///
  /// In es, this message translates to:
  /// **'Ingresa un tema'**
  String get createAiTopicEnterTopic;

  /// No description provided for @createAiTopicCreated.
  ///
  /// In es, this message translates to:
  /// **'Tema IA creado'**
  String get createAiTopicCreated;

  /// No description provided for @createAiTopicSubtitle.
  ///
  /// In es, this message translates to:
  /// **'Crea tu propia categoría de trivia'**
  String get createAiTopicSubtitle;

  /// No description provided for @createAiTopicExamplesLabel.
  ///
  /// In es, this message translates to:
  /// **'Ejemplos:'**
  String get createAiTopicExamplesLabel;

  /// No description provided for @createAiTopicExamplesList.
  ///
  /// In es, this message translates to:
  /// **'• Fórmula 1\n• Harry Potter\n• Películas de Marvel\n• Antiguo Egipto\n• Exploración espacial'**
  String get createAiTopicExamplesList;

  /// No description provided for @createAiTopicFieldLabel.
  ///
  /// In es, this message translates to:
  /// **'Tema'**
  String get createAiTopicFieldLabel;

  /// No description provided for @createAiTopicFieldHint.
  ///
  /// In es, this message translates to:
  /// **'Ejemplo: Fórmula 1'**
  String get createAiTopicFieldHint;

  /// No description provided for @createAiTopicYouHaveCoins.
  ///
  /// In es, this message translates to:
  /// **'Tienes {coins} monedas'**
  String createAiTopicYouHaveCoins(int coins);

  /// No description provided for @createAiTopicFirstFree.
  ///
  /// In es, this message translates to:
  /// **'🎉 Tu primer tema es gratis'**
  String get createAiTopicFirstFree;

  /// No description provided for @createAiTopicCosts.
  ///
  /// In es, this message translates to:
  /// **'Este tema cuesta {cost} monedas'**
  String createAiTopicCosts(int cost);

  /// No description provided for @createAiTopicMissingCoins.
  ///
  /// In es, this message translates to:
  /// **'Te faltan {amount} monedas'**
  String createAiTopicMissingCoins(int amount);

  /// No description provided for @createAiTopicIncludesHint.
  ///
  /// In es, this message translates to:
  /// **'Incluye 10 niveles con 10 preguntas cada uno, preparados de a poco mientras juegas.'**
  String get createAiTopicIncludesHint;

  /// No description provided for @createAiTopicCreatingButton.
  ///
  /// In es, this message translates to:
  /// **'Creando...'**
  String get createAiTopicCreatingButton;

  /// No description provided for @createAiTopicPopularSectionTitle.
  ///
  /// In es, this message translates to:
  /// **'Temas Populares'**
  String get createAiTopicPopularSectionTitle;

  /// No description provided for @createAiTopicPopularSectionHint.
  ///
  /// In es, this message translates to:
  /// **'Elige un tema ya creado por otros jugadores y ahorra monedas'**
  String get createAiTopicPopularSectionHint;

  /// No description provided for @createAiTopicPopularUsedCount.
  ///
  /// In es, this message translates to:
  /// **'Usado {count} veces'**
  String createAiTopicPopularUsedCount(int count);

  /// No description provided for @createAiTopicPopularCostLabel.
  ///
  /// In es, this message translates to:
  /// **'{cost} monedas'**
  String createAiTopicPopularCostLabel(int cost);

  /// No description provided for @createAiTopicPopularSelectedHint.
  ///
  /// In es, this message translates to:
  /// **'🔥 Tema popular seleccionado: costo con descuento'**
  String get createAiTopicPopularSelectedHint;

  /// No description provided for @createAiTopicExistingSelectedHint.
  ///
  /// In es, this message translates to:
  /// **'🏷️ Tema ya existente: costo con descuento'**
  String get createAiTopicExistingSelectedHint;

  /// No description provided for @createAiTopicPopularBadgeTooltip.
  ///
  /// In es, this message translates to:
  /// **'Tema popular'**
  String get createAiTopicPopularBadgeTooltip;

  /// No description provided for @createAiTopicExistingBadgeTooltip.
  ///
  /// In es, this message translates to:
  /// **'Tema ya existente, con descuento'**
  String get createAiTopicExistingBadgeTooltip;

  /// No description provided for @createAiTopicNewBadgeTooltip.
  ///
  /// In es, this message translates to:
  /// **'Tema nuevo, se generará con IA'**
  String get createAiTopicNewBadgeTooltip;

  /// No description provided for @createAiTopicFreeLabel.
  ///
  /// In es, this message translates to:
  /// **'Gratis'**
  String get createAiTopicFreeLabel;

  /// No description provided for @homeLivesUnavailable.
  ///
  /// In es, this message translates to:
  /// **'No se pudieron cargar tus vidas.'**
  String get homeLivesUnavailable;

  /// No description provided for @createAiTopicSearchingButton.
  ///
  /// In es, this message translates to:
  /// **'Buscando temas similares...'**
  String get createAiTopicSearchingButton;

  /// No description provided for @createAiTopicSuggestingButton.
  ///
  /// In es, this message translates to:
  /// **'Pidiendo sugerencias a la IA...'**
  String get createAiTopicSuggestingButton;

  /// No description provided for @createAiTopicBlockedMessage.
  ///
  /// In es, this message translates to:
  /// **'No se pudo generar ese tema. Intenta con otro título.'**
  String get createAiTopicBlockedMessage;

  /// No description provided for @createAiTopicMatchesFoundTitle.
  ///
  /// In es, this message translates to:
  /// **'Encontramos temas similares'**
  String get createAiTopicMatchesFoundTitle;

  /// No description provided for @createAiTopicMatchesFoundHint.
  ///
  /// In es, this message translates to:
  /// **'Elige uno para jugarlo al instante, o crea el tuyo como tema nuevo.'**
  String get createAiTopicMatchesFoundHint;

  /// No description provided for @createAiTopicNoneOfTheseButton.
  ///
  /// In es, this message translates to:
  /// **'Ninguno de estos, crear tema nuevo'**
  String get createAiTopicNoneOfTheseButton;

  /// No description provided for @createAiTopicBackButton.
  ///
  /// In es, this message translates to:
  /// **'Volver'**
  String get createAiTopicBackButton;

  /// No description provided for @createAiTopicAiSuggestionsTitle.
  ///
  /// In es, this message translates to:
  /// **'Sugerencias de la IA'**
  String get createAiTopicAiSuggestionsTitle;

  /// No description provided for @createAiTopicAiSuggestionsHint.
  ///
  /// In es, this message translates to:
  /// **'Elige una de estas opciones para crear tu tema — así evitamos errores de tipeo o temas demasiado vagos para generar buenas preguntas.'**
  String get createAiTopicAiSuggestionsHint;

  /// No description provided for @coinShopTitle.
  ///
  /// In es, this message translates to:
  /// **'Comprar monedas'**
  String get coinShopTitle;

  /// No description provided for @coinShopPurchaseSuccess.
  ///
  /// In es, this message translates to:
  /// **'+{coins} monedas'**
  String coinShopPurchaseSuccess(int coins);

  /// No description provided for @coinShopPurchaseFailed.
  ///
  /// In es, this message translates to:
  /// **'La compra no se completó.'**
  String get coinShopPurchaseFailed;

  /// No description provided for @coinShopComingSoonTitle.
  ///
  /// In es, this message translates to:
  /// **'Próximamente'**
  String get coinShopComingSoonTitle;

  /// No description provided for @coinShopComingSoonBody.
  ///
  /// In es, this message translates to:
  /// **'La compra de monedas todavía no está disponible en esta versión.'**
  String get coinShopComingSoonBody;

  /// No description provided for @coinShopCoinsAmount.
  ///
  /// In es, this message translates to:
  /// **'{coins} monedas'**
  String coinShopCoinsAmount(int coins);

  /// No description provided for @coinShopBuyButton.
  ///
  /// In es, this message translates to:
  /// **'Comprar'**
  String get coinShopBuyButton;

  /// No description provided for @notificationsChallengeDeclined.
  ///
  /// In es, this message translates to:
  /// **'Reto rechazado'**
  String get notificationsChallengeDeclined;

  /// No description provided for @notificationsContinue.
  ///
  /// In es, this message translates to:
  /// **'Continuar'**
  String get notificationsContinue;

  /// No description provided for @notificationsViewResult.
  ///
  /// In es, this message translates to:
  /// **'Ver resultado'**
  String get notificationsViewResult;

  /// No description provided for @notificationsReview.
  ///
  /// In es, this message translates to:
  /// **'Revisar'**
  String get notificationsReview;

  /// No description provided for @notificationsView.
  ///
  /// In es, this message translates to:
  /// **'Ver'**
  String get notificationsView;

  /// No description provided for @notificationsOpen.
  ///
  /// In es, this message translates to:
  /// **'Abrir'**
  String get notificationsOpen;

  /// No description provided for @notificationsOpenLobby.
  ///
  /// In es, this message translates to:
  /// **'Abrir sala'**
  String get notificationsOpenLobby;

  /// No description provided for @notificationsTitle.
  ///
  /// In es, this message translates to:
  /// **'Notificaciones'**
  String get notificationsTitle;

  /// No description provided for @notificationsReadAll.
  ///
  /// In es, this message translates to:
  /// **'Marcar todas'**
  String get notificationsReadAll;

  /// No description provided for @notificationsErrorLoading.
  ///
  /// In es, this message translates to:
  /// **'Error cargando notificaciones:\n{error}'**
  String notificationsErrorLoading(String error);

  /// No description provided for @notificationsFallbackTitle.
  ///
  /// In es, this message translates to:
  /// **'Notificación'**
  String get notificationsFallbackTitle;

  /// No description provided for @notificationsChallengerPrefix.
  ///
  /// In es, this message translates to:
  /// **'👤 {name}'**
  String notificationsChallengerPrefix(String name);

  /// No description provided for @notificationsCategoryLine.
  ///
  /// In es, this message translates to:
  /// **'🎯 Categoría: {category}'**
  String notificationsCategoryLine(String category);

  /// No description provided for @notificationsQuestionsLine.
  ///
  /// In es, this message translates to:
  /// **'❓ Preguntas: {count}'**
  String notificationsQuestionsLine(String count);

  /// No description provided for @notificationsTimeLine.
  ///
  /// In es, this message translates to:
  /// **'⏱ Tiempo: {seconds} seg'**
  String notificationsTimeLine(String seconds);

  /// No description provided for @notificationsEmptyState.
  ///
  /// In es, this message translates to:
  /// **'Aún no tienes notificaciones.'**
  String get notificationsEmptyState;

  /// No description provided for @presenceStatusOnline.
  ///
  /// In es, this message translates to:
  /// **'Online'**
  String get presenceStatusOnline;

  /// No description provided for @presenceStatusInMatch.
  ///
  /// In es, this message translates to:
  /// **'En partida'**
  String get presenceStatusInMatch;

  /// No description provided for @presenceStatusSearching.
  ///
  /// In es, this message translates to:
  /// **'Buscando partida'**
  String get presenceStatusSearching;

  /// No description provided for @friendsOfflineLabel.
  ///
  /// In es, this message translates to:
  /// **'Sin conexión'**
  String get friendsOfflineLabel;

  /// No description provided for @friendsLastSeenJustNow.
  ///
  /// In es, this message translates to:
  /// **'Visto justo ahora'**
  String get friendsLastSeenJustNow;

  /// No description provided for @friendsLastSeenMinutes.
  ///
  /// In es, this message translates to:
  /// **'Visto hace {minutes}m'**
  String friendsLastSeenMinutes(int minutes);

  /// No description provided for @friendsLastSeenHours.
  ///
  /// In es, this message translates to:
  /// **'Visto hace {hours}h'**
  String friendsLastSeenHours(int hours);

  /// No description provided for @friendsEnterUsername.
  ///
  /// In es, this message translates to:
  /// **'Escribe un username para buscar.'**
  String get friendsEnterUsername;

  /// No description provided for @friendsRequestSent.
  ///
  /// In es, this message translates to:
  /// **'Solicitud enviada'**
  String get friendsRequestSent;

  /// No description provided for @friendsActionCompleted.
  ///
  /// In es, this message translates to:
  /// **'Acción completada'**
  String get friendsActionCompleted;

  /// No description provided for @friendsTitle.
  ///
  /// In es, this message translates to:
  /// **'Amigos'**
  String get friendsTitle;

  /// No description provided for @friendsSearchTab.
  ///
  /// In es, this message translates to:
  /// **'Buscar'**
  String get friendsSearchTab;

  /// No description provided for @friendsFriendsTab.
  ///
  /// In es, this message translates to:
  /// **'Amigos'**
  String get friendsFriendsTab;

  /// No description provided for @friendsSentTab.
  ///
  /// In es, this message translates to:
  /// **'Enviadas'**
  String get friendsSentTab;

  /// No description provided for @friendsReceivedTab.
  ///
  /// In es, this message translates to:
  /// **'Recibidas'**
  String get friendsReceivedTab;

  /// No description provided for @friendsUsernameLabel.
  ///
  /// In es, this message translates to:
  /// **'Nombre de usuario'**
  String get friendsUsernameLabel;

  /// No description provided for @friendsNoPlayersFound.
  ///
  /// In es, this message translates to:
  /// **'No se encontraron jugadores con ese username.'**
  String get friendsNoPlayersFound;

  /// No description provided for @friendsErrorLoadingFriends.
  ///
  /// In es, this message translates to:
  /// **'Error cargando amigos:\n{error}'**
  String friendsErrorLoadingFriends(String error);

  /// No description provided for @friendsLoadingFriends.
  ///
  /// In es, this message translates to:
  /// **'Cargando amigos...'**
  String get friendsLoadingFriends;

  /// No description provided for @friendsNoFriendsYet.
  ///
  /// In es, this message translates to:
  /// **'Todavía no tienes amigos agregados.'**
  String get friendsNoFriendsYet;

  /// No description provided for @friendsAsyncOnly.
  ///
  /// In es, this message translates to:
  /// **'Solo asíncrono'**
  String get friendsAsyncOnly;

  /// No description provided for @friendsTodayScore.
  ///
  /// In es, this message translates to:
  /// **'Hoy: {score} pts'**
  String friendsTodayScore(int score);

  /// No description provided for @friendsNotPlayedToday.
  ///
  /// In es, this message translates to:
  /// **'Aún no jugó hoy'**
  String get friendsNotPlayedToday;

  /// No description provided for @friendsErrorLoadingSent.
  ///
  /// In es, this message translates to:
  /// **'Error cargando solicitudes enviadas:\n{error}'**
  String friendsErrorLoadingSent(String error);

  /// No description provided for @friendsLoadingSent.
  ///
  /// In es, this message translates to:
  /// **'Cargando solicitudes enviadas...'**
  String get friendsLoadingSent;

  /// No description provided for @friendsNoSentRequests.
  ///
  /// In es, this message translates to:
  /// **'No tienes solicitudes pendientes por responder.'**
  String get friendsNoSentRequests;

  /// No description provided for @friendsPending.
  ///
  /// In es, this message translates to:
  /// **'Pendiente'**
  String get friendsPending;

  /// No description provided for @friendsSentStatus.
  ///
  /// In es, this message translates to:
  /// **'Enviado'**
  String get friendsSentStatus;

  /// No description provided for @friendsErrorLoadingReceived.
  ///
  /// In es, this message translates to:
  /// **'Error cargando solicitudes:\n{error}'**
  String friendsErrorLoadingReceived(String error);

  /// No description provided for @friendsLoadingReceived.
  ///
  /// In es, this message translates to:
  /// **'Cargando solicitudes...'**
  String get friendsLoadingReceived;

  /// No description provided for @friendsNoReceivedRequests.
  ///
  /// In es, this message translates to:
  /// **'No tienes solicitudes pendientes.'**
  String get friendsNoReceivedRequests;

  /// No description provided for @friendsWantsToAddYou.
  ///
  /// In es, this message translates to:
  /// **'Quiere agregarte'**
  String get friendsWantsToAddYou;

  /// No description provided for @friendsReject.
  ///
  /// In es, this message translates to:
  /// **'Rechazar'**
  String get friendsReject;

  /// No description provided for @friendsAccept.
  ///
  /// In es, this message translates to:
  /// **'Aceptar'**
  String get friendsAccept;

  /// No description provided for @friendsAlreadyFriend.
  ///
  /// In es, this message translates to:
  /// **'Ya es tu amigo'**
  String get friendsAlreadyFriend;

  /// No description provided for @friendsWantsToAddYouTile.
  ///
  /// In es, this message translates to:
  /// **'Te quiere agregar'**
  String get friendsWantsToAddYouTile;

  /// No description provided for @friendsPlayerFound.
  ///
  /// In es, this message translates to:
  /// **'Jugador encontrado'**
  String get friendsPlayerFound;

  /// No description provided for @friendsAddButton.
  ///
  /// In es, this message translates to:
  /// **'Agregar'**
  String get friendsAddButton;

  /// No description provided for @onboardingWelcomeTitle.
  ///
  /// In es, this message translates to:
  /// **'¡Bienvenido a TriviaIA!'**
  String get onboardingWelcomeTitle;

  /// No description provided for @onboardingWelcomeBody.
  ///
  /// In es, this message translates to:
  /// **'Responde preguntas de trivia, compite contra otros jugadores y sube de nivel cada día.'**
  String get onboardingWelcomeBody;

  /// No description provided for @onboardingLivesTitle.
  ///
  /// In es, this message translates to:
  /// **'Tus vidas'**
  String get onboardingLivesTitle;

  /// No description provided for @onboardingLivesBody.
  ///
  /// In es, this message translates to:
  /// **'Tienes 5 vidas. Cada una se recupera sola cada 5 minutos, o puedes comprarla al instante con monedas si no quieres esperar.'**
  String get onboardingLivesBody;

  /// No description provided for @onboardingCoinsTitle.
  ///
  /// In es, this message translates to:
  /// **'Monedas y racha diaria'**
  String get onboardingCoinsTitle;

  /// No description provided for @onboardingCoinsBody.
  ///
  /// In es, this message translates to:
  /// **'Gana monedas y XP jugando. Vuelve cada día al Daily Challenge para mantener tu racha y ganar recompensas extra.'**
  String get onboardingCoinsBody;

  /// No description provided for @onboardingSkip.
  ///
  /// In es, this message translates to:
  /// **'Saltar'**
  String get onboardingSkip;

  /// No description provided for @onboardingNext.
  ///
  /// In es, this message translates to:
  /// **'Siguiente'**
  String get onboardingNext;

  /// No description provided for @onboardingPlayFirstDaily.
  ///
  /// In es, this message translates to:
  /// **'Jugar mi primer Daily Challenge'**
  String get onboardingPlayFirstDaily;

  /// No description provided for @spotlightGotIt.
  ///
  /// In es, this message translates to:
  /// **'Entendido'**
  String get spotlightGotIt;

  /// No description provided for @spotlightPvpTitle.
  ///
  /// In es, this message translates to:
  /// **'Duelos 1 vs 1'**
  String get spotlightPvpTitle;

  /// No description provided for @spotlightPvpBody.
  ///
  /// In es, this message translates to:
  /// **'Reta a otros jugadores en tiempo real o de forma asíncrona. Ganar sube tu rating y te acerca a la siguiente liga, con más recompensas.'**
  String get spotlightPvpBody;

  /// No description provided for @spotlightWeeklyTopicTitle.
  ///
  /// In es, this message translates to:
  /// **'Tema de la semana'**
  String get spotlightWeeklyTopicTitle;

  /// No description provided for @spotlightWeeklyTopicBody.
  ///
  /// In es, this message translates to:
  /// **'Cada semana rota una categoría especial. Responde rondas para ganar monedas y un avatar exclusivo antes de que termine la semana.'**
  String get spotlightWeeklyTopicBody;

  /// No description provided for @spotlightAchievementsTitle.
  ///
  /// In es, this message translates to:
  /// **'Logros'**
  String get spotlightAchievementsTitle;

  /// No description provided for @spotlightAchievementsBody.
  ///
  /// In es, this message translates to:
  /// **'Cumple objetivos jugando y reclama su recompensa en monedas y XP tocando la tarjeta cuando esté completa.'**
  String get spotlightAchievementsBody;

  /// No description provided for @spotlightFramesTitle.
  ///
  /// In es, this message translates to:
  /// **'Marcos de perfil'**
  String get spotlightFramesTitle;

  /// No description provided for @spotlightFramesBody.
  ///
  /// In es, this message translates to:
  /// **'Personaliza tu avatar con marcos que desbloqueas al subir de liga en PvP.'**
  String get spotlightFramesBody;

  /// No description provided for @spotlightAiTopicsGuidedTitle.
  ///
  /// In es, this message translates to:
  /// **'Buscamos antes de generar'**
  String get spotlightAiTopicsGuidedTitle;

  /// No description provided for @spotlightAiTopicsGuidedBody.
  ///
  /// In es, this message translates to:
  /// **'Al crear un tema primero buscamos si ya existe uno parecido: si lo eliges, pagas menos porque reutilizamos sus preguntas. Si no, la IA te propone opciones bien escritas para que elijas una.'**
  String get spotlightAiTopicsGuidedBody;

  /// No description provided for @spotlightAiTopicsPopularTitle.
  ///
  /// In es, this message translates to:
  /// **'Temas Populares'**
  String get spotlightAiTopicsPopularTitle;

  /// No description provided for @spotlightAiTopicsPopularBody.
  ///
  /// In es, this message translates to:
  /// **'Estos temas ya fueron generados por otros jugadores, así que puedes jugarlos con descuento en lugar de pagar el costo completo de un tema nuevo.'**
  String get spotlightAiTopicsPopularBody;

  /// No description provided for @notificationBellTooltip.
  ///
  /// In es, this message translates to:
  /// **'Notificaciones'**
  String get notificationBellTooltip;

  /// No description provided for @buyCoinsButtonLabel.
  ///
  /// In es, this message translates to:
  /// **'Comprar monedas'**
  String get buyCoinsButtonLabel;

  /// No description provided for @profileErrorLoadingMatchHistory.
  ///
  /// In es, this message translates to:
  /// **'Error cargando historial de partidas:\n{error}'**
  String profileErrorLoadingMatchHistory(String error);

  /// No description provided for @serviceEnterUsername.
  ///
  /// In es, this message translates to:
  /// **'Escribe un nombre de usuario.'**
  String get serviceEnterUsername;

  /// No description provided for @serviceConnectionTimeout.
  ///
  /// In es, this message translates to:
  /// **'No se pudo conectar. Revisa tu conexión e inténtalo de nuevo.'**
  String get serviceConnectionTimeout;

  /// No description provided for @serviceInvalidUser.
  ///
  /// In es, this message translates to:
  /// **'Usuario inválido.'**
  String get serviceInvalidUser;

  /// No description provided for @serviceCannotAddSelf.
  ///
  /// In es, this message translates to:
  /// **'No puedes agregarte a ti mismo.'**
  String get serviceCannotAddSelf;

  /// No description provided for @serviceUserNotFound.
  ///
  /// In es, this message translates to:
  /// **'El usuario no existe.'**
  String get serviceUserNotFound;

  /// No description provided for @serviceAlreadyFriends.
  ///
  /// In es, this message translates to:
  /// **'Ya son amigos.'**
  String get serviceAlreadyFriends;

  /// No description provided for @serviceRequestAlreadySent.
  ///
  /// In es, this message translates to:
  /// **'Solicitud ya enviada.'**
  String get serviceRequestAlreadySent;

  /// No description provided for @serviceRequestAlreadyReceived.
  ///
  /// In es, this message translates to:
  /// **'Ese jugador ya te envió una solicitud — revisa tus solicitudes recibidas.'**
  String get serviceRequestAlreadyReceived;

  /// No description provided for @serviceInvalidRequest.
  ///
  /// In es, this message translates to:
  /// **'Solicitud inválida.'**
  String get serviceInvalidRequest;

  /// No description provided for @serviceCouldNotAcceptRequest.
  ///
  /// In es, this message translates to:
  /// **'No se pudo aceptar la solicitud.'**
  String get serviceCouldNotAcceptRequest;

  /// No description provided for @serviceCouldNotRejectRequest.
  ///
  /// In es, this message translates to:
  /// **'No se pudo rechazar la solicitud.'**
  String get serviceCouldNotRejectRequest;

  /// No description provided for @serviceInvalidFriend.
  ///
  /// In es, this message translates to:
  /// **'Amigo inválido.'**
  String get serviceInvalidFriend;

  /// No description provided for @serviceCouldNotRemoveFriend.
  ///
  /// In es, this message translates to:
  /// **'No se pudo eliminar al amigo.'**
  String get serviceCouldNotRemoveFriend;

  /// No description provided for @serviceFriendRequestNotifTitle.
  ///
  /// In es, this message translates to:
  /// **'Nueva solicitud de amistad'**
  String get serviceFriendRequestNotifTitle;

  /// No description provided for @serviceFriendRequestNotifBody.
  ///
  /// In es, this message translates to:
  /// **'{name} quiere agregarte como amigo.'**
  String serviceFriendRequestNotifBody(String name);

  /// No description provided for @serviceRankedCooldown.
  ///
  /// In es, this message translates to:
  /// **'Tienes cooldown de ranked por abandono. Intenta de nuevo en {remaining}.'**
  String serviceRankedCooldown(String remaining);

  /// No description provided for @serviceRoomNotFound.
  ///
  /// In es, this message translates to:
  /// **'Sala no existe'**
  String get serviceRoomNotFound;

  /// No description provided for @serviceNotInRoom.
  ///
  /// In es, this message translates to:
  /// **'No estás dentro de esta sala'**
  String get serviceNotInRoom;

  /// No description provided for @serviceMatchNotFound.
  ///
  /// In es, this message translates to:
  /// **'Match no encontrado'**
  String get serviceMatchNotFound;

  /// No description provided for @serviceChallengedUidEmpty.
  ///
  /// In es, this message translates to:
  /// **'challengedUid vacío'**
  String get serviceChallengedUidEmpty;

  /// No description provided for @serviceCannotChallengeSelfNoPeriod.
  ///
  /// In es, this message translates to:
  /// **'No puedes retarte a ti mismo'**
  String get serviceCannotChallengeSelfNoPeriod;

  /// No description provided for @serviceChallengeNotFound.
  ///
  /// In es, this message translates to:
  /// **'Reto no encontrado'**
  String get serviceChallengeNotFound;

  /// No description provided for @serviceNotYourChallenge.
  ///
  /// In es, this message translates to:
  /// **'No perteneces a este reto'**
  String get serviceNotYourChallenge;

  /// No description provided for @serviceAsyncMatchNotFound.
  ///
  /// In es, this message translates to:
  /// **'Async match no existe'**
  String get serviceAsyncMatchNotFound;

  /// No description provided for @serviceNotYourMatch.
  ///
  /// In es, this message translates to:
  /// **'No perteneces a este match'**
  String get serviceNotYourMatch;

  /// No description provided for @servicePoolEmptyForCategory.
  ///
  /// In es, this message translates to:
  /// **'Pool vacío para {categoryId}'**
  String servicePoolEmptyForCategory(String categoryId);

  /// No description provided for @serviceNoActiveCategories.
  ///
  /// In es, this message translates to:
  /// **'No hay categorías activas'**
  String get serviceNoActiveCategories;

  /// No description provided for @serviceRematchRequestedTitle.
  ///
  /// In es, this message translates to:
  /// **'Revancha solicitada'**
  String get serviceRematchRequestedTitle;

  /// No description provided for @serviceRematchRequestedBody.
  ///
  /// In es, this message translates to:
  /// **'{name} quiere la revancha.'**
  String serviceRematchRequestedBody(String name);

  /// No description provided for @serviceNewAsyncChallengeTitle.
  ///
  /// In es, this message translates to:
  /// **'Nuevo reto asíncrono'**
  String get serviceNewAsyncChallengeTitle;

  /// No description provided for @serviceNewAsyncChallengeBody.
  ///
  /// In es, this message translates to:
  /// **'{name} te retó a una partida 1 vs 1.'**
  String serviceNewAsyncChallengeBody(String name);

  /// No description provided for @serviceYourTurnTitle.
  ///
  /// In es, this message translates to:
  /// **'Tu turno'**
  String get serviceYourTurnTitle;

  /// No description provided for @serviceYourTurnBody.
  ///
  /// In es, this message translates to:
  /// **'{name} terminó su partida asíncrona. Ahora es tu turno.'**
  String serviceYourTurnBody(String name);

  /// No description provided for @serviceCannotChallengeSelfPeriod.
  ///
  /// In es, this message translates to:
  /// **'No puedes retarte a ti mismo.'**
  String get serviceCannotChallengeSelfPeriod;

  /// No description provided for @serviceInviteNotFound.
  ///
  /// In es, this message translates to:
  /// **'La invitación ya no existe.'**
  String get serviceInviteNotFound;

  /// No description provided for @serviceCannotAcceptInvite.
  ///
  /// In es, this message translates to:
  /// **'No puedes aceptar esta invitación.'**
  String get serviceCannotAcceptInvite;

  /// No description provided for @serviceInviteNoLongerAvailable.
  ///
  /// In es, this message translates to:
  /// **'Esta invitación ya no está disponible.'**
  String get serviceInviteNoLongerAvailable;

  /// No description provided for @serviceNoQuestionsForCategory.
  ///
  /// In es, this message translates to:
  /// **'No hay preguntas disponibles para esta categoría.'**
  String get serviceNoQuestionsForCategory;

  /// No description provided for @serviceNoActiveCategoriesAvailable.
  ///
  /// In es, this message translates to:
  /// **'No hay categorías activas disponibles.'**
  String get serviceNoActiveCategoriesAvailable;

  /// No description provided for @serviceSeasonRewardNotificationTitle.
  ///
  /// In es, this message translates to:
  /// **'Recompensa semanal disponible'**
  String get serviceSeasonRewardNotificationTitle;

  /// No description provided for @serviceSeasonRewardNotificationBody.
  ///
  /// In es, this message translates to:
  /// **'Tu recompensa de la liga semanal está lista para reclamar.'**
  String get serviceSeasonRewardNotificationBody;

  /// No description provided for @serviceRealtimeChallengeTitle.
  ///
  /// In es, this message translates to:
  /// **'Reto en tiempo real'**
  String get serviceRealtimeChallengeTitle;

  /// No description provided for @serviceRealtimeChallengeBody.
  ///
  /// In es, this message translates to:
  /// **'{name} te invitó a una partida 1 vs 1 en tiempo real.'**
  String serviceRealtimeChallengeBody(String name);

  /// No description provided for @serviceRealtimeInviteAcceptedTitle.
  ///
  /// In es, this message translates to:
  /// **'Invitación en tiempo real aceptada'**
  String get serviceRealtimeInviteAcceptedTitle;

  /// No description provided for @serviceRealtimeInviteAcceptedBody.
  ///
  /// In es, this message translates to:
  /// **'{name} aceptó tu reto en tiempo real.'**
  String serviceRealtimeInviteAcceptedBody(String name);

  /// No description provided for @achievementFirstPvpWinTitle.
  ///
  /// In es, this message translates to:
  /// **'Primera victoria en duelo'**
  String get achievementFirstPvpWinTitle;

  /// No description provided for @achievementFirstPvpWinDescription.
  ///
  /// In es, this message translates to:
  /// **'Gana tu primera partida 1 vs 1.'**
  String get achievementFirstPvpWinDescription;

  /// No description provided for @achievementPvpWins10Title.
  ///
  /// In es, this message translates to:
  /// **'Duelista'**
  String get achievementPvpWins10Title;

  /// No description provided for @achievementPvpWins10Description.
  ///
  /// In es, this message translates to:
  /// **'Gana 10 partidas 1 vs 1.'**
  String get achievementPvpWins10Description;

  /// No description provided for @achievementPvpStreak5Title.
  ///
  /// In es, this message translates to:
  /// **'En racha'**
  String get achievementPvpStreak5Title;

  /// No description provided for @achievementPvpStreak5Description.
  ///
  /// In es, this message translates to:
  /// **'Alcanza una racha de 5 victorias en 1 vs 1.'**
  String get achievementPvpStreak5Description;

  /// No description provided for @achievementSoloLevels10Title.
  ///
  /// In es, this message translates to:
  /// **'Explorador solitario'**
  String get achievementSoloLevels10Title;

  /// No description provided for @achievementSoloLevels10Description.
  ///
  /// In es, this message translates to:
  /// **'Completa 10 niveles en solitario.'**
  String get achievementSoloLevels10Description;

  /// No description provided for @achievementDailyStreak7Title.
  ///
  /// In es, this message translates to:
  /// **'Hábito semanal'**
  String get achievementDailyStreak7Title;

  /// No description provided for @achievementDailyStreak7Description.
  ///
  /// In es, this message translates to:
  /// **'Alcanza una racha de 7 días en el Daily Challenge.'**
  String get achievementDailyStreak7Description;

  /// No description provided for @achievementFriends5Title.
  ///
  /// In es, this message translates to:
  /// **'Jugador social'**
  String get achievementFriends5Title;

  /// No description provided for @achievementFriends5Description.
  ///
  /// In es, this message translates to:
  /// **'Agrega 5 amigos.'**
  String get achievementFriends5Description;

  /// No description provided for @achievementPvpWins25Title.
  ///
  /// In es, this message translates to:
  /// **'Veterano de duelos'**
  String get achievementPvpWins25Title;

  /// No description provided for @achievementPvpWins25Description.
  ///
  /// In es, this message translates to:
  /// **'Gana 25 partidas 1 vs 1.'**
  String get achievementPvpWins25Description;

  /// No description provided for @achievementSoloLevels25Title.
  ///
  /// In es, this message translates to:
  /// **'Maestro solitario'**
  String get achievementSoloLevels25Title;

  /// No description provided for @achievementSoloLevels25Description.
  ///
  /// In es, this message translates to:
  /// **'Aprueba 25 niveles del modo Solo.'**
  String get achievementSoloLevels25Description;

  /// No description provided for @achievementDailyStreak21Title.
  ///
  /// In es, this message translates to:
  /// **'Constancia de hierro'**
  String get achievementDailyStreak21Title;

  /// No description provided for @achievementDailyStreak21Description.
  ///
  /// In es, this message translates to:
  /// **'Alcanza una racha de 21 días en el Desafío Diario.'**
  String get achievementDailyStreak21Description;

  /// No description provided for @achievementFriends10Title.
  ///
  /// In es, this message translates to:
  /// **'Círculo social'**
  String get achievementFriends10Title;

  /// No description provided for @achievementFriends10Description.
  ///
  /// In es, this message translates to:
  /// **'Agrega 10 amigos.'**
  String get achievementFriends10Description;

  /// No description provided for @achievementWeeklyTopics3Title.
  ///
  /// In es, this message translates to:
  /// **'Explorador semanal'**
  String get achievementWeeklyTopics3Title;

  /// No description provided for @achievementWeeklyTopics3Description.
  ///
  /// In es, this message translates to:
  /// **'Completa 3 Temas Semanales.'**
  String get achievementWeeklyTopics3Description;

  /// No description provided for @achievementCategoriesExplored5Title.
  ///
  /// In es, this message translates to:
  /// **'Mente curiosa'**
  String get achievementCategoriesExplored5Title;

  /// No description provided for @achievementCategoriesExplored5Description.
  ///
  /// In es, this message translates to:
  /// **'Aprueba al menos un nivel en 5 categorías fijas distintas del modo Solo (no incluye temas de IA).'**
  String get achievementCategoriesExplored5Description;

  /// No description provided for @serviceAchievementNotFound.
  ///
  /// In es, this message translates to:
  /// **'Logro no encontrado.'**
  String get serviceAchievementNotFound;

  /// No description provided for @serviceCouldNotClaimReward.
  ///
  /// In es, this message translates to:
  /// **'No se pudo reclamar la recompensa.'**
  String get serviceCouldNotClaimReward;

  /// No description provided for @serviceCouldNotCreateTopic.
  ///
  /// In es, this message translates to:
  /// **'No se pudo crear el tema.'**
  String get serviceCouldNotCreateTopic;

  /// No description provided for @serviceCouldNotRegenerateQuestions.
  ///
  /// In es, this message translates to:
  /// **'No se pudieron regenerar las preguntas.'**
  String get serviceCouldNotRegenerateQuestions;

  /// No description provided for @serviceCouldNotExpandTopic.
  ///
  /// In es, this message translates to:
  /// **'No se pudo ampliar el tema.'**
  String get serviceCouldNotExpandTopic;

  /// No description provided for @serviceCouldNotSearchTopics.
  ///
  /// In es, this message translates to:
  /// **'No se pudieron buscar temas similares.'**
  String get serviceCouldNotSearchTopics;

  /// No description provided for @serviceCouldNotSuggestTopics.
  ///
  /// In es, this message translates to:
  /// **'No se pudieron obtener sugerencias.'**
  String get serviceCouldNotSuggestTopics;

  /// No description provided for @pvpWindowSameLeagueLabel.
  ///
  /// In es, this message translates to:
  /// **'Misma liga'**
  String get pvpWindowSameLeagueLabel;

  /// No description provided for @pvpWindowSameLeagueDescription.
  ///
  /// In es, this message translates to:
  /// **'Buscando primero un rival muy cercano a tu MMR.'**
  String get pvpWindowSameLeagueDescription;

  /// No description provided for @pvpWindowNearbyLeaguesLabel.
  ///
  /// In es, this message translates to:
  /// **'Ligas cercanas'**
  String get pvpWindowNearbyLeaguesLabel;

  /// No description provided for @pvpWindowNearbyLeaguesDescription.
  ///
  /// In es, this message translates to:
  /// **'Ampliando a jugadores de ligas vecinas.'**
  String get pvpWindowNearbyLeaguesDescription;

  /// No description provided for @pvpWindowExpandedRangeLabel.
  ///
  /// In es, this message translates to:
  /// **'Rango ampliado'**
  String get pvpWindowExpandedRangeLabel;

  /// No description provided for @pvpWindowExpandedRangeDescription.
  ///
  /// In es, this message translates to:
  /// **'Priorizando encontrar partida sin perder competitividad.'**
  String get pvpWindowExpandedRangeDescription;

  /// No description provided for @pvpWindowAnyOpponentLabel.
  ///
  /// In es, this message translates to:
  /// **'Cualquier rival disponible'**
  String get pvpWindowAnyOpponentLabel;

  /// No description provided for @pvpWindowAnyOpponentDescription.
  ///
  /// In es, this message translates to:
  /// **'Ahora se prioriza que puedas jugar sin quedarte esperando.'**
  String get pvpWindowAnyOpponentDescription;

  /// No description provided for @weeklyRewardChampionBonus.
  ///
  /// In es, this message translates to:
  /// **'¡Bono de campeón!'**
  String get weeklyRewardChampionBonus;

  /// No description provided for @weeklyRewardTop3Bonus.
  ///
  /// In es, this message translates to:
  /// **'¡Bono top 3!'**
  String get weeklyRewardTop3Bonus;

  /// No description provided for @weeklyRewardTop10Bonus.
  ///
  /// In es, this message translates to:
  /// **'¡Bono top 10!'**
  String get weeklyRewardTop10Bonus;

  /// No description provided for @weeklyRewardGenericBonus.
  ///
  /// In es, this message translates to:
  /// **'Recompensa de liga semanal'**
  String get weeklyRewardGenericBonus;
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
