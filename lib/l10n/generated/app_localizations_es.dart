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
  String homeWeeklyResetsIn(String time) {
    return 'Termina en $time';
  }

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
  String get homeAchievementUnlockedTitle => '🏆 ¡Logro desbloqueado!';

  @override
  String homeAchievementUnlockedSubtitle(String icon, String title) {
    return '$icon $title';
  }

  @override
  String homeAchievementUnlockedRewards(int coins, int xp) {
    return '+$coins monedas · +$xp XP';
  }

  @override
  String get homeAvatarUnlockedTitle => '🎁 ¡Nuevo avatar desbloqueado!';

  @override
  String homeAvatarUnlockedSubtitle(String emoji, String name) {
    return '$emoji $name';
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
  String get homeWeeklyTopicDefaultDescription =>
      'Completa niveles y gana recompensas.';

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
  String get usernamePickerTitle => 'Elige tu nombre de usuario';

  @override
  String get usernamePickerSubtitle =>
      'Tus amigos te encontrarán por este nombre. No podrás cambiarlo después.';

  @override
  String get usernamePickerHint => 'Nombre de usuario';

  @override
  String get usernamePickerContinue => 'Continuar';

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
  String get profileLegalSectionTitle => 'Legal';

  @override
  String get profilePrivacyPolicy => 'Política de Privacidad';

  @override
  String get profileTermsOfService => 'Términos de Servicio';

  @override
  String get profileLinkOpenFailed => 'No se pudo abrir el enlace.';

  @override
  String get profileDangerZoneTitle => 'Zona peligrosa';

  @override
  String get profileDeleteAccount => 'Eliminar cuenta';

  @override
  String get profileDeleteAccountConfirmTitle => '¿Eliminar tu cuenta?';

  @override
  String get profileDeleteAccountConfirmBody =>
      'Esto borra tu perfil, progreso, monedas, amigos y temas creados de forma permanente. No se puede deshacer.';

  @override
  String get profileDeleteAccountConfirmAction => 'Eliminar permanentemente';

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

  @override
  String get livesNoLivesTitle => 'Sin vidas suficientes';

  @override
  String get livesNoLivesMessage =>
      'Necesitas al menos 1 vida completa para entrar a un nivel.';

  @override
  String get livesYourLives => 'Tus vidas';

  @override
  String get livesNextHalf => 'Próx. media vida';

  @override
  String get livesNextFull => 'Para 1 vida completa';

  @override
  String get livesGoBack => 'Volver';

  @override
  String get livesWait => 'Esperar';

  @override
  String livesRecoverButton(int cost) {
    return 'Recuperar 1 vida ($cost monedas)';
  }

  @override
  String get soloTabTitle => 'Solo';

  @override
  String soloErrorLoadingCategories(String error) {
    return 'Error al cargar categorías:\n$error';
  }

  @override
  String get soloNoCategoriesAvailable =>
      'No hay categorías activas en Firestore.';

  @override
  String get soloFixedTopics => 'Temas fijos';

  @override
  String get soloAllCompletedTitle => '¡Completaste todo el modo Solo!';

  @override
  String get soloAllCompletedBody =>
      'Sigue ganando monedas y XP en el Daily Challenge o retando a otros jugadores en PvP.';

  @override
  String get soloAllCompletedDailyButton => 'Ir al Daily Challenge';

  @override
  String get soloAllCompletedPvpButton => 'Ir a PvP';

  @override
  String get soloLifeRecovered => '❤️ Vida recuperada';

  @override
  String get soloNotEnoughCoins => '❌ No tienes suficientes monedas';

  @override
  String soloProgressLevels(int completed, int total) {
    return 'Progreso: $completed / $total niveles';
  }

  @override
  String get soloViewLevels => 'Ver niveles';

  @override
  String get soloStatusCompleted => 'Completado';

  @override
  String get soloStatusInProgress => 'En curso';

  @override
  String get soloStatusNew => 'Nuevo';

  @override
  String soloContinueLevel(int level) {
    return 'Continuar N$level';
  }

  @override
  String get levelSelectNoLevelsYet =>
      'Esta categoría aún no tiene niveles disponibles.';

  @override
  String get levelSelectChooseLevel => 'Selecciona un nivel';

  @override
  String get levelSelectAiTopicApproved => 'Tema IA aprobado';

  @override
  String get levelSelectCategoryApproved => 'Categoría aprobada';

  @override
  String get levelSelectAiTopicProgressApproved =>
      'Tu progreso aprobado en este tema IA';

  @override
  String get levelSelectCategoryProgressApproved =>
      'Tu progreso aprobado en esta categoría';

  @override
  String levelSelectApprovedCount(int completed, int total) {
    return 'Aprobados: $completed / $total';
  }

  @override
  String get levelSelectPlayLastLevel => 'Jugar último nivel';

  @override
  String levelSelectContinueAtLevel(int level) {
    return 'Continuar en nivel $level';
  }

  @override
  String get levelSelectAvailable => 'Disponible';

  @override
  String get levelSelectLocked => 'Bloqueado';

  @override
  String levelSelectLevelNumber(int level) {
    return 'Nivel $level';
  }

  @override
  String get levelSelectNextBadge => 'Siguiente';

  @override
  String get levelSelectLoadFailedTitle => 'No se pudo cargar la categoría.';

  @override
  String get levelPlayAiTopicLabel => 'Tema IA';

  @override
  String levelPlayAppBarTitle(String name, int level) {
    return '$name - Nivel $level';
  }

  @override
  String get levelPlayTimeUp => '⏰ Se acabó el tiempo';

  @override
  String get levelPlayTimeUpNoLives =>
      '⏰ Se acabó el tiempo - te quedaste sin vidas';

  @override
  String get levelPlayTimeUpLostHalfLife =>
      '⏰ Se acabó el tiempo - perdiste media vida';

  @override
  String get levelPlayTimeUpNoLifeLoss =>
      '⏰ Se acabó el tiempo - no perdiste vida';

  @override
  String get levelPlayWrongNoLives => '❌ Incorrecto - te quedaste sin vidas';

  @override
  String get levelPlayWrongLostHalfLife => '❌ Incorrecto - perdiste media vida';

  @override
  String get levelPlayWrongNoLifeLoss => '❌ Incorrecto - no perdiste vida';

  @override
  String get aiReportQuestionTooltip => 'Reportar esta pregunta';

  @override
  String get aiReportDialogTitle => '¿Qué pasa con esta pregunta?';

  @override
  String get aiReportDialogDetailsHint => 'Detalles adicionales (opcional)';

  @override
  String get aiReportDialogCancel => 'Cancelar';

  @override
  String get aiReportDialogSubmit => 'Enviar reporte';

  @override
  String get aiReportReasonWrongAnswer => 'La respuesta marcada está mal';

  @override
  String get aiReportReasonConfusing => 'Pregunta confusa o ambigua';

  @override
  String get aiReportReasonInappropriate => 'Contenido inapropiado';

  @override
  String get aiReportReasonOther => 'Otro motivo';

  @override
  String get aiReportSent => 'Gracias, reportamos la pregunta.';

  @override
  String get levelPlayNeedFullLife =>
      'Necesitas 1 vida completa para entrar a este nivel.';

  @override
  String levelPlayLifeCheckError(String error) {
    return 'Error verificando vidas: $error';
  }

  @override
  String get levelPlaySessionCreateErrorTitle => 'Error creando sesión';

  @override
  String get levelPlayGeneratingQuestions => 'Generando preguntas del nivel...';

  @override
  String get levelPlaySessionNotFound => 'Sesión no encontrada.';

  @override
  String get levelPlaySessionNoQuestions => 'Esta sesión no tiene preguntas.';

  @override
  String get levelPlayLivesMax => 'MAX';

  @override
  String get levelPlayOutOfLivesTitle => 'Te quedaste sin vidas';

  @override
  String get levelPlayOutOfLivesMessage =>
      'No puedes continuar este nivel hasta recuperar vidas.';

  @override
  String levelPlayLivesHeader(String lives) {
    return 'Vidas: $lives';
  }

  @override
  String levelPlayHalfLifeIn(String time) {
    return '+0.5 en $time';
  }

  @override
  String levelPlayQuestionOfTotal(int current, int total) {
    return 'Pregunta $current de $total';
  }

  @override
  String get levelPlayRankExpert => 'Experto';

  @override
  String get levelPlayRankAdvanced => 'Avanzado';

  @override
  String get levelPlayRankIntermediate => 'Intermedio';

  @override
  String get levelPlayRankBeginner => 'Novato';

  @override
  String get levelPlayLevelPassed => '¡Nivel aprobado!';

  @override
  String get levelPlayLevelFinished => 'Nivel finalizado';

  @override
  String levelPlayScoreLine(int correct, int total, String pct) {
    return 'Puntaje: $correct / $total ($pct)';
  }

  @override
  String levelPlayRankLine(String rank) {
    return 'Rango: $rank';
  }

  @override
  String get levelPlayRewardsTitle => 'Recompensas';

  @override
  String get levelPlayAlreadyPassedBefore =>
      'Este nivel ya había sido aprobado antes.';

  @override
  String get levelPlayNeed40Percent =>
      'Necesitas al menos 40% de aciertos para aprobar este nivel.';

  @override
  String get levelPlaySavingProgress => 'Guardando progreso...';

  @override
  String levelPlaySaveError(String error) {
    return 'Error guardando: $error';
  }

  @override
  String get levelPlayRetrySave => 'Reintentar guardado';

  @override
  String get levelPlayProgressSaved => '✅ Progreso guardado';

  @override
  String levelPlayContinueNextLevel(int level) {
    return 'Continuar (Nivel $level)';
  }

  @override
  String get levelPlayWeeklyCounted =>
      'Cuenta para el evento semanal. Este nivel avanzó tu progreso de recompensas semanales.';

  @override
  String get levelPlayWeeklyNotCounted =>
      'No cuenta para el evento semanal. Necesitas al menos 40% de aciertos para que este nivel avance tus recompensas semanales.';

  @override
  String levelPlayPlayerLevel(int level) {
    return 'Nivel de jugador $level';
  }

  @override
  String levelPlayTotalXp(int xp) {
    return 'XP total: $xp';
  }

  @override
  String levelPlayLevelUp(int level) {
    return '¡SUBISTE! Nivel $level';
  }

  @override
  String levelPlayLeveledUpTo(int level) {
    return '¡Subiste al nivel $level!';
  }

  @override
  String levelPlayXpInLevel(int current, int total) {
    return '$current / $total XP en este nivel';
  }

  @override
  String get pvpHubTitle => 'PvP';

  @override
  String get pvpHubHeading => 'Centro competitivo';

  @override
  String get pvpHubSubheading => 'Elige cómo quieres competir.';

  @override
  String get pvpActiveMatchesTitle => 'Partidas Activas';

  @override
  String get pvpActiveMatchesTitleAlert => 'Partidas Activas • ¡Tu turno!';

  @override
  String get pvpActiveMatchesSubtitle =>
      'Turnos pendientes, partidas en vivo y resultados recientes.';

  @override
  String get pvpActiveMatchesSubtitleAlert =>
      'Tienes partidas pendientes esperando tu jugada.';

  @override
  String get pvpRealtimeInvitesTitle => 'Invitaciones en Vivo';

  @override
  String get pvpRealtimeInvitesTitleAlert => 'Invitaciones en Vivo • ¡Nuevo!';

  @override
  String get pvpRealtimeInvitesSubtitle =>
      'Acepta o rechaza retos en vivo. Para retar a un amigo, ve a la pestaña Friends.';

  @override
  String get pvpRealtimeInvitesSubtitleAlert =>
      'Tienes retos en vivo esperando.';

  @override
  String get pvpFindOpponentTitle => 'Buscar Rival';

  @override
  String get pvpFindOpponentSubtitle =>
      'Juega contra cualquier retador disponible.';

  @override
  String get pvpSeasonTitle => 'Temporada PvP';

  @override
  String get pvpSeasonSubtitle =>
      'Consulta tu liga ranked, progreso de temporada, leaderboard y recompensas.';

  @override
  String get activeMatchesTitle => 'Partidas Activas';

  @override
  String get activeMatchesReconnecting => 'Reconectando...';

  @override
  String get activeMatchesYourTurn => 'Tu turno';

  @override
  String get activeMatchesLoadingYourMatches => 'Cargando tus partidas...';

  @override
  String get activeMatchesNoneWaitingForYou =>
      'No tienes partidas asíncronas pendientes.';

  @override
  String get activeMatchesWaitingForOpponent => 'Esperando al rival';

  @override
  String get activeMatchesLoadingMatches => 'Cargando partidas...';

  @override
  String get activeMatchesNoneWaitingForOpponent =>
      'No hay partidas esperando a tu rival.';

  @override
  String get activeMatchesRecentlyFinished => 'Finalizadas recientemente';

  @override
  String get activeMatchesLoadingResults => 'Cargando resultados...';

  @override
  String get activeMatchesNoneFinished =>
      'No hay partidas finalizadas recientes.';

  @override
  String activeMatchesYourTurnSubtitle(String category) {
    return 'Tu turno • $category';
  }

  @override
  String activeMatchesWaitingSubtitle(int score) {
    return 'Esperando • Tu puntaje: $score';
  }

  @override
  String activeMatchesDrawSubtitle(int a, int b) {
    return 'Empate • $a-$b';
  }

  @override
  String activeMatchesVictorySubtitle(int a, int b) {
    return 'Victoria • $a-$b';
  }

  @override
  String activeMatchesDefeatSubtitle(int a, int b) {
    return 'Derrota • $a-$b';
  }

  @override
  String get activeMatchesPlay => 'Jugar';

  @override
  String get activeMatchesView => 'Ver';

  @override
  String get activeMatchesResult => 'Resultado';

  @override
  String get findOpponentTitle => 'Buscar rival';

  @override
  String get findOpponentLiveTab => 'Tiempo real';

  @override
  String get findOpponentAsyncTab => 'Asíncrono';

  @override
  String liveMenuLeagueTitle(String name) {
    return 'Liga $name';
  }

  @override
  String get liveMenuMmrHint1 => 'Buscar rival afecta tu MMR y tu liga PvP.';

  @override
  String get liveMenuFixedTopicLabel => 'Tema fijo';

  @override
  String get liveMenuPublicMatchmaking => 'Matchmaking público';

  @override
  String get liveMenuMmrHint2 =>
      'Buscar rival afecta tu MMR, liga y estadísticas PvP.';

  @override
  String get liveMenuPrivateMatches => 'Partidas privadas';

  @override
  String get liveMenuCreatePrivateRoom => 'Crear sala privada';

  @override
  String get liveMenuJoinWithCode => 'Unirme con código';

  @override
  String get liveMenuPrivateMatchesHint =>
      'Las partidas privadas son amistosas y no afectan tu ranking.';

  @override
  String get asyncMenuSelectTopicFirst => 'Selecciona un tema fijo primero.';

  @override
  String get asyncMenuConfigTitle => 'Configuración';

  @override
  String get asyncMenuFixedTopicsLabel => 'Temas fijos';

  @override
  String get asyncMenuNoActiveCategories => 'No hay categorías activas.';

  @override
  String get asyncMenuSelectTopicLabel => 'Selecciona un tema fijo';

  @override
  String get asyncMenuFindPlayerButton => 'Buscar jugador para retar';

  @override
  String get asyncMenuTip =>
      'Tip: Retas a alguien, juegas inmediatamente y tu rival puede jugar luego. Revisa Active Matches para ver tus retos pendientes.';

  @override
  String get createMatchTitle => 'Crear sala (Tiempo real)';

  @override
  String get createMatchYourName => 'Tu nombre (displayName)';

  @override
  String get createMatchCategory => 'Categoría';

  @override
  String get createMatchDifficulty => 'Dificultad';

  @override
  String get createMatchDiffEasy => '1 (Fácil)';

  @override
  String get createMatchDiffMedium => '2 (Medio)';

  @override
  String get createMatchDiffHard => '3 (Difícil)';

  @override
  String get createMatchTimePerQuestion => 'Tiempo/Pregunta';

  @override
  String get createMatchQuestions => 'Preguntas';

  @override
  String get createMatchAutoSearch => 'Buscar jugador automático';

  @override
  String get createMatchCreateRoom => 'Crear sala';

  @override
  String get joinMatchTitle => 'Unirme';

  @override
  String get joinMatchCodeLabel => 'Código de sala (ej: A7KQ2)';

  @override
  String get liveMatchmakingRankedTitle => 'Matchmaking Ranked';

  @override
  String get liveMatchmakingCasualTitle => 'Matchmaking Casual';

  @override
  String liveMatchmakingTypeLine(String type) {
    return 'Tipo: $type';
  }

  @override
  String liveMatchmakingCategoryLine(String category) {
    return 'Categoría: $category';
  }

  @override
  String liveMatchmakingDifficultyLine(int difficulty) {
    return 'Dificultad: $difficulty';
  }

  @override
  String liveMatchmakingQuestionsLine(int total) {
    return 'Preguntas: $total';
  }

  @override
  String liveMatchmakingTimePerQuestionLine(int seconds) {
    return 'Tiempo/Pregunta: ${seconds}s';
  }

  @override
  String get liveMatchmakingNoOpponentFound =>
      'No se encontró rival por ahora. Intenta nuevamente.';

  @override
  String get liveMatchmakingTryAsyncInstead => 'Jugar asíncrono en su lugar';

  @override
  String get liveMatchmakingSearchButton => 'Buscar';

  @override
  String get liveMatchmakingSearching => 'Buscando...';

  @override
  String get liveMatchmakingSearchingOpponent => 'Buscando rival...';

  @override
  String liveMatchmakingQueueStatus(String status) {
    return 'Estado cola: $status';
  }

  @override
  String get liveMatchmakingRankedHint =>
      'Primero busca rivales cercanos a tu MMR; si tarda, amplía el rango automáticamente.';

  @override
  String get liveMatchmakingCasualHint =>
      'Casual no afecta tu MMR. Se prioriza encontrar rival rápido.';

  @override
  String get liveMatchmakingCancelSearch => 'Cancelar búsqueda';

  @override
  String get asyncFindPlayersCannotChallengeSelf =>
      'No puedes retarte a ti mismo.';

  @override
  String get asyncFindPlayersTitle => 'Buscar jugador (asíncrono)';

  @override
  String get asyncFindPlayersSearchLabel => 'Buscar por nombre';

  @override
  String get asyncFindPlayersNoneToShow => 'No hay jugadores para mostrar.';

  @override
  String get asyncFindPlayersChallengeButton => 'Retar';

  @override
  String get realtimeInvitesDeclined => 'Invitación rechazada';

  @override
  String realtimeInvitesErrorLoading(String error) {
    return 'Error cargando invitaciones:\n$error';
  }

  @override
  String realtimeInvitesInvitedYou(String name) {
    return '$name te invitó';
  }

  @override
  String realtimeInvitesSubtitle(String category) {
    return '1 vs 1 en vivo • Categoría: $category';
  }

  @override
  String get realtimeInvitesDecline => 'Rechazar';

  @override
  String get realtimeInvitesAccept => 'Aceptar';

  @override
  String get realtimeInvitesEmpty =>
      'No tienes invitaciones en vivo por ahora.';

  @override
  String get friendChallengeNotOnline =>
      'Tu amigo no está conectado para jugar en tiempo real.';

  @override
  String friendChallengeRealtimeSent(String name) {
    return 'Reto en tiempo real enviado a $name';
  }

  @override
  String get friendChallengeOnline => 'Online';

  @override
  String get friendChallengeOffline => 'Offline';

  @override
  String get friendChallengeSendRealtime => 'Enviar reto en tiempo real';

  @override
  String get friendChallengeCreateAsync => 'Crear reto asíncrono';

  @override
  String get friendChallengeTitle => 'Configurar reto';

  @override
  String get friendChallengeTypeLabel => 'Tipo de reto';

  @override
  String get friendChallengeNeedOnlineHint =>
      'Tu amigo debe estar online para jugar en tiempo real.';

  @override
  String get friendChallengeMatchConfig => 'Configuración del match';

  @override
  String get friendChallengeCategoryRandom => 'Aleatorio';

  @override
  String get friendChallengeDiffEasy => 'Fácil';

  @override
  String get friendChallengeDiffMedium => 'Media';

  @override
  String get friendChallengeDiffHard => 'Difícil';

  @override
  String get friendChallengeQuestionCountLabel => 'Cantidad de preguntas';

  @override
  String friendChallengeQuestionsCount(int count) {
    return '$count preguntas';
  }

  @override
  String get friendChallengeTimePerQuestionLabel => 'Tiempo por pregunta';

  @override
  String friendChallengeSeconds(int seconds) {
    return '$seconds segundos';
  }

  @override
  String get friendChallengeRealtimeHint =>
      'Tiempo real requiere que ambos estén online. Las partidas con amigos son casuales y no afectan MMR.';

  @override
  String get friendChallengeAsyncHint =>
      'Asíncrono permite que tu amigo juegue cuando pueda. No afecta MMR.';

  @override
  String get matchLobbyWaitingFriendJoin =>
      'Esperando que tu amigo se una a la sala.';

  @override
  String get matchLobbyAllReadyStarting =>
      'Todo listo. La partida está iniciando...';

  @override
  String get matchLobbyReadyWaitingOpponent =>
      'Listo. Esperando que tu rival confirme.';

  @override
  String get matchLobbyOpponentReadyConfirm =>
      'Tu rival ya está listo. Confirma para empezar.';

  @override
  String get matchLobbyWaitingBothReady =>
      'Esperando que ambos jugadores estén listos.';

  @override
  String get matchLobbyTitle => 'Sala 1 vs 1';

  @override
  String get matchLobbyNotFound => 'Sala no encontrada';

  @override
  String get matchLobbyNoLongerAvailable => 'La sala ya no está disponible.';

  @override
  String get matchLobbyHeading => 'Partida 1 vs 1';

  @override
  String get matchLobbyTopicLabel => 'Tema';

  @override
  String get matchLobbyModeLabel => 'Modo';

  @override
  String get matchLobbyModeFixed => 'Sin IA';

  @override
  String get matchLobbyModeAi => 'Con IA';

  @override
  String get matchLobbyTimeLabel => 'Tiempo';

  @override
  String matchLobbySecondsPerQuestion(int seconds) {
    return '$seconds s por pregunta';
  }

  @override
  String get matchLobbyCodeCopied => 'Código copiado';

  @override
  String get matchLobbyWaitingOpponentButton => 'Esperando rival';

  @override
  String get matchLobbyWaitingOpponentEllipsis => 'Esperando rival...';

  @override
  String get matchLobbyImReady => 'Estoy listo';

  @override
  String get matchLobbyCancelReady => 'Cancelar listo';

  @override
  String matchLobbyRoomStatus(String status) {
    return 'Estado de la sala: $status';
  }

  @override
  String get matchLobbyPlayer1 => 'Jugador 1';

  @override
  String get matchLobbyPlayer2 => 'Jugador 2';

  @override
  String get matchLobbyReadyLabel => 'Listo';

  @override
  String get matchLobbyWaitingLabel => 'Esperando...';

  @override
  String get matchLobbyRoomCodeLabel => 'Código de sala';

  @override
  String get matchLobbyCopyCodeButton => 'Copiar código';

  @override
  String get pvpResultPerfectDraw => 'Empate perfecto';

  @override
  String pvpResultWonByPoints(int diff) {
    return 'Ganaste por +$diff puntos';
  }

  @override
  String pvpResultLostByPoints(int diff) {
    return 'Perdiste por $diff puntos';
  }

  @override
  String get pvpResultFinalResult => 'Resultado final';

  @override
  String get pvpResultVs => 'VS';

  @override
  String get pvpResultMatchSummary => 'Resumen del match';

  @override
  String get pvpResultYourScore => 'Tu score';

  @override
  String get pvpResultOpponent => 'Rival';

  @override
  String get pvpResultPerformance => 'Rendimiento';

  @override
  String get pvpResultBefore => 'Antes';

  @override
  String get pvpResultNow => 'Ahora';

  @override
  String pvpResultCurrentStreak(int count) {
    return '🔥 Racha actual: $count victorias';
  }

  @override
  String get matchPlayRematchRequestTitle => 'Solicitud de revancha';

  @override
  String matchPlayRematchRequestBody(String name) {
    return '$name quiere jugar una revancha.';
  }

  @override
  String get matchPlayTitle => '1 vs 1';

  @override
  String get matchPlayNotFound => 'Match no encontrado';

  @override
  String get matchPlayWaitingToStart => 'Esperando que inicie...';

  @override
  String get matchPlayNoQuestions => 'Este match no tiene preguntas.';

  @override
  String get matchPlayYourScoreLabel => 'Tu puntaje';

  @override
  String get matchPlayWaitingFinalResult => 'Esperando resultado final...';

  @override
  String get matchPlayOpponentStillAnswering =>
      'Tu rival todavía está respondiendo preguntas.';

  @override
  String matchPlayYourScoreLine(int score) {
    return 'Tu puntaje: $score';
  }

  @override
  String get matchPlayDrawTitle => 'Empate';

  @override
  String get matchPlayDrawSubtitle => 'Ambos terminaron con el mismo puntaje.';

  @override
  String get matchPlayVictoryTitle => '¡Ganaste!';

  @override
  String get matchPlayVictoryRankedSubtitle =>
      'Buen duelo. Tu rating competitivo fue actualizado.';

  @override
  String get matchPlayVictoryCasualSubtitle =>
      'Buen duelo. Sumaste una victoria 1 vs 1.';

  @override
  String get matchPlayDefeatTitle => 'Perdiste';

  @override
  String get matchPlayDefeatRankedSubtitle =>
      'Estuviste cerca. Tu rating competitivo fue actualizado.';

  @override
  String get matchPlayDefeatCasualSubtitle =>
      'Estuviste cerca. Intenta una revancha.';

  @override
  String get matchPlayRematch => 'Revancha';

  @override
  String get matchPlaySendingRequest => 'Enviando solicitud...';

  @override
  String get matchPlayRequestSent => 'Solicitud enviada ✓';

  @override
  String get matchPlayCreatingRematch => 'Creando revancha...';

  @override
  String get matchPlayExit => 'Salir';

  @override
  String get asyncMatchPlayTitle => 'Reto asíncrono';

  @override
  String get asyncMatchPlayNotFound => 'Reto no encontrado';

  @override
  String get asyncMatchPlayNoQuestions => 'Este reto no tiene preguntas.';

  @override
  String get asyncMatchPlayYouFallback => 'Tú';

  @override
  String get asyncMatchPlayOpponentFallback => 'Rival';

  @override
  String get asyncMatchPlayCorrectLabel => 'Aciertos';

  @override
  String get asyncMatchPlayChallengeCompletedTitle => 'Reto completado';

  @override
  String get asyncMatchPlaySendingResultSubtitle =>
      'Enviando tu resultado. Luego esperaremos a tu rival.';

  @override
  String get asyncMatchPlayAlreadyPlayedTitle => 'Ya jugaste este reto';

  @override
  String get asyncMatchPlayCalculatingFinal =>
      'Tu resultado fue enviado. Calculando resultado final.';

  @override
  String get asyncMatchPlayWaitingOpponentPlay =>
      'Tu resultado fue enviado. Esperando que tu rival juegue.';

  @override
  String get asyncMatchPlaySendingRematch => 'Enviando revancha...';

  @override
  String get pvpSeasonTabSeason => 'Temporada';

  @override
  String get pvpSeasonTabLeaderboard => 'Clasificación';

  @override
  String get pvpSeasonTabRewards => 'Recompensas';

  @override
  String pvpSeasonLabel(String id) {
    return 'Temporada: $id';
  }

  @override
  String pvpSeasonEndsIn(String time) {
    return 'Termina en: $time';
  }

  @override
  String pvpSeasonProjectedReward(int coins) {
    return 'Recompensa proyectada: +$coins monedas';
  }

  @override
  String get pvpSeasonRankedHint =>
      'Ranked usa matchmaking flexible: primero busca cerca de tu liga, luego amplía el rango para que nadie se quede esperando.';

  @override
  String get pvpSeasonHowItWorksTitle => 'Cómo funcionan las Temporadas PvP';

  @override
  String get pvpSeasonHowItWorksBullet1 =>
      '• Juega partidas Ranked para subir tu MMR.';

  @override
  String get pvpSeasonHowItWorksBullet2 =>
      '• Tu liga se calcula según tu MMR actual.';

  @override
  String get pvpSeasonHowItWorksBullet3 =>
      '• Las clasificaciones ordenan a los jugadores por MMR.';

  @override
  String get pvpSeasonHowItWorksBullet4 =>
      '• Las recompensas se basan en tu liga final cuando termina la temporada.';

  @override
  String get pvpSeasonFriendsTab => 'Amigos';

  @override
  String get pvpSeasonGlobalTab => 'Global';

  @override
  String get pvpSeasonAllTab => 'Todas';

  @override
  String pvpSeasonErrorLoadingFriends(String error) {
    return 'Error cargando clasificación de amigos:\n$error';
  }

  @override
  String get pvpSeasonNoFriendsTitle => 'Aún no hay amigos en la clasificación';

  @override
  String get pvpSeasonNoFriendsEmptyHint =>
      'Juega partidas Ranked y agrega amigos para comparar tu rating PvP.';

  @override
  String get pvpSeasonNoFriendsHint =>
      'Agrega amigos para comparar tu rating PvP con gente que conoces.';

  @override
  String pvpSeasonYouSuffix(String name) {
    return '$name (Tú)';
  }

  @override
  String pvpSeasonMatchesCount(int count) {
    return '$count partidas';
  }

  @override
  String pvpSeasonWinLossDraw(int wins, int losses, int draws) {
    return '$wins G / $losses P / $draws E';
  }

  @override
  String pvpSeasonErrorLoadingLeaderboard(String error) {
    return 'Error cargando clasificación:\n$error';
  }

  @override
  String get pvpSeasonNoRankedPlayers =>
      'Aún no hay jugadores ranked.\nJuega una partida Ranked para entrar en esta clasificación.';

  @override
  String get pvpSeasonRewardsTitle => 'Recompensas de Temporada';

  @override
  String get pvpSeasonRewardsSubtitle =>
      'Las recompensas se basan en tu mejor liga PvP de cada temporada finalizada.';

  @override
  String get pvpSeasonCurrentProjectedReward => 'Recompensa proyectada actual';

  @override
  String pvpSeasonEndsInLine(String time) {
    return 'La temporada termina en $time';
  }

  @override
  String get pvpSeasonCheckingRewards =>
      'Verificando recompensas de temporada PvP pendientes...';

  @override
  String get pvpSeasonCouldNotLoad => 'No se pudieron cargar las recompensas';

  @override
  String get pvpSeasonNoRewardYetTitle => 'Aún no hay recompensa disponible';

  @override
  String get pvpSeasonNoRewardYetHint =>
      'Juega partidas Ranked esta temporada. Cuando termine, tu recompensa PvP aparecerá aquí.';

  @override
  String pvpSeasonPendingSingle(int count) {
    return '$count recompensa de temporada pendiente';
  }

  @override
  String pvpSeasonPendingMultiple(int count) {
    return '$count recompensas de temporada pendientes';
  }

  @override
  String pvpSeasonMorePending(int count) {
    return '+$count temporada(s) pendiente(s) más';
  }

  @override
  String get pvpSeasonClaiming => 'Reclamando...';

  @override
  String get pvpSeasonClaimAllButton => 'Reclamar todas las recompensas';

  @override
  String get pvpSeasonNoPendingRewards =>
      'No hay recompensas de temporada PvP pendientes.';

  @override
  String pvpSeasonClaimedRewards(int count, int coins) {
    return '¡Reclamaste $count recompensa(s) de temporada PvP: +$coins monedas!';
  }

  @override
  String get dailyResultTitle => 'Resultado del Daily Challenge';

  @override
  String get dailyResultComplete => '¡Daily Challenge completado!';

  @override
  String get dailyResultCorrectAnswers => 'Respuestas correctas';

  @override
  String get dailyResultTotalAnswered => 'Total respondidas';

  @override
  String get dailyResultCoinsEarned => 'Monedas ganadas';

  @override
  String get dailyResultStreakLabel => 'Racha diaria';

  @override
  String dailyResultDaysValue(int days) {
    return '$days días';
  }

  @override
  String get dailyResultStreakBonus => 'Bono de racha';

  @override
  String get dailyResultAlreadyPlayed =>
      'Ya jugaste hoy. No se otorgaron monedas nuevamente.';

  @override
  String get dailyResultBackHome => 'Volver al inicio';

  @override
  String dailyResultNextChallengeIn(String time) {
    return 'Próximo desafío en $time';
  }

  @override
  String get dailyResultViewLeaderboard => 'Ver ranking de hoy';

  @override
  String get weeklyRewardsTitle => 'Recompensas semanales';

  @override
  String get weeklyRewardsNoPending =>
      'No hay recompensas semanales pendientes.';

  @override
  String weeklyRewardsClaimed(int count, int coins) {
    return '¡Reclamaste $count recompensa(s): +$coins monedas!';
  }

  @override
  String get weeklyRewardsChecking =>
      'Verificando recompensas semanales pendientes...';

  @override
  String get weeklyRewardsNoPendingTitle =>
      'No hay recompensas semanales pendientes';

  @override
  String get weeklyRewardsKeepPlayingHint =>
      'Sigue jugando el Weekly Challenge para ganar recompensas semanales.';

  @override
  String weeklyRewardsPendingSingle(int count) {
    return '$count recompensa pendiente';
  }

  @override
  String weeklyRewardsPendingMultiple(int count) {
    return '$count recompensas pendientes';
  }

  @override
  String weeklyRewardsTotalAvailable(int coins) {
    return 'Total disponible: +$coins monedas';
  }

  @override
  String weeklyRewardsMiniTile(
      String seasonId, String leagueName, int rank, String message) {
    return '$seasonId • $leagueName • Puesto #$rank • $message';
  }

  @override
  String get weeklyRewardsHistoryTitle => 'Historial de recompensas semanales';

  @override
  String get weeklyRewardsNoHistory =>
      'Aún no has reclamado recompensas de temporada.';

  @override
  String weeklyRewardsHistoryTitleLine(String seasonId, String leagueName) {
    return '$seasonId • $leagueName';
  }

  @override
  String weeklyRewardsHistorySubtitle(int rank, int score, String message) {
    return 'Puesto #$rank • Puntaje $score • $message';
  }

  @override
  String get weeklyRewardsLeagueFallback => 'Liga';

  @override
  String get weeklyRewardsMessageFallback => 'Recompensa semanal reclamada';

  @override
  String weeklyRewardsErrorLoadingHistory(String error) {
    return 'Error cargando historial:\n$error';
  }

  @override
  String get dailyLeaderboardTitle => 'Clasificación Diaria';

  @override
  String dailyLeaderboardErrorLoading(String error) {
    return 'Error cargando clasificación:\n$error';
  }

  @override
  String get dailyLeaderboardNoData =>
      'No hay datos de clasificación disponibles.';

  @override
  String get dailyLeaderboardNoScoresYet =>
      'Aún no hay puntajes hoy.\n¡Juega el Daily Challenge primero!';

  @override
  String get dailyLeaderboardRankingTitle => 'Clasificación';

  @override
  String dailyLeaderboardPtsSuffix(int score) {
    return '$score pts';
  }

  @override
  String dailyLeaderboardNameWithYou(String name) {
    return '$name  (Tú)';
  }

  @override
  String dailyLeaderboardCorrectStreakLine(int correct, int total, int streak) {
    return 'Correctas: $correct / $total  •  Racha: $streak';
  }

  @override
  String get dailyLeaderboardScoreLabel => 'Puntaje';

  @override
  String get dailyChallengeCoinsPopup => '+5 Monedas 🎉';

  @override
  String dailyChallengeErrorSaving(String error) {
    return 'Error guardando resultados: $error';
  }

  @override
  String get dailyChallengeNoQuestions => 'No hay preguntas disponibles';

  @override
  String get dailyChallengeTimeLabel => 'Tiempo';

  @override
  String dailyChallengeDifficultyLine(String level) {
    return 'Dificultad: $level';
  }

  @override
  String dailyChallengeAnsweredCount(int count) {
    return 'Respondidas: $count';
  }

  @override
  String get dailyChallengeCompletedTitle => '¡Daily completado!';

  @override
  String get dailyChallengeSavingResults => 'Guardando tus resultados...';

  @override
  String get weeklyTopicScreenTitle => 'Weekly Topic';

  @override
  String weeklyTopicCoinsClaimed(int coins) {
    return '¡$coins monedas reclamadas!';
  }

  @override
  String get weeklyTopicRewardUnavailable =>
      'La recompensa ya fue reclamada o aún no está disponible.';

  @override
  String get weeklyTopicNoExclusiveReward =>
      'No hay recompensa exclusiva configurada para esta semana.';

  @override
  String weeklyTopicAvatarUnlocked(String emoji, String name) {
    return '¡$emoji $name desbloqueado!';
  }

  @override
  String get weeklyTopicFeaturedBadge => 'Tema Semanal Destacado';

  @override
  String get weeklyTopicProgressTitle => 'Progreso';

  @override
  String weeklyTopicLevelsCompleted(int count) {
    return '$count / 10 niveles completados';
  }

  @override
  String get weeklyTopicRewardsTitle => 'Recompensas';

  @override
  String weeklyTopicFiveLevelReward(int coins) {
    return '5 niveles: +$coins monedas';
  }

  @override
  String get weeklyTopicCoinRewardClaimed => 'Recompensa de monedas reclamada';

  @override
  String get weeklyTopicClaim5LevelReward => 'Reclamar recompensa de 5 niveles';

  @override
  String weeklyTopicTenLevelReward(String emoji, String name) {
    return '10 niveles: $emoji $name';
  }

  @override
  String get weeklyTopicExclusiveClaimed => 'Recompensa exclusiva reclamada.';

  @override
  String get weeklyTopicExclusiveReady =>
      'Recompensa exclusiva lista para reclamar.';

  @override
  String get weeklyTopicExclusiveLocked =>
      'Completa los 10 niveles para desbloquear esta recompensa.';

  @override
  String get weeklyTopicExclusiveClaimedButton =>
      'Recompensa exclusiva reclamada';

  @override
  String get weeklyTopicClaim10LevelReward =>
      'Reclamar recompensa de 10 niveles';

  @override
  String get weeklyTopicCategoryMissing =>
      'Falta la categoría del Weekly Topic.';

  @override
  String get weeklyTopicPlayButton => 'Jugar Weekly Topic';

  @override
  String weeklyTopicCorrectAnswersProgress(int correct, int total) {
    return '$correct / $total respuestas correctas';
  }

  @override
  String weeklyTopicCoinRewardDescription(int threshold, int coins) {
    return '$threshold respuestas correctas: +$coins monedas';
  }

  @override
  String get weeklyTopicClaimCoinReward => 'Reclamar recompensa de monedas';

  @override
  String weeklyTopicCompletionRewardDescription(
      int threshold, String emoji, String name) {
    return '$threshold respuestas correctas: $emoji $name';
  }

  @override
  String get weeklyTopicClaimCompletionReward =>
      'Reclamar recompensa exclusiva';

  @override
  String weeklyTopicExclusiveLockedRounds(int threshold) {
    return 'Consigue $threshold respuestas correctas para desbloquear esta recompensa.';
  }

  @override
  String get weeklyTopicRoundResultTitle => 'Ronda completada';

  @override
  String weeklyTopicRoundResultBody(int correct, int total) {
    return 'Respondiste correctamente $correct de $total preguntas.';
  }

  @override
  String get weeklyTopicRoundResultButton => 'Continuar';

  @override
  String weeklyTopicRoundQuestionCount(int current, int total) {
    return 'Pregunta $current de $total';
  }

  @override
  String weeklyTopicRoundCorrectCount(int correct) {
    return 'Correctas: $correct';
  }

  @override
  String get weeklyLeagueScreenTitle => 'Weekly Challenge';

  @override
  String weeklyLeagueErrorLoading(String error) {
    return 'Error cargando el desafío semanal:\n$error';
  }

  @override
  String get weeklyLeagueNoScoresYet =>
      'Aún no hay puntajes semanales.\nJuega un Daily Challenge para entrar en esta clasificación semanal.';

  @override
  String get weeklyLeagueRankingTitle => 'Clasificación Semanal';

  @override
  String weeklyLeagueTierSuffix(String name) {
    return 'Nivel $name';
  }

  @override
  String weeklyLeagueScoreLabel(int score) {
    return 'Puntaje semanal: $score';
  }

  @override
  String weeklyLeagueResetIn(String time) {
    return 'Reinicio semanal en $time';
  }

  @override
  String get weeklyLeagueRewardHistoryButton => 'Historial de recompensas';

  @override
  String get weeklyLeaguePendingSeasonRewards =>
      'Recompensas de temporada pendientes';

  @override
  String get weeklyLeagueOpenToSeeDetails =>
      'Abre Recompensas Semanales para ver tu puesto y monedas exactas.';

  @override
  String get weeklyLeagueViewDetails => 'Ver detalles';

  @override
  String get weeklyLeagueClaim => 'Reclamar';

  @override
  String get weeklyLeagueWeeklyRewardsTitle => 'Recompensas Semanales';

  @override
  String weeklyLeagueTop1Reward(int coins) {
    return 'Top 1: $coins monedas + bono de ascenso';
  }

  @override
  String weeklyLeagueTop3Reward(int coins) {
    return 'Top 2-3: $coins monedas';
  }

  @override
  String weeklyLeagueTop10Reward(int coins) {
    return 'Top 10: $coins monedas';
  }

  @override
  String get weeklyLeagueResetHint =>
      'Al final de la semana, la clasificación se reinicia y las recompensas se pueden reclamar.';

  @override
  String weeklyLeagueLevelStreak(int level, int streak) {
    return 'Nivel $level  •  Racha $streak';
  }

  @override
  String get weeklyLeagueWeeklyLabel => 'Semanal';

  @override
  String weeklyLeagueClaimedRewards(int count, int coins) {
    return '¡Reclamaste $count recompensas: +$coins monedas!';
  }

  @override
  String authGateError(String error) {
    return 'Error: $error';
  }

  @override
  String get achievementsTitle => 'Logros';

  @override
  String achievementsRewardClaimed(int coins) {
    return '🎉 Recompensa reclamada: +$coins monedas';
  }

  @override
  String achievementsErrorLoading(String error) {
    return 'Error cargando logros:\n$error';
  }

  @override
  String get achievementsProgressTitle => 'Progreso de Logros';

  @override
  String achievementsCompletedCount(int completed, int total) {
    return '$completed / $total completados';
  }

  @override
  String get achievementsClaimed => 'Reclamado';

  @override
  String get achievementsClaimReward => 'Reclamar recompensa';

  @override
  String get achievementsInProgress => 'En progreso';

  @override
  String achievementsCoinsPill(int coins) {
    return '+$coins monedas';
  }

  @override
  String get aiTopicsStatusReady => 'Listo';

  @override
  String get aiTopicsStatusFailed => 'Falló';

  @override
  String get aiTopicsStatusDeleted => 'Eliminado';

  @override
  String get aiTopicsStatusInvalid => 'Necesita reparación';

  @override
  String get aiTopicsStatusBlocked => 'Bloqueado';

  @override
  String get aiTopicsStatusPreparing => 'Preparando';

  @override
  String get aiTopicsTitle => 'Temas IA';

  @override
  String get aiTopicsCreateTopic => 'Crear tema';

  @override
  String aiTopicsErrorLoading(String error) {
    return 'Error cargando temas IA:\n$error';
  }

  @override
  String get aiTopicsUntitled => 'Tema sin título';

  @override
  String get aiTopicsDeleteTitle => '¿Eliminar tema?';

  @override
  String aiTopicsDeleteBody(String title) {
    return '¿Quieres quitar \"$title\" de tus temas IA?';
  }

  @override
  String get aiTopicsCancel => 'Cancelar';

  @override
  String get aiTopicsDelete => 'Eliminar';

  @override
  String aiTopicsLevelsQuestions(int levels, int questions) {
    return '$levels niveles • $questions preguntas';
  }

  @override
  String get aiTopicsUnavailableSubtitle =>
      'No se pudo generar este tema. Desliza para eliminarlo y recuperar tu costo.';

  @override
  String get aiTopicsFree => 'Gratis';

  @override
  String aiTopicsCoinsCost(int cost) {
    return '$cost monedas';
  }

  @override
  String aiTopicsRegenerateMenuItem(int cost) {
    return 'Regenerar preguntas — $cost monedas';
  }

  @override
  String aiTopicsExpandMenuItem(int cost) {
    return 'Ampliar tema (+10 niveles) — $cost monedas';
  }

  @override
  String get aiTopicsRegenerateDialogTitle => 'Regenerar preguntas';

  @override
  String aiTopicsRegenerateDialogBody(String title, int cost, int coins) {
    return 'Esto reemplaza las preguntas de \"$title\" por otras nuevas.\n\nCosto: $cost monedas\nTienes: $coins monedas';
  }

  @override
  String get aiTopicsRegenerateSuccess => 'Preguntas regeneradas';

  @override
  String get aiTopicsExpandDialogTitle => 'Ampliar tema';

  @override
  String aiTopicsExpandDialogBody(String title, int cost, int coins) {
    return 'Agrega 10 niveles más a \"$title\".\n\nCosto: $cost monedas\nTienes: $coins monedas';
  }

  @override
  String get aiTopicsExpandSuccess => 'Tema ampliado';

  @override
  String get aiTopicsConfirm => 'Confirmar';

  @override
  String get aiTopicsEmptyTitle => 'Crea tu propio tema de trivia';

  @override
  String get aiTopicsEmptySubtitle =>
      'Elige cualquier tema que te guste. Las preguntas generadas por IA se conectarán en el siguiente paso.';

  @override
  String get aiTopicsEmptyButton => 'Crear Tema IA';

  @override
  String get createAiTopicEnterTopic => 'Ingresa un tema';

  @override
  String get createAiTopicCreated => 'Tema IA creado';

  @override
  String get createAiTopicSubtitle => 'Crea tu propia categoría de trivia';

  @override
  String get createAiTopicExamplesLabel => 'Ejemplos:';

  @override
  String get createAiTopicExamplesList =>
      '• Fórmula 1\n• Harry Potter\n• Películas de Marvel\n• Antiguo Egipto\n• Exploración espacial';

  @override
  String get createAiTopicFieldLabel => 'Tema';

  @override
  String get createAiTopicFieldHint => 'Ejemplo: Fórmula 1';

  @override
  String createAiTopicYouHaveCoins(int coins) {
    return 'Tienes $coins monedas';
  }

  @override
  String get createAiTopicFirstFree => '🎉 Tu primer tema es gratis';

  @override
  String createAiTopicCosts(int cost) {
    return 'Este tema cuesta $cost monedas';
  }

  @override
  String createAiTopicMissingCoins(int amount) {
    return 'Te faltan $amount monedas';
  }

  @override
  String get createAiTopicIncludesHint =>
      'Incluye 10 niveles con 10 preguntas cada uno, preparados de a poco mientras juegas.';

  @override
  String get createAiTopicCreatingButton => 'Creando...';

  @override
  String get coinShopTitle => 'Comprar monedas';

  @override
  String coinShopPurchaseSuccess(int coins) {
    return '+$coins monedas';
  }

  @override
  String get coinShopPurchaseFailed => 'La compra no se completó.';

  @override
  String get coinShopComingSoonTitle => 'Próximamente';

  @override
  String get coinShopComingSoonBody =>
      'La compra de monedas todavía no está disponible en esta versión.';

  @override
  String coinShopCoinsAmount(int coins) {
    return '$coins monedas';
  }

  @override
  String get coinShopBuyButton => 'Comprar';

  @override
  String get notificationsChallengeDeclined => 'Reto rechazado';

  @override
  String get notificationsContinue => 'Continuar';

  @override
  String get notificationsViewResult => 'Ver resultado';

  @override
  String get notificationsReview => 'Revisar';

  @override
  String get notificationsView => 'Ver';

  @override
  String get notificationsOpen => 'Abrir';

  @override
  String get notificationsOpenLobby => 'Abrir sala';

  @override
  String get notificationsTitle => 'Notificaciones';

  @override
  String get notificationsReadAll => 'Marcar todas';

  @override
  String notificationsErrorLoading(String error) {
    return 'Error cargando notificaciones:\n$error';
  }

  @override
  String get notificationsFallbackTitle => 'Notificación';

  @override
  String notificationsChallengerPrefix(String name) {
    return '👤 $name';
  }

  @override
  String notificationsCategoryLine(String category) {
    return '🎯 Categoría: $category';
  }

  @override
  String notificationsQuestionsLine(String count) {
    return '❓ Preguntas: $count';
  }

  @override
  String notificationsTimeLine(String seconds) {
    return '⏱ Tiempo: $seconds seg';
  }

  @override
  String get notificationsEmptyState => 'Aún no tienes notificaciones.';

  @override
  String get friendsOfflineLabel => 'Sin conexión';

  @override
  String get friendsLastSeenJustNow => 'Visto justo ahora';

  @override
  String friendsLastSeenMinutes(int minutes) {
    return 'Visto hace ${minutes}m';
  }

  @override
  String friendsLastSeenHours(int hours) {
    return 'Visto hace ${hours}h';
  }

  @override
  String get friendsEnterUsername => 'Escribe un username para buscar.';

  @override
  String get friendsRequestSent => 'Solicitud enviada';

  @override
  String get friendsActionCompleted => 'Acción completada';

  @override
  String get friendsTitle => 'Amigos';

  @override
  String get friendsSearchTab => 'Buscar';

  @override
  String get friendsFriendsTab => 'Amigos';

  @override
  String get friendsSentTab => 'Enviadas';

  @override
  String get friendsReceivedTab => 'Recibidas';

  @override
  String get friendsUsernameLabel => 'Nombre de usuario';

  @override
  String get friendsNoPlayersFound =>
      'No se encontraron jugadores con ese username.';

  @override
  String friendsErrorLoadingFriends(String error) {
    return 'Error cargando amigos:\n$error';
  }

  @override
  String get friendsLoadingFriends => 'Cargando amigos...';

  @override
  String get friendsNoFriendsYet => 'Todavía no tienes amigos agregados.';

  @override
  String get friendsAsyncOnly => 'Solo asíncrono';

  @override
  String friendsTodayScore(int score) {
    return 'Hoy: $score pts';
  }

  @override
  String get friendsNotPlayedToday => 'Aún no jugó hoy';

  @override
  String friendsErrorLoadingSent(String error) {
    return 'Error cargando solicitudes enviadas:\n$error';
  }

  @override
  String get friendsLoadingSent => 'Cargando solicitudes enviadas...';

  @override
  String get friendsNoSentRequests =>
      'No tienes solicitudes pendientes por responder.';

  @override
  String get friendsPending => 'Pendiente';

  @override
  String get friendsSentStatus => 'Enviado';

  @override
  String friendsErrorLoadingReceived(String error) {
    return 'Error cargando solicitudes:\n$error';
  }

  @override
  String get friendsLoadingReceived => 'Cargando solicitudes...';

  @override
  String get friendsNoReceivedRequests => 'No tienes solicitudes pendientes.';

  @override
  String get friendsWantsToAddYou => 'Quiere agregarte';

  @override
  String get friendsReject => 'Rechazar';

  @override
  String get friendsAccept => 'Aceptar';

  @override
  String get friendsAlreadyFriend => 'Ya es tu amigo';

  @override
  String get friendsWantsToAddYouTile => 'Te quiere agregar';

  @override
  String get friendsPlayerFound => 'Jugador encontrado';

  @override
  String get friendsAddButton => 'Agregar';

  @override
  String get onboardingWelcomeTitle => '¡Bienvenido a TriviaIA!';

  @override
  String get onboardingWelcomeBody =>
      'Responde preguntas de trivia, compite contra otros jugadores y sube de nivel cada día.';

  @override
  String get onboardingLivesTitle => 'Tus vidas';

  @override
  String get onboardingLivesBody =>
      'Tienes 5 vidas. Cada una se recupera sola cada 5 minutos, o puedes comprarla al instante con monedas si no quieres esperar.';

  @override
  String get onboardingCoinsTitle => 'Monedas y racha diaria';

  @override
  String get onboardingCoinsBody =>
      'Gana monedas y XP jugando. Vuelve cada día al Daily Challenge para mantener tu racha y ganar recompensas extra.';

  @override
  String get onboardingSkip => 'Saltar';

  @override
  String get onboardingNext => 'Siguiente';

  @override
  String get onboardingPlayFirstDaily => 'Jugar mi primer Daily Challenge';

  @override
  String get spotlightGotIt => 'Entendido';

  @override
  String get spotlightPvpTitle => 'Duelos 1 vs 1';

  @override
  String get spotlightPvpBody =>
      'Reta a otros jugadores en tiempo real o de forma asíncrona. Ganar sube tu rating y te acerca a la siguiente liga, con más recompensas.';

  @override
  String get spotlightWeeklyTopicTitle => 'Tema de la semana';

  @override
  String get spotlightWeeklyTopicBody =>
      'Cada semana rota una categoría especial. Responde rondas para ganar monedas y un avatar exclusivo antes de que termine la semana.';

  @override
  String get spotlightAchievementsTitle => 'Logros';

  @override
  String get spotlightAchievementsBody =>
      'Cumple objetivos jugando y reclama su recompensa en monedas y XP tocando la tarjeta cuando esté completa.';

  @override
  String get spotlightFramesTitle => 'Marcos de perfil';

  @override
  String get spotlightFramesBody =>
      'Personaliza tu avatar con marcos que desbloqueas al subir de liga en PvP.';

  @override
  String get notificationBellTooltip => 'Notificaciones';

  @override
  String get buyCoinsButtonLabel => 'Comprar monedas';

  @override
  String profileErrorLoadingMatchHistory(String error) {
    return 'Error cargando historial de partidas:\n$error';
  }

  @override
  String get levelPlayPerfect => '¡PERFECTO!';

  @override
  String get serviceEnterUsername => 'Escribe un nombre de usuario.';

  @override
  String get serviceConnectionTimeout =>
      'No se pudo conectar. Revisa tu conexión e inténtalo de nuevo.';

  @override
  String get serviceInvalidUser => 'Usuario inválido.';

  @override
  String get serviceCannotAddSelf => 'No puedes agregarte a ti mismo.';

  @override
  String get serviceUserNotFound => 'El usuario no existe.';

  @override
  String get serviceAlreadyFriends => 'Ya son amigos.';

  @override
  String get serviceRequestAlreadySent => 'Solicitud ya enviada.';

  @override
  String get serviceInvalidRequest => 'Solicitud inválida.';

  @override
  String get serviceCouldNotAcceptRequest => 'No se pudo aceptar la solicitud.';

  @override
  String get serviceInvalidFriend => 'Amigo inválido.';

  @override
  String get serviceCouldNotRemoveFriend => 'No se pudo eliminar al amigo.';

  @override
  String get serviceFriendRequestNotifTitle => 'Nueva solicitud de amistad';

  @override
  String serviceFriendRequestNotifBody(String name) {
    return '$name quiere agregarte como amigo.';
  }

  @override
  String serviceRankedCooldown(String remaining) {
    return 'Tienes cooldown de ranked por abandono. Intenta de nuevo en $remaining.';
  }

  @override
  String get serviceAiTopicEmpty => 'Tema IA no puede estar vacío';

  @override
  String get serviceRoomNotFound => 'Sala no existe';

  @override
  String get serviceRoomAlreadyStartedOrEnded => 'La sala ya inició o terminó';

  @override
  String get serviceRoomFull => 'Sala llena';

  @override
  String get serviceNotInRoom => 'No estás dentro de esta sala';

  @override
  String get serviceMatchNotFound => 'Match no encontrado';

  @override
  String get serviceChallengedUidEmpty => 'challengedUid vacío';

  @override
  String get serviceCannotChallengeSelfNoPeriod =>
      'No puedes retarte a ti mismo';

  @override
  String get serviceChallengeNotFound => 'Reto no encontrado';

  @override
  String get serviceNotYourChallenge => 'No perteneces a este reto';

  @override
  String get serviceAsyncMatchNotFound => 'Async match no existe';

  @override
  String get serviceNotYourMatch => 'No perteneces a este match';

  @override
  String get serviceCodeNotFound => 'Código no encontrado';

  @override
  String servicePoolEmptyForCategory(String categoryId) {
    return 'Pool vacío para $categoryId';
  }

  @override
  String get serviceNoActiveCategories => 'No hay categorías activas';

  @override
  String get serviceRematchRequestedTitle => 'Revancha solicitada';

  @override
  String serviceRematchRequestedBody(String name) {
    return '$name quiere la revancha.';
  }

  @override
  String get serviceNewAsyncChallengeTitle => 'Nuevo reto asíncrono';

  @override
  String serviceNewAsyncChallengeBody(String name) {
    return '$name te retó a una partida 1 vs 1.';
  }

  @override
  String get serviceYourTurnTitle => 'Tu turno';

  @override
  String serviceYourTurnBody(String name) {
    return '$name terminó su partida asíncrona. Ahora es tu turno.';
  }

  @override
  String get serviceCannotChallengeSelfPeriod =>
      'No puedes retarte a ti mismo.';

  @override
  String get serviceInviteNotFound => 'La invitación ya no existe.';

  @override
  String get serviceCannotAcceptInvite => 'No puedes aceptar esta invitación.';

  @override
  String get serviceInviteNoLongerAvailable =>
      'Esta invitación ya no está disponible.';

  @override
  String get serviceNoQuestionsForCategory =>
      'No hay preguntas disponibles para esta categoría.';

  @override
  String get serviceNoActiveCategoriesAvailable =>
      'No hay categorías activas disponibles.';

  @override
  String get serviceRealtimeChallengeTitle => 'Reto en tiempo real';

  @override
  String serviceRealtimeChallengeBody(String name) {
    return '$name te invitó a una partida 1 vs 1 en tiempo real.';
  }

  @override
  String get serviceRealtimeInviteAcceptedTitle =>
      'Invitación en tiempo real aceptada';

  @override
  String serviceRealtimeInviteAcceptedBody(String name) {
    return '$name aceptó tu reto en tiempo real.';
  }

  @override
  String get serviceNoActiveDailyCategories =>
      'No hay categorías activas para Daily Challenge.';

  @override
  String get serviceNoQuestionsInPools =>
      'No hay preguntas disponibles en los pools fijos.';

  @override
  String get achievementFirstPvpWinTitle => 'Primera victoria en duelo';

  @override
  String get achievementFirstPvpWinDescription =>
      'Gana tu primera partida 1 vs 1.';

  @override
  String get achievementPvpWins10Title => 'Duelista';

  @override
  String get achievementPvpWins10Description => 'Gana 10 partidas 1 vs 1.';

  @override
  String get achievementPvpStreak5Title => 'En racha';

  @override
  String get achievementPvpStreak5Description =>
      'Alcanza una racha de 5 victorias en 1 vs 1.';

  @override
  String get achievementSoloLevels10Title => 'Explorador solitario';

  @override
  String get achievementSoloLevels10Description =>
      'Completa 10 niveles en solitario.';

  @override
  String get achievementDailyStreak7Title => 'Hábito semanal';

  @override
  String get achievementDailyStreak7Description =>
      'Alcanza una racha de 7 días en el Daily Challenge.';

  @override
  String get achievementFriends5Title => 'Jugador social';

  @override
  String get achievementFriends5Description => 'Agrega 5 amigos.';

  @override
  String get achievementPvpWins25Title => 'Veterano de duelos';

  @override
  String get achievementPvpWins25Description => 'Gana 25 partidas 1 vs 1.';

  @override
  String get achievementSoloLevels25Title => 'Maestro solitario';

  @override
  String get achievementSoloLevels25Description =>
      'Aprueba 25 niveles del modo Solo.';

  @override
  String get achievementDailyStreak21Title => 'Constancia de hierro';

  @override
  String get achievementDailyStreak21Description =>
      'Alcanza una racha de 21 días en el Desafío Diario.';

  @override
  String get achievementFriends10Title => 'Círculo social';

  @override
  String get achievementFriends10Description => 'Agrega 10 amigos.';

  @override
  String get achievementWeeklyTopics3Title => 'Explorador semanal';

  @override
  String get achievementWeeklyTopics3Description =>
      'Completa 3 Temas Semanales.';

  @override
  String get achievementCategoriesExplored5Title => 'Mente curiosa';

  @override
  String get achievementCategoriesExplored5Description =>
      'Aprueba al menos un nivel en 5 categorías distintas del modo Solo.';

  @override
  String get serviceAchievementCompletedTitle => 'Logro completado';

  @override
  String serviceAchievementCompletedBody(String title) {
    return 'Completaste \"$title\". Reclama tu recompensa.';
  }

  @override
  String get serviceAchievementNotFound => 'Logro no encontrado.';

  @override
  String get serviceCouldNotClaimReward => 'No se pudo reclamar la recompensa.';

  @override
  String get pvpWindowSameLeagueLabel => 'Misma liga';

  @override
  String get pvpWindowSameLeagueDescription =>
      'Buscando primero un rival muy cercano a tu MMR.';

  @override
  String get pvpWindowNearbyLeaguesLabel => 'Ligas cercanas';

  @override
  String get pvpWindowNearbyLeaguesDescription =>
      'Ampliando a jugadores de ligas vecinas.';

  @override
  String get pvpWindowExpandedRangeLabel => 'Rango ampliado';

  @override
  String get pvpWindowExpandedRangeDescription =>
      'Priorizando encontrar partida sin perder competitividad.';

  @override
  String get pvpWindowAnyOpponentLabel => 'Cualquier rival disponible';

  @override
  String get pvpWindowAnyOpponentDescription =>
      'Ahora se prioriza que puedas jugar sin quedarte esperando.';

  @override
  String get weeklyRewardChampionBonus => '¡Bono de campeón!';

  @override
  String get weeklyRewardTop3Bonus => '¡Bono top 3!';

  @override
  String get weeklyRewardTop10Bonus => '¡Bono top 10!';

  @override
  String get weeklyRewardGenericBonus => 'Recompensa de liga semanal';
}
