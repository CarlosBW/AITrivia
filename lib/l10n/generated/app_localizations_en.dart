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
  String get profileEditUsername => 'Edit username';

  @override
  String get profileEnterUsername => 'Enter username';

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
  String profileUpdateError(String error) {
    return 'Error updating profile: $error';
  }

  @override
  String get profileUpdated => 'Profile updated';

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
}
