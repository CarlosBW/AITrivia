import 'package:firebase_analytics/firebase_analytics.dart';

class AnalyticsService {
  AnalyticsService._();

  static final AnalyticsService instance = AnalyticsService._();

  FirebaseAnalytics get _analytics => FirebaseAnalytics.instance;

  Future<void> logSignUp() async {
    await _analytics.logSignUp(signUpMethod: 'anonymous');
  }

  Future<void> logOnboardingComplete({required bool skipped}) async {
    await _analytics.logEvent(
      name: 'onboarding_complete',
      parameters: {'skipped': skipped},
    );
  }

  Future<void> logDailyChallengeComplete({
    required int streak,
    required int score,
  }) async {
    await _analytics.logEvent(
      name: 'daily_challenge_complete',
      parameters: {'streak': streak, 'score': score},
    );
  }

  Future<void> logPvpMatchComplete({
    required String mode,
    required String result,
    required bool ranked,
  }) async {
    await _analytics.logEvent(
      name: 'pvp_match_complete',
      parameters: {'mode': mode, 'result': result, 'ranked': ranked},
    );
  }

  Future<void> logAchievementUnlocked({required String achievementId}) async {
    await _analytics.logEvent(
      name: 'achievement_unlocked',
      parameters: {'achievement_id': achievementId},
    );
  }

  Future<void> logNavTabSelected({required String tab}) async {
    await _analytics.logEvent(
      name: 'nav_tab_selected',
      parameters: {'tab': tab},
    );
  }
}
