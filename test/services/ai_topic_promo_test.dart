import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:trivia_ia_flutter/services/ai_topic_promo.dart';

/// El recordatorio de temas personalizados sale cada pocos días, no en cada
/// apertura, y nunca el primer día.
void main() {
  final day0 = DateTime(2026, 11, 13, 10);

  test('vence al cumplirse el intervalo, no antes', () {
    final anchor = day0.millisecondsSinceEpoch;
    int at(Duration d) => day0.add(d).millisecondsSinceEpoch;

    expect(
      aiTopicPromoDue(anchorMs: anchor, nowMs: at(const Duration(days: 3))),
      isFalse,
    );
    expect(
      aiTopicPromoDue(anchorMs: anchor, nowMs: at(aiTopicPromoInterval)),
      isTrue,
    );
  });

  test('un reloj atrasado no lo dispara', () {
    final anchor = day0.millisecondsSinceEpoch;
    expect(
      aiTopicPromoDue(
        anchorMs: anchor,
        nowMs: day0.subtract(const Duration(days: 30)).millisecondsSinceEpoch,
      ),
      isFalse,
    );
  });

  test('la primera apertura solo pone el reloj en marcha', () async {
    SharedPreferences.setMockInitialValues({});

    expect(await takeAiTopicPromoTurn(now: day0), isFalse);
    expect(
      await takeAiTopicPromoTurn(now: day0.add(const Duration(hours: 5))),
      isFalse,
    );
  });

  test('sale a los días, y luego espera otra vez', () async {
    SharedPreferences.setMockInitialValues({});
    await takeAiTopicPromoTurn(now: day0);

    final due = day0.add(aiTopicPromoInterval);
    expect(await takeAiTopicPromoTurn(now: due), isTrue);
    // Mostrado: la siguiente apertura ya no lo repite.
    expect(
      await takeAiTopicPromoTurn(now: due.add(const Duration(minutes: 1))),
      isFalse,
    );
    expect(
      await takeAiTopicPromoTurn(now: due.add(aiTopicPromoInterval)),
      isTrue,
    );
  });
}
