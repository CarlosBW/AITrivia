import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/weekly_league_service.dart';

/// The week id names the document a player's weekly standing lives in, and
/// `rotateWeeklyTopic` runs against the same Monday boundary on the server.
/// If the anchoring drifts, a player's score lands in a week nobody reads.
void main() {
  final service = WeeklyLeagueService.instance;

  // 2026-08-17 is a Monday; the 23rd is the Sunday that closes that week.
  final monday = DateTime(2026, 8, 17);
  final sunday = DateTime(2026, 8, 23);

  group('currentWeekId', () {
    test('el lunes se nombra a sí mismo', () {
      expect(service.currentWeekId(monday), '2026-08-17');
    });

    test('todos los días de la semana caen en el mismo lunes', () {
      for (var offset = 0; offset < 7; offset++) {
        final day = monday.add(Duration(days: offset));
        expect(
          service.currentWeekId(day),
          '2026-08-17',
          reason: 'falló para ${day.toIso8601String()}',
        );
      }
    });

    test('el lunes siguiente abre una semana nueva', () {
      expect(
        service.currentWeekId(sunday.add(const Duration(days: 1))),
        '2026-08-24',
      );
    });

    test('la hora del día no cambia la semana', () {
      expect(
        service.currentWeekId(DateTime(2026, 8, 19, 0, 0, 0)),
        service.currentWeekId(DateTime(2026, 8, 19, 23, 59, 59)),
      );
    });

    // Una semana puede empezar en diciembre y terminar en enero: el id
    // tiene que seguir siendo el del lunes, no el del año en curso.
    test('una semana a caballo entre dos años', () {
      expect(service.currentWeekId(DateTime(2026, 12, 31)), '2026-12-28');
      expect(service.currentWeekId(DateTime(2027, 1, 1)), '2026-12-28');
    });
  });

  group('nextResetDate', () {
    test('cae en el lunes siguiente a medianoche', () {
      final reset = service.nextResetDate(DateTime(2026, 8, 19, 15, 30));

      expect(reset, DateTime(2026, 8, 24));
      expect(reset.weekday, DateTime.monday);
    });

    test('desde el propio lunes apunta a siete días después', () {
      expect(service.nextResetDate(monday), DateTime(2026, 8, 24));
    });
  });

  group('timeUntilReset', () {
    test('nunca es negativo dentro de la semana', () {
      for (var offset = 0; offset < 7; offset++) {
        final day = monday.add(Duration(days: offset, hours: 12));
        expect(service.timeUntilReset(day), greaterThan(Duration.zero));
      }
    });

    test('encoge conforme avanza la semana', () {
      final early = service.timeUntilReset(DateTime(2026, 8, 17, 9));
      final late = service.timeUntilReset(DateTime(2026, 8, 22, 9));

      expect(late, lessThan(early));
    });

    test('desde el lunes a medianoche queda una semana entera', () {
      expect(service.timeUntilReset(monday), const Duration(days: 7));
    });
  });
}
