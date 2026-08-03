// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get langSwitchLabelEn => 'EN';

  @override
  String get langSwitchLabelEs => 'ES';

  @override
  String get navChallengeAcceptedTitle => 'Challenge accepted';

  @override
  String get navChallengeAcceptedBodyFallback => 'Your invite was accepted.';

  @override
  String get navLater => 'Later';

  @override
  String get navPlayNow => 'Play now';

  @override
  String get navNewNotificationTitle => 'New notification';

  @override
  String get navNewNotificationSubtitle => 'Check the bell';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonLoading => 'Loading...';

  @override
  String get commonSaving => 'Saving...';

  @override
  String get homeActionTimeout => 'The action took too long.';

  @override
  String get homeCoins => 'Coins';

  @override
  String get homeXp => 'XP';

  @override
  String get homeFreeTopic => 'Free topic';

  @override
  String get homeAlreadyPlayedDaily =>
      'You already played today\'s Daily Challenge.';

  @override
  String get homeMoreWaysToPlay => 'More ways to play';

  @override
  String get homeWeeklyChallengeReward => 'Weekly Challenge • Reward!';

  @override
  String get homeWeeklyChallenge => 'Weekly Challenge';

  @override
  String homeWeeklyResetsIn(String time) {
    return 'Ends in $time';
  }

  @override
  String get homeTabsHint =>
      'Use the bottom tabs to play SOLO, compete in PvP, challenge friends, and view your profile.';

  @override
  String get homeStreakUpTitle => '🔥 STREAK UP!';

  @override
  String get homeStreakUpSubtitle => 'Keep coming back daily';

  @override
  String get homeWelcomeBackTitle => '📅 Welcome back!';

  @override
  String homeLoginStreakLabel(int days) {
    return 'Login streak: $days days';
  }

  @override
  String get homeAchievementUnlockedTitle => '🏆 Achievement unlocked!';

  @override
  String homeAchievementUnlockedSubtitle(String icon, String title) {
    return '$icon $title';
  }

  @override
  String homeAchievementUnlockedRewards(int coins, int xp) {
    return 'Reward ready: +$coins coins · +$xp XP — claim it in Achievements';
  }

  @override
  String get homeAvatarUnlockedTitle => '🎁 New avatar unlocked!';

  @override
  String homeAvatarUnlockedSubtitle(String emoji, String name) {
    return '$emoji $name';
  }

  @override
  String homeLoginStreakCoins(int coins) {
    return '+$coins coins';
  }

  @override
  String homeLivesSuffix(String lives) {
    return '$lives lives';
  }

  @override
  String get homeLivesFull => 'Lives at max';

  @override
  String get homeAiTopicTitle => 'Free Topic (AI)';

  @override
  String get homeAiTopicSubtitle =>
      'Create your own topic and play with your coins';

  @override
  String homeStatsErrorLoading(String error) {
    return 'Error loading your coins and XP:\n$error';
  }

  @override
  String get homeWeeklyTopicUnavailable => 'Weekly Topic unavailable';

  @override
  String get homeWeeklyTopicNoneAvailable => 'No Weekly Topic available';

  @override
  String get homeWeeklyTopicCheckBack =>
      'Check back soon for a featured challenge.';

  @override
  String get homeWeeklyTopicLoading => 'Loading Weekly Topic...';

  @override
  String get homeOpenWeeklyTopic => 'Open Weekly Topic';

  @override
  String homeWeeklyTopicRewardCoins(int coins) {
    return '+$coins coins';
  }

  @override
  String get homeWeeklyTopicDefaultDescription =>
      'Complete levels and earn rewards.';

  @override
  String get homeDailyChallengeTitle => 'Daily Challenge';

  @override
  String homeDailyChallengeStreak(int days) {
    return 'Streak: $days days';
  }

  @override
  String get homeReward => 'Reward!';

  @override
  String get profileTitle => 'Player Profile';

  @override
  String get profileUsernameHelper => 'Must be unique. Use 3 to 20 characters.';

  @override
  String get profileUsernameLengthError =>
      'The username must be between 3 and 20 characters.';

  @override
  String get profileUsernameCharsError =>
      'Use only letters, numbers, and underscore.';

  @override
  String get profileUsernameTaken => 'That username already exists.';

  @override
  String get usernamePickerTitle => 'Choose your username';

  @override
  String get usernamePickerSubtitle =>
      'Friends will find you by this name. You won\'t be able to change it later.';

  @override
  String get usernamePickerHint => 'Username';

  @override
  String get usernamePickerContinue => 'Continue';

  @override
  String get profileAvatarCollection => 'Avatar Collection';

  @override
  String profileUnlockedCount(int count, int total) {
    return 'Unlocked $count / $total';
  }

  @override
  String get profileCurrentlyEquipped => 'Currently equipped';

  @override
  String get profileChooseFrame => 'Choose Frame';

  @override
  String profileEquippedNotice(String emoji, String name) {
    return '$emoji $name equipped';
  }

  @override
  String profileAvatarUpdateError(String error) {
    return 'Error updating avatar: $error';
  }

  @override
  String profileLevel(int level) {
    return 'Level $level';
  }

  @override
  String profileWeeklyScore(int score) {
    return 'Weekly Score: $score';
  }

  @override
  String profileXpToNextLevel(int current, int required) {
    return '$current / $required XP to next level';
  }

  @override
  String get profileAchievements => 'Achievements';

  @override
  String get profileLegalSectionTitle => 'Legal';

  @override
  String get profilePrivacyPolicy => 'Privacy Policy';

  @override
  String get profileTermsOfService => 'Terms of Service';

  @override
  String get profileLinkOpenFailed => 'Couldn\'t open the link.';

  @override
  String get profileDangerZoneTitle => 'Danger zone';

  @override
  String get profileDeleteAccount => 'Delete account';

  @override
  String get profileDeleteAccountConfirmTitle => 'Delete your account?';

  @override
  String get profileDeleteAccountConfirmBody =>
      'This permanently erases your profile, progress, coins, friends, and created topics. This can\'t be undone.';

  @override
  String get profileDeleteAccountConfirmAction => 'Permanently delete';

  @override
  String get profileAchievementsSubtitle => 'Check your progress and rewards';

  @override
  String get profileCoins => 'Coins';

  @override
  String get profileFreeTopics => 'Free topics';

  @override
  String get profileStreak => 'Streak';

  @override
  String get profileBestStreak => 'Best streak';

  @override
  String get profileStats => 'Stats';

  @override
  String get profileGamesPlayed => 'Games played';

  @override
  String get profileCorrectAnswers => 'Correct answers';

  @override
  String get profileWrongAnswers => 'Wrong answers';

  @override
  String get profileAccuracy => 'Accuracy';

  @override
  String get profileBestDailyScore => 'Best Daily score';

  @override
  String profilePvpLeague(String league) {
    return '$league PvP League';
  }

  @override
  String get profileRankedHint =>
      'Ranked first searches for rivals in your league and widens the range if no players are available.';

  @override
  String get profile1v1Stats => '1 vs 1 Stats';

  @override
  String get profileRankedMmr => 'Ranked MMR';

  @override
  String get profileVictories => 'Victories';

  @override
  String get profileDefeats => 'Defeats';

  @override
  String get profileDraws => 'Draws';

  @override
  String get profileMatchesPlayed => 'Matches played';

  @override
  String get profileWinrate => 'Winrate';

  @override
  String get profileCurrentStreak => 'Current streak';

  @override
  String get profileRecentMatches => 'Recent PvP matches';

  @override
  String get profileNoMatches => 'No PvP matches yet.';

  @override
  String profileVsOpponent(String opponent) {
    return 'vs $opponent';
  }

  @override
  String get profileScore => 'Score';

  @override
  String get profileRanked => 'Ranked';

  @override
  String get profileCasual => 'Casual';

  @override
  String profileErrorLoading(String error) {
    return 'Error loading profile:\n$error';
  }

  @override
  String get matchResultVictory => 'Victory';

  @override
  String get matchResultDefeat => 'Defeat';

  @override
  String get matchResultDraw => 'Draw';

  @override
  String get matchResultMatch => 'Match';

  @override
  String get avatarCategoryBase => 'BASE';

  @override
  String get avatarCategoryPvp => 'PVP';

  @override
  String get avatarCategoryWeekly => 'WEEKLY';

  @override
  String get avatarCategoryAchievement => 'ACHIEVEMENT';

  @override
  String get avatarCategoryAi => 'AI';

  @override
  String get avatarCategoryAiUnique => 'AI UNIQUE';

  @override
  String get avatarNameBrain => 'Brain';

  @override
  String get avatarNameRocket => 'Rocket';

  @override
  String get avatarNameGamer => 'Gamer';

  @override
  String get avatarNameFire => 'Fire';

  @override
  String get avatarNameStar => 'Star';

  @override
  String get avatarNameCat => 'Cat';

  @override
  String get avatarNameRobot => 'Robot';

  @override
  String get avatarNameTrophy => 'Trophy';

  @override
  String get avatarUnlockDefault => 'Default avatar';

  @override
  String get avatarNamePvpBronze => 'Bronze Challenger';

  @override
  String get avatarNamePvpSilver => 'Silver Challenger';

  @override
  String get avatarNamePvpGold => 'Gold Champion';

  @override
  String get avatarNamePvpPlatinum => 'Platinum Elite';

  @override
  String get avatarNamePvpDiamond => 'Diamond Elite';

  @override
  String get avatarNamePvpMaster => 'Master Champion';

  @override
  String get avatarUnlockReachBronze => 'Reach Bronze League';

  @override
  String get avatarUnlockReachSilver => 'Reach Silver League';

  @override
  String get avatarUnlockReachGold => 'Reach Gold League';

  @override
  String get avatarUnlockReachPlatinum => 'Reach Platinum League';

  @override
  String get avatarUnlockReachDiamond => 'Reach Diamond League';

  @override
  String get avatarUnlockReachMaster => 'Reach Master League';

  @override
  String get avatarNameWeeklyCine => 'Cinema Expert';

  @override
  String get avatarNameWeeklyHistory => 'History Scholar';

  @override
  String get avatarNameWeeklyScience => 'Science Mind';

  @override
  String get avatarNameWeeklySports => 'Sports Champion';

  @override
  String get avatarNameWeeklyMusic => 'Music Maestro';

  @override
  String get avatarNameWeeklyArt => 'Art Connoisseur';

  @override
  String get avatarNameWeeklyGeography => 'Globe Trotter';

  @override
  String get avatarNameWeeklyVideogames => 'Game Master';

  @override
  String get avatarNameWeeklyBooks => 'Bookworm';

  @override
  String get avatarUnlockWeeklyCine => 'Complete a Cinema Weekly Topic';

  @override
  String get avatarUnlockWeeklyHistory => 'Complete a History Weekly Topic';

  @override
  String get avatarUnlockWeeklyScience => 'Complete a Science Weekly Topic';

  @override
  String get avatarUnlockWeeklySports => 'Complete a Sports Weekly Topic';

  @override
  String get avatarUnlockWeeklyMusic => 'Complete a Music Weekly Topic';

  @override
  String get avatarUnlockWeeklyArt => 'Complete an Art Weekly Topic';

  @override
  String get avatarUnlockWeeklyGeography => 'Complete a Geography Weekly Topic';

  @override
  String get avatarUnlockWeeklyVideogames => 'Complete a Gaming Weekly Topic';

  @override
  String get avatarUnlockWeeklyBooks => 'Complete a Books Weekly Topic';

  @override
  String get avatarName100Questions => '100 Answers';

  @override
  String get avatarUnlock100Questions => 'Answer 100 questions';

  @override
  String get avatarName1000Questions => 'Trivia Legend';

  @override
  String get avatarUnlock1000Questions => 'Answer 1000 questions';

  @override
  String get avatarNameAiTopicMaster => 'AI Topic Master';

  @override
  String get avatarUnlockAiTopicMaster => 'Complete an AI-generated topic';

  @override
  String get frameNameBronze => 'Bronze Frame';

  @override
  String get frameNameSilver => 'Silver Frame';

  @override
  String get frameNameGold => 'Gold Frame';

  @override
  String get frameNamePlatinum => 'Platinum Frame';

  @override
  String get frameNameDiamond => 'Diamond Frame';

  @override
  String get frameNameMaster => 'Master Frame';

  @override
  String get livesNoLivesTitle => 'Not enough lives';

  @override
  String get livesNoLivesMessage =>
      'You need at least 1 full life to enter a level.';

  @override
  String get livesYourLives => 'Your lives';

  @override
  String get livesNextHalf => 'Next half life';

  @override
  String get livesNextFull => 'For 1 full life';

  @override
  String get livesGoBack => 'Back';

  @override
  String get livesWait => 'Wait';

  @override
  String livesRecoverButton(int cost) {
    return 'Recover 1 life ($cost coins)';
  }

  @override
  String get soloTabTitle => 'Solo';

  @override
  String soloErrorLoadingCategories(String error) {
    return 'Error loading categories:\n$error';
  }

  @override
  String get soloNoCategoriesAvailable => 'No active categories in Firestore.';

  @override
  String get soloFixedTopics => 'Fixed Topics';

  @override
  String get soloAllCompletedTitle => 'You completed all of Solo mode!';

  @override
  String get soloAllCompletedBody =>
      'Keep earning coins and XP in the Daily Challenge or by challenging other players in PvP.';

  @override
  String get soloAllCompletedDailyButton => 'Go to Daily Challenge';

  @override
  String get soloAllCompletedPvpButton => 'Go to PvP';

  @override
  String get soloLifeRecovered => '❤️ Life recovered';

  @override
  String get soloNotEnoughCoins => '❌ Not enough coins';

  @override
  String soloProgressLevels(int completed, int total) {
    return 'Progress: $completed / $total levels';
  }

  @override
  String get soloViewLevels => 'View levels';

  @override
  String get soloStatusCompleted => 'Completed';

  @override
  String get soloStatusInProgress => 'In progress';

  @override
  String get soloStatusNew => 'New';

  @override
  String soloContinueLevel(int level) {
    return 'Continue L$level';
  }

  @override
  String get levelSelectNoLevelsYet =>
      'This category doesn\'t have levels available yet.';

  @override
  String get levelSelectChooseLevel => 'Choose a level';

  @override
  String get levelSelectAiTopicApproved => 'AI topic passed';

  @override
  String get levelSelectCategoryApproved => 'Category passed';

  @override
  String get levelSelectAiTopicProgressApproved =>
      'Your progress passed in this AI topic';

  @override
  String get levelSelectCategoryProgressApproved =>
      'Your progress passed in this category';

  @override
  String levelSelectApprovedCount(int completed, int total) {
    return 'Passed: $completed / $total';
  }

  @override
  String get levelSelectPlayLastLevel => 'Play last level';

  @override
  String levelSelectContinueAtLevel(int level) {
    return 'Continue at level $level';
  }

  @override
  String get levelSelectAvailable => 'Available';

  @override
  String get levelSelectLocked => 'Locked';

  @override
  String levelSelectLevelNumber(int level) {
    return 'Level $level';
  }

  @override
  String get levelSelectNextBadge => 'Next';

  @override
  String get levelSelectLoadFailedTitle => 'Couldn\'t load the category.';

  @override
  String get levelPlayAiTopicLabel => 'AI Topic';

  @override
  String levelPlayAppBarTitle(String name, int level) {
    return '$name - Level $level';
  }

  @override
  String get levelPlayTimeUp => '⏰ Time\'s up';

  @override
  String get levelPlayTimeUpNoLives => '⏰ Time\'s up - you ran out of lives';

  @override
  String get levelPlayTimeUpLostHalfLife =>
      '⏰ Time\'s up - you lost half a life';

  @override
  String get levelPlayTimeUpNoLifeLoss =>
      '⏰ Time\'s up - you didn\'t lose any life';

  @override
  String get levelPlayWrongNoLives => '❌ Wrong - you ran out of lives';

  @override
  String get levelPlayWrongLostHalfLife => '❌ Wrong - you lost half a life';

  @override
  String get levelPlayWrongNoLifeLoss => '❌ Wrong - you didn\'t lose any life';

  @override
  String get aiReportQuestionTooltip => 'Report this question';

  @override
  String get aiReportDialogTitle => 'What\'s wrong with this question?';

  @override
  String get aiReportDialogDetailsHint => 'Additional details (optional)';

  @override
  String get aiReportDialogCancel => 'Cancel';

  @override
  String get aiReportDialogSubmit => 'Send report';

  @override
  String get aiReportReasonWrongAnswer => 'The marked answer is wrong';

  @override
  String get aiReportReasonConfusing => 'Confusing or ambiguous question';

  @override
  String get aiReportReasonInappropriate => 'Inappropriate content';

  @override
  String get aiReportReasonOther => 'Other reason';

  @override
  String get aiReportSent => 'Thanks, we reported the question.';

  @override
  String get levelPlayNeedFullLife =>
      'You need 1 full life to enter this level.';

  @override
  String levelPlayLifeCheckError(String error) {
    return 'Error checking lives: $error';
  }

  @override
  String get levelPlaySessionCreateErrorTitle => 'Error creating session';

  @override
  String get levelPlayGeneratingQuestions => 'Generating level questions...';

  @override
  String get levelPlaySessionNotFound => 'Session not found.';

  @override
  String get levelPlaySessionNoQuestions => 'This session has no questions.';

  @override
  String get levelPlayLivesMax => 'MAX';

  @override
  String get levelPlayOutOfLivesTitle => 'You ran out of lives';

  @override
  String get levelPlayOutOfLivesMessage =>
      'You can\'t continue this level until you recover lives.';

  @override
  String levelPlayLivesHeader(String lives) {
    return 'Lives: $lives';
  }

  @override
  String levelPlayHalfLifeIn(String time) {
    return '+0.5 in $time';
  }

  @override
  String levelPlayQuestionOfTotal(int current, int total) {
    return 'Question $current of $total';
  }

  @override
  String get levelPlayRankExpert => 'Expert';

  @override
  String get levelPlayRankAdvanced => 'Advanced';

  @override
  String get levelPlayRankIntermediate => 'Intermediate';

  @override
  String get levelPlayRankBeginner => 'Beginner';

  @override
  String get levelPlayLevelPassed => 'Level passed!';

  @override
  String get levelPlayLevelFinished => 'Level finished';

  @override
  String levelPlayScoreLine(int correct, int total, String pct) {
    return 'Score: $correct / $total ($pct)';
  }

  @override
  String levelPlayRankLine(String rank) {
    return 'Rank: $rank';
  }

  @override
  String get levelPlayRewardsTitle => 'Rewards';

  @override
  String get levelPlayAlreadyPassedBefore =>
      'This level had already been passed before.';

  @override
  String get levelPlayNeed40Percent =>
      'You need at least 40% correct to pass this level.';

  @override
  String get levelPlaySavingProgress => 'Saving progress...';

  @override
  String levelPlaySaveError(String error) {
    return 'Error saving: $error';
  }

  @override
  String get levelPlayRetrySave => 'Retry save';

  @override
  String get levelPlayProgressSaved => '✅ Progress saved';

  @override
  String levelPlayContinueNextLevel(int level) {
    return 'Continue (Level $level)';
  }

  @override
  String get levelPlayWeeklyCounted =>
      'Counts for the weekly event. This level advanced your weekly rewards progress.';

  @override
  String get levelPlayWeeklyNotCounted =>
      'Doesn\'t count for the weekly event. You need at least 40% correct for this level to advance your weekly rewards.';

  @override
  String levelPlayPlayerLevel(int level) {
    return 'Player level $level';
  }

  @override
  String levelPlayTotalXp(int xp) {
    return 'Total XP: $xp';
  }

  @override
  String levelPlayLevelUp(int level) {
    return 'LEVEL UP! $level';
  }

  @override
  String levelPlayLeveledUpTo(int level) {
    return 'You leveled up to $level!';
  }

  @override
  String levelPlayXpInLevel(int current, int total) {
    return '$current / $total XP in this level';
  }

  @override
  String get pvpHubTitle => 'PvP';

  @override
  String get pvpHubHeading => 'Competitive hub';

  @override
  String get pvpHubSubheading => 'Choose how you want to compete.';

  @override
  String get pvpActiveMatchesTitle => 'Active Matches';

  @override
  String get pvpActiveMatchesTitleAlert => 'Active Matches • Your Turn!';

  @override
  String get pvpActiveMatchesSubtitle =>
      'Pending turns, live games, and recent results.';

  @override
  String get pvpActiveMatchesSubtitleAlert =>
      'You have pending matches waiting for your move.';

  @override
  String get pvpRealtimeInvitesTitle => 'Realtime Invites';

  @override
  String get pvpRealtimeInvitesTitleAlert => 'Realtime Invites • New!';

  @override
  String get pvpRealtimeInvitesSubtitle =>
      'Accept or decline live challenges. To challenge a friend, go to the Friends tab.';

  @override
  String get pvpRealtimeInvitesSubtitleAlert =>
      'You have live challenges waiting.';

  @override
  String get pvpFindOpponentTitle => 'Find Opponent';

  @override
  String get pvpFindOpponentSubtitle =>
      'Play against any available challenger.';

  @override
  String get pvpSeasonTitle => 'PvP Season';

  @override
  String get pvpSeasonSubtitle =>
      'View your ranked league, season progress, leaderboard and rewards.';

  @override
  String get activeMatchesTitle => 'Active Matches';

  @override
  String get activeMatchesReconnecting => 'Reconnecting...';

  @override
  String get activeMatchesYourTurn => 'Your Turn';

  @override
  String get activeMatchesLoadingYourMatches => 'Loading your matches...';

  @override
  String get activeMatchesNoneWaitingForYou =>
      'No async matches waiting for you.';

  @override
  String get activeMatchesWaitingForOpponent => 'Waiting For Opponent';

  @override
  String get activeMatchesLoadingMatches => 'Loading matches...';

  @override
  String get activeMatchesNoneWaitingForOpponent =>
      'No matches waiting for your opponent.';

  @override
  String get activeMatchesRecentlyFinished => 'Recently Finished';

  @override
  String get activeMatchesLoadingResults => 'Loading results...';

  @override
  String get activeMatchesNoneFinished => 'No recent finished matches.';

  @override
  String activeMatchesYourTurnSubtitle(String category) {
    return 'Your turn • $category';
  }

  @override
  String activeMatchesWaitingSubtitle(int score) {
    return 'Waiting • Your score: $score';
  }

  @override
  String activeMatchesDrawSubtitle(int a, int b) {
    return 'Draw • $a-$b';
  }

  @override
  String activeMatchesVictorySubtitle(int a, int b) {
    return 'Victory • $a-$b';
  }

  @override
  String activeMatchesDefeatSubtitle(int a, int b) {
    return 'Defeat • $a-$b';
  }

  @override
  String get activeMatchesPlay => 'Play';

  @override
  String get activeMatchesView => 'View';

  @override
  String get activeMatchesResult => 'Result';

  @override
  String get findOpponentTitle => 'Find Opponent';

  @override
  String get findOpponentLiveTab => 'Live';

  @override
  String get findOpponentAsyncTab => 'Async';

  @override
  String liveMenuLeagueTitle(String name) {
    return '$name League';
  }

  @override
  String get liveMenuMmrHint1 =>
      'Finding an opponent affects your MMR and PvP league.';

  @override
  String get liveMenuFixedTopicLabel => 'Fixed topic';

  @override
  String get liveMenuPublicMatchmaking => 'Public matchmaking';

  @override
  String get liveMenuMmrHint2 =>
      'Finding an opponent affects your MMR, league, and PvP stats.';

  @override
  String get liveMenuPrivateMatches => 'Private matches';

  @override
  String get liveMenuCreatePrivateRoom => 'Create private room';

  @override
  String get liveMenuJoinWithCode => 'Join with code';

  @override
  String get liveMenuPrivateMatchesHint =>
      'Private matches are friendly and don\'t affect your ranking.';

  @override
  String get asyncMenuSelectTopicFirst => 'Select a fixed topic first.';

  @override
  String get asyncMenuConfigTitle => 'Configuration';

  @override
  String get asyncMenuFixedTopicsLabel => 'Fixed topics';

  @override
  String get asyncMenuNoActiveCategories => 'No active categories.';

  @override
  String get asyncMenuSelectTopicLabel => 'Select a fixed topic';

  @override
  String get asyncMenuFindPlayerButton => 'Find a player to challenge';

  @override
  String get asyncMenuTip =>
      'Tip: You challenge someone, play immediately, and your opponent can play later. Check Active Matches to see your pending challenges.';

  @override
  String get createMatchTitle => 'Create Room (Live)';

  @override
  String get createMatchYourName => 'Your name (displayName)';

  @override
  String get createMatchCategory => 'Category';

  @override
  String get createMatchDifficulty => 'Difficulty';

  @override
  String get createMatchDiffEasy => '1 (Easy)';

  @override
  String get createMatchDiffMedium => '2 (Medium)';

  @override
  String get createMatchDiffHard => '3 (Hard)';

  @override
  String get createMatchTimePerQuestion => 'Time/Question';

  @override
  String get createMatchQuestions => 'Questions';

  @override
  String get createMatchAutoSearch => 'Find player automatically';

  @override
  String get createMatchCreateRoom => 'Create Room';

  @override
  String get joinMatchTitle => 'Join';

  @override
  String get joinMatchCodeLabel => 'Room code (e.g: A7KQ2)';

  @override
  String get liveMatchmakingRankedTitle => 'Ranked Matchmaking';

  @override
  String get liveMatchmakingCasualTitle => 'Casual Matchmaking';

  @override
  String liveMatchmakingTypeLine(String type) {
    return 'Type: $type';
  }

  @override
  String liveMatchmakingCategoryLine(String category) {
    return 'Category: $category';
  }

  @override
  String liveMatchmakingDifficultyLine(int difficulty) {
    return 'Difficulty: $difficulty';
  }

  @override
  String liveMatchmakingQuestionsLine(int total) {
    return 'Questions: $total';
  }

  @override
  String liveMatchmakingTimePerQuestionLine(int seconds) {
    return 'Time/Question: ${seconds}s';
  }

  @override
  String get liveMatchmakingNoOpponentFound =>
      'No opponent found right now. Try again.';

  @override
  String get liveMatchmakingTryAsyncInstead => 'Play async instead';

  @override
  String get liveMatchmakingSearchButton => 'Search';

  @override
  String get liveMatchmakingSearching => 'Searching...';

  @override
  String get liveMatchmakingSearchingOpponent => 'Searching for opponent...';

  @override
  String liveMatchmakingQueueStatus(String status) {
    return 'Queue status: $status';
  }

  @override
  String get liveMatchmakingRankedHint =>
      'First searches for rivals close to your MMR; if it takes too long, it widens the range automatically.';

  @override
  String get liveMatchmakingCasualHint =>
      'Casual doesn\'t affect your MMR. Finding an opponent fast is prioritized.';

  @override
  String get liveMatchmakingCancelSearch => 'Cancel search';

  @override
  String get asyncFindPlayersCannotChallengeSelf =>
      'You can\'t challenge yourself.';

  @override
  String get asyncFindPlayersTitle => 'Find player (async)';

  @override
  String get asyncFindPlayersSearchLabel => 'Search by name';

  @override
  String get asyncFindPlayersSearchPrompt =>
      'Type a username to search for players.';

  @override
  String get asyncFindPlayersNoneToShow => 'No players to show.';

  @override
  String get asyncFindPlayersChallengeButton => 'Challenge';

  @override
  String get realtimeInvitesDeclined => 'Invite declined';

  @override
  String realtimeInvitesErrorLoading(String error) {
    return 'Error loading invites:\n$error';
  }

  @override
  String realtimeInvitesInvitedYou(String name) {
    return '$name invited you';
  }

  @override
  String realtimeInvitesSubtitle(String category) {
    return 'Realtime 1 vs 1 • Category: $category';
  }

  @override
  String get realtimeInvitesDecline => 'Decline';

  @override
  String get realtimeInvitesAccept => 'Accept';

  @override
  String get realtimeInvitesEmpty => 'No realtime invites right now.';

  @override
  String get realtimeInvitesReceivedTab => 'Received';

  @override
  String get realtimeInvitesSentTab => 'Sent';

  @override
  String realtimeInvitesSentTo(String name) {
    return 'You invited $name';
  }

  @override
  String get realtimeInvitesWaitingResponse => 'Waiting for response...';

  @override
  String get realtimeInvitesCancel => 'Cancel';

  @override
  String get realtimeInvitesCancelled => 'Invite cancelled';

  @override
  String get realtimeInvitesSentEmpty =>
      'You haven\'t sent any invites right now.';

  @override
  String get friendChallengeNotOnline =>
      'Your friend isn\'t connected to play in real time.';

  @override
  String friendChallengeRealtimeSent(String name) {
    return 'Realtime challenge sent to $name';
  }

  @override
  String get friendChallengeOnline => 'Online';

  @override
  String get friendChallengeOffline => 'Offline';

  @override
  String get friendChallengeSendRealtime => 'Send realtime challenge';

  @override
  String get friendChallengeCreateAsync => 'Create async challenge';

  @override
  String get friendChallengeTitle => 'Set up challenge';

  @override
  String get friendChallengeTypeLabel => 'Challenge type';

  @override
  String get friendChallengeNeedOnlineHint =>
      'Your friend must be online to play in real time.';

  @override
  String get friendChallengeMatchConfig => 'Match settings';

  @override
  String get friendChallengeCategoryRandom => 'Random';

  @override
  String get friendChallengeDiffEasy => 'Easy';

  @override
  String get friendChallengeDiffMedium => 'Medium';

  @override
  String get friendChallengeDiffHard => 'Hard';

  @override
  String get friendChallengeQuestionCountLabel => 'Number of questions';

  @override
  String friendChallengeQuestionsCount(int count) {
    return '$count questions';
  }

  @override
  String get friendChallengeTimePerQuestionLabel => 'Time per question';

  @override
  String friendChallengeSeconds(int seconds) {
    return '$seconds seconds';
  }

  @override
  String get friendChallengeRealtimeHint =>
      'Realtime requires both players online. Matches with friends are casual and don\'t affect MMR.';

  @override
  String get friendChallengeAsyncHint =>
      'Async lets your friend play whenever they can. Doesn\'t affect MMR.';

  @override
  String get matchLobbyWaitingFriendJoin =>
      'Waiting for your friend to join the room.';

  @override
  String get matchLobbyAllReadyStarting => 'All set. The match is starting...';

  @override
  String get matchLobbyReadyWaitingOpponent =>
      'Ready. Waiting for your opponent to confirm.';

  @override
  String get matchLobbyOpponentReadyConfirm =>
      'Your opponent is already ready. Confirm to start.';

  @override
  String get matchLobbyWaitingBothReady =>
      'Waiting for both players to be ready.';

  @override
  String get matchLobbyTitle => '1 vs 1 Room';

  @override
  String get matchLobbyNotFound => 'Room not found';

  @override
  String get matchLobbyNoLongerAvailable => 'The room is no longer available.';

  @override
  String get matchLobbyHeading => '1 vs 1 Match';

  @override
  String get matchLobbyTopicLabel => 'Topic';

  @override
  String get matchLobbyModeLabel => 'Mode';

  @override
  String get matchLobbyModeFixed => 'No AI';

  @override
  String get matchLobbyModeAi => 'With AI';

  @override
  String get matchLobbyTimeLabel => 'Time';

  @override
  String matchLobbySecondsPerQuestion(int seconds) {
    return '${seconds}s per question';
  }

  @override
  String get matchLobbyCodeCopied => 'Code copied';

  @override
  String get matchLobbyWaitingOpponentButton => 'Waiting for opponent';

  @override
  String get matchLobbyWaitingOpponentEllipsis => 'Waiting for opponent...';

  @override
  String get matchLobbyImReady => 'I\'m ready';

  @override
  String get matchLobbyCancelReady => 'Cancel ready';

  @override
  String matchLobbyRoomStatus(String status) {
    return 'Room status: $status';
  }

  @override
  String get matchLobbyPlayer1 => 'Player 1';

  @override
  String get matchLobbyPlayer2 => 'Player 2';

  @override
  String get matchLobbyReadyLabel => 'Ready';

  @override
  String get matchLobbyWaitingLabel => 'Waiting...';

  @override
  String get matchLobbyRoomCodeLabel => 'Room code';

  @override
  String get matchLobbyCopyCodeButton => 'Copy code';

  @override
  String get pvpResultPerfectDraw => 'Perfect draw';

  @override
  String pvpResultWonByPoints(int diff) {
    return 'You won by +$diff points';
  }

  @override
  String pvpResultLostByPoints(int diff) {
    return 'You lost by $diff points';
  }

  @override
  String get pvpResultFinalResult => 'Final result';

  @override
  String get pvpResultVs => 'VS';

  @override
  String get pvpResultMatchSummary => 'Match summary';

  @override
  String get pvpResultYourScore => 'Your score';

  @override
  String get pvpResultOpponent => 'Opponent';

  @override
  String get pvpResultPerformance => 'Performance';

  @override
  String get pvpResultBefore => 'Before';

  @override
  String get pvpResultNow => 'Now';

  @override
  String pvpResultCurrentStreak(int count) {
    return '🔥 Current streak: $count wins';
  }

  @override
  String get matchPlayRematchRequestTitle => 'Rematch request';

  @override
  String matchPlayRematchRequestBody(String name) {
    return '$name wants to play a rematch.';
  }

  @override
  String get matchPlayTitle => '1 vs 1';

  @override
  String get matchPlayNotFound => 'Match not found';

  @override
  String get matchPlayWaitingToStart => 'Waiting for it to start...';

  @override
  String get matchPlayNoQuestions => 'This match has no questions.';

  @override
  String get matchPlayYourScoreLabel => 'Your score';

  @override
  String get matchPlayWaitingFinalResult => 'Waiting for final result...';

  @override
  String get matchPlayOpponentStillAnswering =>
      'Your opponent is still answering questions.';

  @override
  String matchPlayYourScoreLine(int score) {
    return 'Your score: $score';
  }

  @override
  String get matchPlayDrawTitle => 'Draw';

  @override
  String get matchPlayDrawSubtitle => 'Both finished with the same score.';

  @override
  String get matchPlayVictoryTitle => 'You won!';

  @override
  String get matchPlayVictoryRankedSubtitle =>
      'Good match. Your competitive rating was updated.';

  @override
  String get matchPlayVictoryCasualSubtitle =>
      'Good match. You earned a 1 vs 1 win.';

  @override
  String get matchPlayDefeatTitle => 'You lost';

  @override
  String get matchPlayDefeatRankedSubtitle =>
      'So close. Your competitive rating was updated.';

  @override
  String get matchPlayDefeatCasualSubtitle => 'So close. Try a rematch.';

  @override
  String get matchPlayRematch => 'Rematch';

  @override
  String get matchPlaySendingRequest => 'Sending request...';

  @override
  String get matchPlayRequestSent => 'Request sent ✓';

  @override
  String get matchPlayCreatingRematch => 'Creating rematch...';

  @override
  String get matchPlayExit => 'Exit';

  @override
  String get asyncMatchPlayTitle => 'Async Challenge';

  @override
  String get asyncMatchPlayNotFound => 'Challenge not found';

  @override
  String get asyncMatchPlayNoQuestions => 'This challenge has no questions.';

  @override
  String get asyncMatchPlayYouFallback => 'You';

  @override
  String get asyncMatchPlayOpponentFallback => 'Opponent';

  @override
  String get asyncMatchPlayCorrectLabel => 'Correct';

  @override
  String get asyncMatchPlayChallengeCompletedTitle => 'Challenge completed';

  @override
  String get asyncMatchPlaySendingResultSubtitle =>
      'Sending your result. Then we\'ll wait for your opponent.';

  @override
  String get asyncMatchPlayAlreadyPlayedTitle =>
      'You already played this challenge';

  @override
  String get asyncMatchPlayCalculatingFinal =>
      'Your result was sent. Calculating final result.';

  @override
  String get asyncMatchPlayWaitingOpponentPlay =>
      'Your result was sent. Waiting for your opponent to play.';

  @override
  String get asyncMatchPlaySendingRematch => 'Sending rematch...';

  @override
  String get pvpSeasonTabSeason => 'Season';

  @override
  String get pvpSeasonTabLeaderboard => 'Leaderboard';

  @override
  String get pvpSeasonTabRewards => 'Rewards';

  @override
  String pvpSeasonLabel(String id) {
    return 'Season: $id';
  }

  @override
  String pvpSeasonEndsIn(String time) {
    return 'Ends in: $time';
  }

  @override
  String pvpSeasonProjectedReward(int coins) {
    return 'Projected reward: +$coins coins';
  }

  @override
  String get pvpSeasonRankedHint =>
      'Ranked uses flexible matchmaking: first it looks near your league, then expands the range so players are not left waiting.';

  @override
  String get pvpSeasonHowItWorksTitle => 'How PvP Seasons work';

  @override
  String get pvpSeasonHowItWorksBullet1 =>
      '• Play Ranked Matches to increase your MMR.';

  @override
  String get pvpSeasonHowItWorksBullet2 =>
      '• Your league is calculated from your current MMR.';

  @override
  String get pvpSeasonHowItWorksBullet3 =>
      '• Leaderboards rank players by MMR.';

  @override
  String get pvpSeasonHowItWorksBullet4 =>
      '• Rewards are based on your final league when the season ends.';

  @override
  String get pvpSeasonFriendsTab => 'Friends';

  @override
  String get pvpSeasonGlobalTab => 'Global';

  @override
  String get pvpSeasonAllTab => 'All';

  @override
  String pvpSeasonErrorLoadingFriends(String error) {
    return 'Error loading friends leaderboard:\n$error';
  }

  @override
  String get pvpSeasonNoFriendsTitle => 'No friends in leaderboard yet';

  @override
  String get pvpSeasonNoFriendsEmptyHint =>
      'Play Ranked Matches and add friends to compare your PvP rating.';

  @override
  String get pvpSeasonNoFriendsHint =>
      'Add friends to compare your PvP rating with people you know.';

  @override
  String pvpSeasonYouSuffix(String name) {
    return '$name (You)';
  }

  @override
  String pvpSeasonMatchesCount(int count) {
    return '$count matches';
  }

  @override
  String pvpSeasonWinLossDraw(int wins, int losses, int draws) {
    return '$wins W / $losses L / $draws D';
  }

  @override
  String pvpSeasonErrorLoadingLeaderboard(String error) {
    return 'Error loading leaderboard:\n$error';
  }

  @override
  String get pvpSeasonNoRankedPlayers =>
      'No ranked players yet.\nPlay Ranked Match to enter this leaderboard.';

  @override
  String get pvpSeasonRewardsTitle => 'Season Rewards';

  @override
  String get pvpSeasonRewardsSubtitle =>
      'Rewards are based on your best PvP league from each finished season.';

  @override
  String get pvpSeasonCurrentProjectedReward => 'Current projected reward';

  @override
  String pvpSeasonEndsInLine(String time) {
    return 'Season ends in $time';
  }

  @override
  String get pvpSeasonCheckingRewards =>
      'Checking pending PvP season rewards...';

  @override
  String get pvpSeasonCouldNotLoad => 'Could not load rewards';

  @override
  String get pvpSeasonNoRewardYetTitle => 'No reward available yet';

  @override
  String get pvpSeasonNoRewardYetHint =>
      'Play Ranked Matches this season. When the season ends, your PvP reward will appear here.';

  @override
  String pvpSeasonPendingSingle(int count) {
    return '$count pending season reward';
  }

  @override
  String pvpSeasonPendingMultiple(int count) {
    return '$count pending season rewards';
  }

  @override
  String pvpSeasonMorePending(int count) {
    return '+$count more pending season(s)';
  }

  @override
  String get pvpSeasonClaiming => 'Claiming...';

  @override
  String get pvpSeasonClaimAllButton => 'Claim All Rewards';

  @override
  String get pvpSeasonNoPendingRewards =>
      'No pending PvP season rewards available.';

  @override
  String pvpSeasonClaimedRewards(int count, int coins) {
    return 'Claimed $count PvP season reward(s): +$coins coins!';
  }

  @override
  String get dailyResultTitle => 'Daily Challenge Result';

  @override
  String get dailyResultComplete => 'Daily Challenge Complete!';

  @override
  String get dailyResultCorrectAnswers => 'Correct answers';

  @override
  String get dailyResultTotalAnswered => 'Total answered';

  @override
  String get dailyResultCoinsEarned => 'Coins earned';

  @override
  String get dailyResultStreakLabel => 'Daily streak';

  @override
  String dailyResultDaysValue(int days) {
    return '$days days';
  }

  @override
  String get dailyResultStreakBonus => 'Streak bonus';

  @override
  String get dailyResultAlreadyPlayed =>
      'You already played today. Coins were not awarded again.';

  @override
  String get dailyResultBackHome => 'Back to Home';

  @override
  String dailyResultNextChallengeIn(String time) {
    return 'Next challenge in $time';
  }

  @override
  String get dailyResultViewLeaderboard => 'View today\'s ranking';

  @override
  String get weeklyRewardsTitle => 'Weekly Rewards';

  @override
  String get weeklyRewardsNoPending => 'No pending weekly rewards.';

  @override
  String weeklyRewardsClaimed(int count, int coins) {
    return 'Claimed $count reward(s): +$coins coins!';
  }

  @override
  String get weeklyRewardsChecking => 'Checking pending weekly rewards...';

  @override
  String get weeklyRewardsNoPendingTitle => 'No pending weekly rewards';

  @override
  String get weeklyRewardsKeepPlayingHint =>
      'Keep playing Weekly Challenge to earn weekly rewards.';

  @override
  String weeklyRewardsPendingSingle(int count) {
    return '$count pending reward';
  }

  @override
  String weeklyRewardsPendingMultiple(int count) {
    return '$count pending rewards';
  }

  @override
  String weeklyRewardsTotalAvailable(int coins) {
    return 'Total available: +$coins coins';
  }

  @override
  String weeklyRewardsMiniTile(
      String seasonId, String leagueName, int rank, String message) {
    return '$seasonId • $leagueName • Rank #$rank • $message';
  }

  @override
  String get weeklyRewardsHistoryTitle => 'Weekly Rewards History';

  @override
  String get weeklyRewardsNoHistory => 'No season rewards claimed yet.';

  @override
  String weeklyRewardsHistoryTitleLine(String seasonId, String leagueName) {
    return '$seasonId • $leagueName';
  }

  @override
  String weeklyRewardsHistorySubtitle(int rank, int score, String message) {
    return 'Rank #$rank • Score $score • $message';
  }

  @override
  String get weeklyRewardsLeagueFallback => 'League';

  @override
  String get weeklyRewardsMessageFallback => 'Weekly reward claimed';

  @override
  String weeklyRewardsErrorLoadingHistory(String error) {
    return 'Error loading history:\n$error';
  }

  @override
  String get dailyLeaderboardTitle => 'Daily Leaderboard';

  @override
  String dailyLeaderboardErrorLoading(String error) {
    return 'Error loading leaderboard:\n$error';
  }

  @override
  String get dailyLeaderboardNoData => 'No leaderboard data available.';

  @override
  String get dailyLeaderboardNoScoresYet =>
      'No scores yet today.\nPlay the Daily Challenge first!';

  @override
  String get dailyLeaderboardRankingTitle => 'Ranking';

  @override
  String dailyLeaderboardPtsSuffix(int score) {
    return '$score pts';
  }

  @override
  String dailyLeaderboardNameWithYou(String name) {
    return '$name  (You)';
  }

  @override
  String dailyLeaderboardCorrectStreakLine(int correct, int total, int streak) {
    return 'Correct: $correct / $total  •  Streak: $streak';
  }

  @override
  String get dailyLeaderboardScoreLabel => 'Score';

  @override
  String get dailyChallengeCoinsPopup => '+5 Coins 🎉';

  @override
  String dailyChallengeErrorSaving(String error) {
    return 'Error saving results: $error';
  }

  @override
  String get dailyChallengeNoQuestions => 'No questions available';

  @override
  String get dailyChallengeTimeLabel => 'Time';

  @override
  String dailyChallengeDifficultyLine(String level) {
    return 'Difficulty: $level';
  }

  @override
  String dailyChallengeAnsweredCount(int count) {
    return 'Answered: $count';
  }

  @override
  String get dailyChallengeCompletedTitle => 'Daily completed!';

  @override
  String get dailyChallengeSavingResults => 'Saving your results...';

  @override
  String get weeklyTopicScreenTitle => 'Weekly Topic';

  @override
  String weeklyTopicCoinsClaimed(int coins) {
    return '+$coins coins claimed!';
  }

  @override
  String get weeklyTopicRewardUnavailable =>
      'Reward already claimed or not available yet.';

  @override
  String get weeklyTopicNoExclusiveReward =>
      'No exclusive reward configured for this week.';

  @override
  String weeklyTopicAvatarUnlocked(String emoji, String name) {
    return '$emoji $name unlocked!';
  }

  @override
  String get weeklyTopicFeaturedBadge => 'Weekly Featured Topic';

  @override
  String get weeklyTopicProgressTitle => 'Progress';

  @override
  String weeklyTopicLevelsCompleted(int count) {
    return '$count / 10 levels completed';
  }

  @override
  String get weeklyTopicRewardsTitle => 'Rewards';

  @override
  String weeklyTopicFiveLevelReward(int coins) {
    return '5 levels: +$coins coins';
  }

  @override
  String get weeklyTopicCoinRewardClaimed => 'Coin reward claimed';

  @override
  String get weeklyTopicClaim5LevelReward => 'Claim 5-level reward';

  @override
  String weeklyTopicTenLevelReward(String emoji, String name) {
    return '10 levels: $emoji $name';
  }

  @override
  String get weeklyTopicExclusiveClaimed => 'Exclusive reward claimed.';

  @override
  String get weeklyTopicExclusiveReady => 'Exclusive reward ready to claim.';

  @override
  String get weeklyTopicExclusiveLocked =>
      'Complete all 10 levels to unlock this reward.';

  @override
  String get weeklyTopicExclusiveClaimedButton => 'Exclusive reward claimed';

  @override
  String get weeklyTopicClaim10LevelReward => 'Claim 10-level reward';

  @override
  String get weeklyTopicCategoryMissing => 'Weekly Topic category is missing.';

  @override
  String get weeklyTopicPlayButton => 'Play Weekly Topic';

  @override
  String weeklyTopicCorrectAnswersProgress(int correct, int total) {
    return '$correct / $total correct answers';
  }

  @override
  String weeklyTopicCoinRewardDescription(int threshold, int coins) {
    return '$threshold correct answers: +$coins coins';
  }

  @override
  String get weeklyTopicClaimCoinReward => 'Claim coin reward';

  @override
  String weeklyTopicCompletionRewardDescription(
      int threshold, String emoji, String name) {
    return '$threshold correct answers: $emoji $name';
  }

  @override
  String get weeklyTopicClaimCompletionReward => 'Claim exclusive reward';

  @override
  String weeklyTopicExclusiveLockedRounds(int threshold) {
    return 'Get $threshold correct answers to unlock this reward.';
  }

  @override
  String get weeklyTopicRoundResultTitle => 'Round complete';

  @override
  String weeklyTopicRoundResultBody(int correct, int total) {
    return 'You answered $correct out of $total questions correctly.';
  }

  @override
  String get weeklyTopicRoundResultButton => 'Continue';

  @override
  String weeklyTopicRoundQuestionCount(int current, int total) {
    return 'Question $current of $total';
  }

  @override
  String weeklyTopicRoundCorrectCount(int correct) {
    return 'Correct: $correct';
  }

  @override
  String get weeklyLeagueScreenTitle => 'Weekly Challenge';

  @override
  String weeklyLeagueErrorLoading(String error) {
    return 'Error loading weekly challenge:\n$error';
  }

  @override
  String get weeklyLeagueNoScoresYet =>
      'No weekly scores yet.\nPlay a Daily Challenge to enter this weekly ranking.';

  @override
  String get weeklyLeagueRankingTitle => 'Weekly Ranking';

  @override
  String weeklyLeagueTierSuffix(String name) {
    return '$name Tier';
  }

  @override
  String weeklyLeagueScoreLabel(int score) {
    return 'Weekly Score: $score';
  }

  @override
  String weeklyLeagueResetIn(String time) {
    return 'Weekly reset in $time';
  }

  @override
  String get weeklyLeagueRewardHistoryButton => 'Reward history';

  @override
  String get weeklyLeaguePendingSeasonRewards => 'Pending season rewards';

  @override
  String get weeklyLeagueOpenToSeeDetails =>
      'Open Weekly Rewards to see exact rank and coins.';

  @override
  String get weeklyLeagueViewDetails => 'View details';

  @override
  String get weeklyLeagueClaim => 'Claim';

  @override
  String get weeklyLeagueWeeklyRewardsTitle => 'Weekly Rewards';

  @override
  String weeklyLeagueTop1Reward(int coins) {
    return 'Top 1: $coins coins + promotion bonus';
  }

  @override
  String weeklyLeagueTop3Reward(int coins) {
    return 'Top 2-3: $coins coins';
  }

  @override
  String weeklyLeagueTop10Reward(int coins) {
    return 'Top 10: $coins coins';
  }

  @override
  String get weeklyLeagueResetHint =>
      'At the end of the week, rankings reset and rewards become claimable.';

  @override
  String weeklyLeagueLevelStreak(int level, int streak) {
    return 'Level $level  •  Streak $streak';
  }

  @override
  String get weeklyLeagueWeeklyLabel => 'Weekly';

  @override
  String weeklyLeagueClaimedRewards(int count, int coins) {
    return 'Claimed $count rewards: +$coins coins!';
  }

  @override
  String authGateError(String error) {
    return 'Error: $error';
  }

  @override
  String get achievementsTitle => 'Achievements';

  @override
  String achievementsRewardClaimed(int coins, int xp) {
    return '🎉 Reward claimed: +$coins coins, +$xp XP';
  }

  @override
  String achievementsErrorLoading(String error) {
    return 'Error loading achievements:\n$error';
  }

  @override
  String get achievementsProgressTitle => 'Achievements Progress';

  @override
  String achievementsCompletedCount(int completed, int total) {
    return '$completed / $total completed';
  }

  @override
  String get achievementsClaimed => 'Claimed';

  @override
  String get achievementsClaimReward => 'Claim Reward';

  @override
  String get achievementsInProgress => 'In progress';

  @override
  String achievementsCoinsPill(int coins) {
    return '+$coins coins';
  }

  @override
  String get aiTopicsStatusReady => 'Ready';

  @override
  String get aiTopicsStatusFailed => 'Failed';

  @override
  String get aiTopicsStatusDeleted => 'Deleted';

  @override
  String get aiTopicsStatusInvalid => 'Needs repair';

  @override
  String get aiTopicsStatusBlocked => 'Blocked';

  @override
  String get aiTopicsStatusPreparing => 'Preparing';

  @override
  String get aiTopicsTitle => 'AI Topics';

  @override
  String get aiTopicsCreateTopic => 'Create Topic';

  @override
  String aiTopicsErrorLoading(String error) {
    return 'Error loading AI topics:\n$error';
  }

  @override
  String get aiTopicsUntitled => 'Untitled topic';

  @override
  String get aiTopicsDeleteTitle => 'Delete topic?';

  @override
  String aiTopicsDeleteBody(String title) {
    return 'Do you want to remove \"$title\" from your AI topics?';
  }

  @override
  String get aiTopicsCancel => 'Cancel';

  @override
  String get aiTopicsDelete => 'Delete';

  @override
  String aiTopicsLevelsQuestions(int levels, int questions) {
    return '$levels levels • $questions questions';
  }

  @override
  String get aiTopicsUnavailableSubtitle =>
      'This topic couldn\'t be generated. Swipe to delete it and get your cost back.';

  @override
  String get aiTopicsFree => 'Free';

  @override
  String aiTopicsCoinsCost(int cost) {
    return '$cost coins';
  }

  @override
  String aiTopicsRegenerateMenuItem(int cost) {
    return 'Add more questions — $cost coins';
  }

  @override
  String aiTopicsExpandMenuItem(int cost) {
    return 'Expand topic (+10 levels) — $cost coins';
  }

  @override
  String get aiTopicsRegenerateDialogTitle => 'Add more questions';

  @override
  String aiTopicsRegenerateDialogBody(String title, int cost, int coins) {
    return 'This generates new questions for \"$title\" and adds them to the ones it already has, so replaying each level gives you different questions.\n\nCost: $cost coins\nYou have: $coins coins';
  }

  @override
  String get aiTopicsRegenerateSuccess => 'Questions added';

  @override
  String get aiTopicsExpandDialogTitle => 'Expand topic';

  @override
  String aiTopicsExpandDialogBody(String title, int cost, int coins) {
    return 'Adds 10 more levels to \"$title\".\n\nCost: $cost coins\nYou have: $coins coins';
  }

  @override
  String get aiTopicsExpandSuccess => 'Topic expanded';

  @override
  String get aiTopicsConfirm => 'Confirm';

  @override
  String get aiTopicsEmptyTitle => 'Create your own trivia topic';

  @override
  String get aiTopicsEmptySubtitle =>
      'Choose any topic you like. AI-generated questions will be connected in the next step.';

  @override
  String get aiTopicsEmptyButton => 'Create AI Topic';

  @override
  String get createAiTopicEnterTopic => 'Enter a topic';

  @override
  String get createAiTopicCreated => 'AI topic created';

  @override
  String get createAiTopicSubtitle => 'Create your own trivia category';

  @override
  String get createAiTopicExamplesLabel => 'Examples:';

  @override
  String get createAiTopicExamplesList =>
      '• Formula 1\n• Harry Potter\n• Marvel Movies\n• Ancient Egypt\n• Space Exploration';

  @override
  String get createAiTopicFieldLabel => 'Topic';

  @override
  String get createAiTopicFieldHint => 'Example: Formula 1';

  @override
  String createAiTopicYouHaveCoins(int coins) {
    return 'You have $coins coins';
  }

  @override
  String get createAiTopicFirstFree => '🎉 Your first topic is free';

  @override
  String createAiTopicCosts(int cost) {
    return 'This topic costs $cost coins';
  }

  @override
  String createAiTopicMissingCoins(int amount) {
    return 'You\'re missing $amount coins';
  }

  @override
  String get createAiTopicIncludesHint =>
      'Includes 10 levels with 10 questions each, prepared gradually as you play.';

  @override
  String get createAiTopicCreatingButton => 'Creating...';

  @override
  String get createAiTopicPopularSectionTitle => 'Popular Topics';

  @override
  String get createAiTopicPopularSectionHint =>
      'Pick a topic other players already created and save coins';

  @override
  String createAiTopicPopularUsedCount(int count) {
    return 'Used $count times';
  }

  @override
  String createAiTopicPopularCostLabel(int cost) {
    return '$cost coins';
  }

  @override
  String get createAiTopicPopularSelectedHint =>
      '🔥 Popular topic selected: discounted cost';

  @override
  String get createAiTopicExistingSelectedHint =>
      '🏷️ Existing topic: discounted cost';

  @override
  String get createAiTopicPopularBadgeTooltip => 'Popular topic';

  @override
  String get createAiTopicExistingBadgeTooltip => 'Existing topic, discounted';

  @override
  String get createAiTopicNewBadgeTooltip =>
      'New topic, will be generated with AI';

  @override
  String get createAiTopicFreeLabel => 'Free';

  @override
  String get homeLivesUnavailable => 'Couldn\'t load your lives.';

  @override
  String get createAiTopicSearchingButton => 'Searching similar topics...';

  @override
  String get createAiTopicSuggestingButton =>
      'Asking the AI for suggestions...';

  @override
  String get createAiTopicBlockedMessage =>
      'Couldn\'t generate that topic. Try another title.';

  @override
  String get createAiTopicMatchesFoundTitle => 'We found similar topics';

  @override
  String get createAiTopicMatchesFoundHint =>
      'Pick one to play it instantly, or create yours as a new topic.';

  @override
  String get createAiTopicNoneOfTheseButton =>
      'None of these, create a new topic';

  @override
  String get createAiTopicBackButton => 'Back';

  @override
  String get createAiTopicAiSuggestionsTitle => 'AI suggestions';

  @override
  String get createAiTopicAiSuggestionsHint =>
      'Pick one of these to create your topic — this avoids typos or topics too vague to generate good questions from.';

  @override
  String get coinShopTitle => 'Buy coins';

  @override
  String coinShopPurchaseSuccess(int coins) {
    return '+$coins coins';
  }

  @override
  String get coinShopPurchaseFailed => 'The purchase didn\'t complete.';

  @override
  String get coinShopComingSoonTitle => 'Coming soon';

  @override
  String get coinShopComingSoonBody =>
      'Buying coins isn\'t available in this version yet.';

  @override
  String coinShopCoinsAmount(int coins) {
    return '$coins coins';
  }

  @override
  String get coinShopBuyButton => 'Buy';

  @override
  String get notificationsChallengeDeclined => 'Challenge declined';

  @override
  String get notificationsContinue => 'Continue';

  @override
  String get notificationsViewResult => 'View result';

  @override
  String get notificationsReview => 'Review';

  @override
  String get notificationsView => 'View';

  @override
  String get notificationsOpen => 'Open';

  @override
  String get notificationsOpenLobby => 'Open lobby';

  @override
  String get notificationsTitle => 'Notifications';

  @override
  String get notificationsReadAll => 'Read all';

  @override
  String notificationsErrorLoading(String error) {
    return 'Error loading notifications:\n$error';
  }

  @override
  String get notificationsFallbackTitle => 'Notification';

  @override
  String notificationsChallengerPrefix(String name) {
    return '👤 $name';
  }

  @override
  String notificationsCategoryLine(String category) {
    return '🎯 Category: $category';
  }

  @override
  String notificationsQuestionsLine(String count) {
    return '❓ Questions: $count';
  }

  @override
  String notificationsTimeLine(String seconds) {
    return '⏱ Time: $seconds sec';
  }

  @override
  String get notificationsEmptyState => 'No notifications yet.';

  @override
  String get presenceStatusOnline => 'Online';

  @override
  String get presenceStatusInMatch => 'In match';

  @override
  String get presenceStatusSearching => 'Searching match';

  @override
  String get friendsOfflineLabel => 'Offline';

  @override
  String get friendsLastSeenJustNow => 'Last seen just now';

  @override
  String friendsLastSeenMinutes(int minutes) {
    return 'Last seen ${minutes}m ago';
  }

  @override
  String friendsLastSeenHours(int hours) {
    return 'Last seen ${hours}h ago';
  }

  @override
  String get friendsEnterUsername => 'Enter a username to search.';

  @override
  String get friendsRequestSent => 'Request sent';

  @override
  String get friendsActionCompleted => 'Action completed';

  @override
  String get friendsTitle => 'Friends';

  @override
  String get friendsSearchTab => 'Search';

  @override
  String get friendsFriendsTab => 'Friends';

  @override
  String get friendsSentTab => 'Sent';

  @override
  String get friendsReceivedTab => 'Received';

  @override
  String get friendsUsernameLabel => 'Username';

  @override
  String get friendsNoPlayersFound => 'No players found with that username.';

  @override
  String friendsErrorLoadingFriends(String error) {
    return 'Error loading friends:\n$error';
  }

  @override
  String get friendsLoadingFriends => 'Loading friends...';

  @override
  String get friendsNoFriendsYet => 'You don\'t have any friends added yet.';

  @override
  String get friendsAsyncOnly => 'Async only';

  @override
  String friendsTodayScore(int score) {
    return 'Today: $score pts';
  }

  @override
  String get friendsNotPlayedToday => 'Hasn\'t played today';

  @override
  String friendsErrorLoadingSent(String error) {
    return 'Error loading sent requests:\n$error';
  }

  @override
  String get friendsLoadingSent => 'Loading sent requests...';

  @override
  String get friendsNoSentRequests =>
      'You don\'t have any pending requests to answer.';

  @override
  String get friendsPending => 'Pending';

  @override
  String get friendsSentStatus => 'Sent';

  @override
  String friendsErrorLoadingReceived(String error) {
    return 'Error loading requests:\n$error';
  }

  @override
  String get friendsLoadingReceived => 'Loading requests...';

  @override
  String get friendsNoReceivedRequests =>
      'You don\'t have any pending requests.';

  @override
  String get friendsWantsToAddYou => 'Wants to add you';

  @override
  String get friendsReject => 'Reject';

  @override
  String get friendsAccept => 'Accept';

  @override
  String get friendsAlreadyFriend => 'Already your friend';

  @override
  String get friendsWantsToAddYouTile => 'Wants to add you';

  @override
  String get friendsPlayerFound => 'Player found';

  @override
  String get friendsAddButton => 'Add';

  @override
  String get onboardingWelcomeTitle => 'Welcome to TriviaIA!';

  @override
  String get onboardingWelcomeBody =>
      'Answer trivia questions, compete against other players, and level up every day.';

  @override
  String get onboardingLivesTitle => 'Your lives';

  @override
  String get onboardingLivesBody =>
      'You have 5 lives. Each one refills on its own every 5 minutes, or you can buy it instantly with coins if you don\'t want to wait.';

  @override
  String get onboardingCoinsTitle => 'Coins and daily streak';

  @override
  String get onboardingCoinsBody =>
      'Earn coins and XP by playing. Come back every day to the Daily Challenge to keep your streak and earn extra rewards.';

  @override
  String get onboardingSkip => 'Skip';

  @override
  String get onboardingNext => 'Next';

  @override
  String get onboardingPlayFirstDaily => 'Play my first Daily Challenge';

  @override
  String get spotlightGotIt => 'Got it';

  @override
  String get spotlightPvpTitle => '1v1 Duels';

  @override
  String get spotlightPvpBody =>
      'Challenge other players in real time or asynchronously. Winning raises your rating and gets you closer to the next league, with bigger rewards.';

  @override
  String get spotlightWeeklyTopicTitle => 'Weekly Topic';

  @override
  String get spotlightWeeklyTopicBody =>
      'A special category rotates every week. Answer rounds to earn coins and an exclusive avatar before the week ends.';

  @override
  String get spotlightAchievementsTitle => 'Achievements';

  @override
  String get spotlightAchievementsBody =>
      'Complete goals by playing and claim their coin and XP reward by tapping the card once it\'s done.';

  @override
  String get spotlightFramesTitle => 'Profile frames';

  @override
  String get spotlightFramesBody =>
      'Customize your avatar with frames you unlock by climbing PvP leagues.';

  @override
  String get spotlightAiTopicsGuidedTitle => 'We search before generating';

  @override
  String get spotlightAiTopicsGuidedBody =>
      'When you create a topic we first look for a similar one: picking it costs less, because we reuse its questions. If there\'s none, the AI proposes well-formed options for you to choose from.';

  @override
  String get spotlightAiTopicsPopularTitle => 'Popular Topics';

  @override
  String get spotlightAiTopicsPopularBody =>
      'These topics were already generated by other players, so you can play them at a discount instead of paying full price for a new topic.';

  @override
  String get notificationBellTooltip => 'Notifications';

  @override
  String get buyCoinsButtonLabel => 'Buy coins';

  @override
  String profileErrorLoadingMatchHistory(String error) {
    return 'Error loading match history:\n$error';
  }

  @override
  String get levelPlayPerfect => 'PERFECT!';

  @override
  String get serviceEnterUsername => 'Enter a username.';

  @override
  String get serviceConnectionTimeout =>
      'Couldn\'t connect. Check your connection and try again.';

  @override
  String get serviceInvalidUser => 'Invalid user.';

  @override
  String get serviceCannotAddSelf => 'You can\'t add yourself.';

  @override
  String get serviceUserNotFound => 'The user doesn\'t exist.';

  @override
  String get serviceAlreadyFriends => 'You\'re already friends.';

  @override
  String get serviceRequestAlreadySent => 'Request already sent.';

  @override
  String get serviceRequestAlreadyReceived =>
      'That player already sent you a request — check your incoming requests.';

  @override
  String get serviceInvalidRequest => 'Invalid request.';

  @override
  String get serviceCouldNotAcceptRequest => 'Couldn\'t accept the request.';

  @override
  String get serviceCouldNotRejectRequest => 'Couldn\'t reject the request.';

  @override
  String get serviceInvalidFriend => 'Invalid friend.';

  @override
  String get serviceCouldNotRemoveFriend => 'Couldn\'t remove the friend.';

  @override
  String get serviceFriendRequestNotifTitle => 'New friend request';

  @override
  String serviceFriendRequestNotifBody(String name) {
    return '$name wants to add you as a friend.';
  }

  @override
  String serviceRankedCooldown(String remaining) {
    return 'You have a ranked cooldown from abandoning. Try again in $remaining.';
  }

  @override
  String get serviceRoomNotFound => 'Room doesn\'t exist';

  @override
  String get serviceNotInRoom => 'You\'re not in this room';

  @override
  String get serviceMatchNotFound => 'Match not found';

  @override
  String get serviceChallengedUidEmpty => 'challengedUid empty';

  @override
  String get serviceCannotChallengeSelfNoPeriod =>
      'You can\'t challenge yourself';

  @override
  String get serviceChallengeNotFound => 'Challenge not found';

  @override
  String get serviceNotYourChallenge => 'This challenge isn\'t yours';

  @override
  String get serviceAsyncMatchNotFound => 'Async match doesn\'t exist';

  @override
  String get serviceNotYourMatch => 'This match isn\'t yours';

  @override
  String servicePoolEmptyForCategory(String categoryId) {
    return 'Empty pool for $categoryId';
  }

  @override
  String get serviceNoActiveCategories => 'No active categories';

  @override
  String get serviceRematchRequestedTitle => 'Rematch requested';

  @override
  String serviceRematchRequestedBody(String name) {
    return '$name wants a rematch.';
  }

  @override
  String get serviceNewAsyncChallengeTitle => 'New async challenge';

  @override
  String serviceNewAsyncChallengeBody(String name) {
    return '$name challenged you to a 1 vs 1 match.';
  }

  @override
  String get serviceYourTurnTitle => 'Your turn';

  @override
  String serviceYourTurnBody(String name) {
    return '$name finished their async match. Now it is your turn.';
  }

  @override
  String get serviceCannotChallengeSelfPeriod =>
      'You can\'t challenge yourself.';

  @override
  String get serviceInviteNotFound => 'The invite no longer exists.';

  @override
  String get serviceCannotAcceptInvite => 'You can\'t accept this invite.';

  @override
  String get serviceInviteNoLongerAvailable =>
      'This invite is no longer available.';

  @override
  String get serviceNoQuestionsForCategory =>
      'No questions available for this category.';

  @override
  String get serviceNoActiveCategoriesAvailable =>
      'No active categories available.';

  @override
  String get serviceSeasonRewardNotificationTitle => 'Weekly reward available';

  @override
  String get serviceSeasonRewardNotificationBody =>
      'Your weekly league reward is ready to claim.';

  @override
  String get serviceRealtimeChallengeTitle => 'Realtime challenge';

  @override
  String serviceRealtimeChallengeBody(String name) {
    return '$name invited you to a realtime 1 vs 1 match.';
  }

  @override
  String get serviceRealtimeInviteAcceptedTitle => 'Realtime invite accepted';

  @override
  String serviceRealtimeInviteAcceptedBody(String name) {
    return '$name accepted your realtime challenge.';
  }

  @override
  String get serviceNoActiveDailyCategories =>
      'No active categories for the Daily Challenge.';

  @override
  String get serviceNoQuestionsInPools =>
      'No questions available in the fixed pools.';

  @override
  String get achievementFirstPvpWinTitle => 'First Duel Win';

  @override
  String get achievementFirstPvpWinDescription =>
      'Win your first 1 vs 1 match.';

  @override
  String get achievementPvpWins10Title => 'Duelist';

  @override
  String get achievementPvpWins10Description => 'Win 10 1 vs 1 matches.';

  @override
  String get achievementPvpStreak5Title => 'On Fire';

  @override
  String get achievementPvpStreak5Description =>
      'Reach a 5-win streak in 1 vs 1.';

  @override
  String get achievementSoloLevels10Title => 'Solo Explorer';

  @override
  String get achievementSoloLevels10Description => 'Complete 10 solo levels.';

  @override
  String get achievementDailyStreak7Title => 'Weekly Habit';

  @override
  String get achievementDailyStreak7Description =>
      'Reach a 7-day Daily Challenge streak.';

  @override
  String get achievementFriends5Title => 'Social Player';

  @override
  String get achievementFriends5Description => 'Add 5 friends.';

  @override
  String get achievementPvpWins25Title => 'Duel Veteran';

  @override
  String get achievementPvpWins25Description => 'Win 25 1v1 matches.';

  @override
  String get achievementSoloLevels25Title => 'Solo Master';

  @override
  String get achievementSoloLevels25Description => 'Pass 25 Solo mode levels.';

  @override
  String get achievementDailyStreak21Title => 'Iron Consistency';

  @override
  String get achievementDailyStreak21Description =>
      'Reach a 21-day Daily Challenge streak.';

  @override
  String get achievementFriends10Title => 'Social Circle';

  @override
  String get achievementFriends10Description => 'Add 10 friends.';

  @override
  String get achievementWeeklyTopics3Title => 'Weekly Explorer';

  @override
  String get achievementWeeklyTopics3Description => 'Complete 3 Weekly Topics.';

  @override
  String get achievementCategoriesExplored5Title => 'Curious Mind';

  @override
  String get achievementCategoriesExplored5Description =>
      'Pass at least one level in 5 different fixed Solo categories (AI-generated topics don\'t count).';

  @override
  String get serviceAchievementNotFound => 'Achievement not found.';

  @override
  String get serviceCouldNotClaimReward => 'Couldn\'t claim the reward.';

  @override
  String get serviceCouldNotCreateTopic => 'Couldn\'t create the topic.';

  @override
  String get serviceCouldNotRegenerateQuestions =>
      'Couldn\'t regenerate the questions.';

  @override
  String get serviceCouldNotExpandTopic => 'Couldn\'t expand the topic.';

  @override
  String get serviceCouldNotSearchTopics =>
      'Couldn\'t search for similar topics.';

  @override
  String get serviceCouldNotSuggestTopics => 'Couldn\'t get suggestions.';

  @override
  String get pvpWindowSameLeagueLabel => 'Same league';

  @override
  String get pvpWindowSameLeagueDescription =>
      'Looking first for an opponent very close to your MMR.';

  @override
  String get pvpWindowNearbyLeaguesLabel => 'Nearby leagues';

  @override
  String get pvpWindowNearbyLeaguesDescription =>
      'Expanding to players from nearby leagues.';

  @override
  String get pvpWindowExpandedRangeLabel => 'Expanded range';

  @override
  String get pvpWindowExpandedRangeDescription =>
      'Prioritizing finding a match without losing competitiveness.';

  @override
  String get pvpWindowAnyOpponentLabel => 'Any available opponent';

  @override
  String get pvpWindowAnyOpponentDescription =>
      'Now prioritizing that you can play without being stuck waiting.';

  @override
  String get weeklyRewardChampionBonus => 'Champion bonus!';

  @override
  String get weeklyRewardTop3Bonus => 'Top 3 bonus!';

  @override
  String get weeklyRewardTop10Bonus => 'Top 10 bonus!';

  @override
  String get weeklyRewardGenericBonus => 'Weekly league reward';
}
