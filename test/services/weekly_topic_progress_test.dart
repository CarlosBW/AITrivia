import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/weekly_topic_service.dart';

/// La tarjeta del tema de la semana en Inicio muestra cuánto falta para la
/// siguiente recompensa.
void main() {
  test('primero se trabaja hacia las monedas', () {
    expect(weeklyTopicNextTarget(0), WeeklyTopicService.coinRewardThreshold);
    expect(weeklyTopicNextTarget(24), WeeklyTopicService.coinRewardThreshold);
  });

  test('alcanzadas las monedas, hacia la recompensa exclusiva', () {
    expect(
      weeklyTopicNextTarget(WeeklyTopicService.coinRewardThreshold),
      WeeklyTopicService.completionRewardThreshold,
    );
    expect(
      weeklyTopicNextTarget(500),
      WeeklyTopicService.completionRewardThreshold,
    );
  });

  test('la barra va de vacía a llena sin pasarse', () {
    expect(weeklyTopicProgress(0), 0);
    expect(weeklyTopicProgress(12), closeTo(12 / 25, 0.0001));
    expect(weeklyTopicProgress(25), closeTo(0.5, 0.0001));
    expect(weeklyTopicProgress(500), 1);
  });
}
