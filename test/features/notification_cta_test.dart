import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/features/notifications/notifications_screen.dart';
import 'package:trivia_ia_flutter/l10n/generated/app_localizations.dart';

/// Un aviso que no abre nada no debe ofrecer un "Abrir" que no hace nada.
void main() {
  final l10n = lookupAppLocalizations(const Locale('es'));

  test('los avisos de pregunta reportada no ofrecen abrir nada', () {
    expect(notificationCta(l10n, 'question_report'), isNull);
  });

  test('los demas avisos siguen con su accion', () {
    expect(notificationCta(l10n, 'match_turn'), l10n.notificationsContinue);
    expect(notificationCta(l10n, 'algo_nuevo'), l10n.notificationsOpen);
  });
}
