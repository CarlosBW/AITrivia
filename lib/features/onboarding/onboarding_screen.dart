import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../auth/user_bootstrap.dart';
import '../daily/daily_challenge_screen.dart';
import '../navigation/main_navigation_screen.dart';
import '../../services/analytics_service.dart';
import '../../l10n/generated/app_localizations.dart';

class _OnboardingPageData {
  final String emoji;
  final String title;
  final String body;

  const _OnboardingPageData({
    required this.emoji,
    required this.title,
    required this.body,
  });
}

List<_OnboardingPageData> _pagesFor(AppLocalizations l10n) => [
      _OnboardingPageData(
        emoji: '🧠',
        title: l10n.onboardingWelcomeTitle,
        body: l10n.onboardingWelcomeBody,
      ),
      _OnboardingPageData(
        emoji: '❤️',
        title: l10n.onboardingLivesTitle,
        body: l10n.onboardingLivesBody,
      ),
      _OnboardingPageData(
        emoji: '🔥',
        title: l10n.onboardingCoinsTitle,
        body: l10n.onboardingCoinsBody,
      ),
    ];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;
  bool _finishing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish({required bool goToDailyChallenge}) async {
    if (_finishing) return;
    setState(() => _finishing = true);

    final uid = FirebaseAuth.instance.currentUser!.uid;

    try {
      await markOnboardingSeen(uid);
    } catch (_) {
      // No bloquear la entrada al juego si falla marcar el flag.
    }

    try {
      await AnalyticsService.instance.logOnboardingComplete(
        skipped: !goToDailyChallenge,
      );
    } catch (_) {}

    if (!mounted) return;

    // Always land on MainNavigationScreen as the new root route first, so
    // there's a "home" left to pop back to — DailyChallengeScreen is then
    // pushed on top rather than replacing everything, otherwise its result
    // screen's "back home" button has nothing below it to pop to.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainNavigationScreen()),
    );

    if (goToDailyChallenge) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DailyChallengeScreen(uid: uid)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final pages = _pagesFor(l10n);
    final isLastPage = _page == pages.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: TextButton(
                onPressed: _finishing
                    ? null
                    : () => _finish(goToDailyChallenge: false),
                child: Text(l10n.onboardingSkip),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, index) {
                  final page = pages[index];

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          page.emoji,
                          style: const TextStyle(fontSize: 72),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.baloo2(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          page.body,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(pages.length, (i) {
                final active = i == _page;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              }),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _finishing
                      ? null
                      : () {
                          if (isLastPage) {
                            _finish(goToDailyChallenge: true);
                          } else {
                            _controller.nextPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOut,
                            );
                          }
                        },
                  child: Text(
                    isLastPage
                        ? l10n.onboardingPlayFirstDaily
                        : l10n.onboardingNext,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
