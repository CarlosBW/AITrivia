import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../auth/user_bootstrap.dart';
import '../daily/daily_challenge_screen.dart';
import '../navigation/main_navigation_screen.dart';

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

const _pages = [
  _OnboardingPageData(
    emoji: '🧠',
    title: '¡Bienvenido a TriviaIA!',
    body:
        'Responde preguntas de trivia, compite contra otros jugadores y sube de nivel cada día.',
  ),
  _OnboardingPageData(
    emoji: '❤️',
    title: 'Tus vidas',
    body:
        'Tienes 5 vidas. Cada una se recupera sola cada 5 minutos, o puedes comprarla al instante con monedas si no quieres esperar.',
  ),
  _OnboardingPageData(
    emoji: '🔥',
    title: 'Monedas y racha diaria',
    body:
        'Gana monedas y XP jugando. Vuelve cada día al Daily Challenge para mantener tu racha y ganar recompensas extra.',
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

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => goToDailyChallenge
            ? DailyChallengeScreen(uid: uid)
            : const MainNavigationScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLastPage = _page == _pages.length - 1;

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
                child: const Text('Saltar'),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, index) {
                  final page = _pages[index];

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
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          page.body,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.black.withOpacity(0.65),
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
              children: List.generate(_pages.length, (i) {
                final active = i == _page;

                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: active ? 22 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active ? Colors.deepPurple : Colors.black26,
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
                    isLastPage ? 'Jugar mi primer Daily Challenge' : 'Siguiente',
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
