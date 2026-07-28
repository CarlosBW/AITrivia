// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get langSwitchLabelEn => 'EN';

  @override
  String get langSwitchLabelEs => 'ES';

  @override
  String get navChallengeAcceptedTitle => 'Reto aceptado';

  @override
  String get navChallengeAcceptedBodyFallback => 'Tu invitación fue aceptada.';

  @override
  String get navLater => 'Luego';

  @override
  String get navPlayNow => 'Jugar ahora';

  @override
  String get navNewNotificationTitle => 'Nueva notificación';

  @override
  String get navNewNotificationSubtitle => 'Revisa la campana';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonSave => 'Guardar';

  @override
  String get commonRetry => 'Reintentar';

  @override
  String get commonLoading => 'Cargando...';

  @override
  String get commonSaving => 'Guardando...';

  @override
  String get homeActionTimeout => 'La acción tardó demasiado.';

  @override
  String get homeCoins => 'Monedas';

  @override
  String get homeXp => 'XP';

  @override
  String get homeFreeTopic => 'Tema libre';

  @override
  String get homeAlreadyPlayedDaily => 'Ya jugaste el Daily Challenge de hoy.';

  @override
  String get homeMoreWaysToPlay => 'Más formas de jugar';

  @override
  String get homeWeeklyChallengeReward => 'Weekly Challenge • ¡Recompensa!';

  @override
  String get homeWeeklyChallenge => 'Weekly Challenge';

  @override
  String get homeTabsHint =>
      'Usa las pestañas inferiores para jugar SOLO, competir en PvP, retar amigos y ver tu perfil.';

  @override
  String get homeStreakUpTitle => '🔥 ¡RACHA!';

  @override
  String get homeStreakUpSubtitle => 'Sigue volviendo cada día';

  @override
  String get homeWelcomeBackTitle => '📅 ¡Volviste!';

  @override
  String homeLoginStreakLabel(int days) {
    return 'Racha de sesión: $days días';
  }

  @override
  String homeLoginStreakCoins(int coins) {
    return '+$coins monedas';
  }

  @override
  String homeLivesSuffix(String lives) {
    return '$lives vidas';
  }

  @override
  String get homeLivesFull => 'Vidas al máximo';

  @override
  String get homeAiTopicTitle => 'Tema libre (IA)';

  @override
  String get homeAiTopicSubtitle =>
      'Crea tu propio tema y juega con tus monedas';

  @override
  String get homeWeeklyTopicUnavailable => 'Weekly Topic no disponible';

  @override
  String get homeWeeklyTopicNoneAvailable => 'No hay Weekly Topic disponible';

  @override
  String get homeWeeklyTopicCheckBack =>
      'Vuelve pronto para un nuevo reto destacado.';

  @override
  String get homeWeeklyTopicLoading => 'Cargando Weekly Topic...';

  @override
  String get homeOpenWeeklyTopic => 'Abrir Weekly Topic';

  @override
  String homeWeeklyTopicRewardCoins(int coins) {
    return '+$coins monedas';
  }

  @override
  String get homeDailyChallengeTitle => 'Daily Challenge';

  @override
  String homeDailyChallengeStreak(int days) {
    return 'Racha: $days días';
  }

  @override
  String get homeReward => '¡Recompensa!';

  @override
  String get profileTitle => 'Perfil de jugador';

  @override
  String get profileEditUsername => 'Editar nombre de usuario';

  @override
  String get profileEnterUsername => 'Ingresa tu nombre de usuario';

  @override
  String get profileUsernameHelper => 'Debe ser único. Usa 3 a 20 caracteres.';

  @override
  String get profileUsernameLengthError =>
      'El nombre de usuario debe tener entre 3 y 20 caracteres.';

  @override
  String get profileUsernameCharsError =>
      'Usa solo letras, números y guion bajo.';

  @override
  String get profileUsernameTaken => 'Ese nombre de usuario ya existe.';

  @override
  String profileUpdateError(String error) {
    return 'Error actualizando perfil: $error';
  }

  @override
  String get profileUpdated => 'Perfil actualizado';

  @override
  String get profileAvatarCollection => 'Colección de avatares';

  @override
  String profileUnlockedCount(int count, int total) {
    return 'Desbloqueados $count / $total';
  }

  @override
  String get profileCurrentlyEquipped => 'Equipado actualmente';

  @override
  String get profileChooseFrame => 'Elegir marco';

  @override
  String profileEquippedNotice(String emoji, String name) {
    return '$emoji $name equipado';
  }

  @override
  String profileAvatarUpdateError(String error) {
    return 'Error actualizando avatar: $error';
  }

  @override
  String profileLevel(int level) {
    return 'Nivel $level';
  }

  @override
  String profileWeeklyScore(int score) {
    return 'Puntaje semanal: $score';
  }

  @override
  String profileXpToNextLevel(int current, int required) {
    return '$current / $required XP para el siguiente nivel';
  }

  @override
  String get profileAchievements => 'Logros';

  @override
  String get profileAchievementsSubtitle => 'Revisa tu progreso y recompensas';

  @override
  String get profileCoins => 'Monedas';

  @override
  String get profileFreeTopics => 'Temas gratis';

  @override
  String get profileStreak => 'Racha';

  @override
  String get profileBestStreak => 'Mejor racha';

  @override
  String get profileStats => 'Estadísticas';

  @override
  String get profileGamesPlayed => 'Partidas jugadas';

  @override
  String get profileCorrectAnswers => 'Respuestas correctas';

  @override
  String get profileWrongAnswers => 'Respuestas incorrectas';

  @override
  String get profileAccuracy => 'Precisión';

  @override
  String get profileBestDailyScore => 'Mejor puntaje diario';

  @override
  String profilePvpLeague(String league) {
    return 'Liga PvP $league';
  }

  @override
  String get profileRankedHint =>
      'Ranked busca primero rivales de tu liga y amplía el rango si no hay jugadores disponibles.';

  @override
  String get profile1v1Stats => 'Estadísticas 1 vs 1';

  @override
  String get profileRankedMmr => 'MMR clasificado';

  @override
  String get profileVictories => 'Victorias';

  @override
  String get profileDefeats => 'Derrotas';

  @override
  String get profileDraws => 'Empates';

  @override
  String get profileMatchesPlayed => 'Partidas jugadas';

  @override
  String get profileWinrate => '% de victorias';

  @override
  String get profileCurrentStreak => 'Racha actual';

  @override
  String get profileRecentMatches => 'Partidas PvP recientes';

  @override
  String get profileNoMatches => 'Aún no hay partidas PvP.';

  @override
  String profileVsOpponent(String opponent) {
    return 'vs $opponent';
  }

  @override
  String get profileScore => 'Puntaje';

  @override
  String get profileRanked => 'Clasificado';

  @override
  String get profileCasual => 'Casual';

  @override
  String profileErrorLoading(String error) {
    return 'Error cargando perfil:\n$error';
  }

  @override
  String get matchResultVictory => 'Victoria';

  @override
  String get matchResultDefeat => 'Derrota';

  @override
  String get matchResultDraw => 'Empate';

  @override
  String get matchResultMatch => 'Partida';

  @override
  String get avatarCategoryBase => 'BASE';

  @override
  String get avatarCategoryPvp => 'PVP';

  @override
  String get avatarCategoryWeekly => 'SEMANAL';

  @override
  String get avatarCategoryAchievement => 'LOGRO';

  @override
  String get avatarCategoryAi => 'IA';

  @override
  String get avatarCategoryAiUnique => 'IA ÚNICO';
}
