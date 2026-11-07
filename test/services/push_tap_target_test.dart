import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/notification_service.dart';

/// Tocar el aviso de un reto llevaba a la lista de notificaciones, de ahí a
/// la de invitaciones, y recién ahí se aceptaba. Ahora el aviso lleva a
/// donde dice.
void main() {
  test('un reto en vivo se acepta directamente', () {
    expect(
      pushTapTarget({'type': 'realtime_invite', 'inviteId': 'inv1'}),
      const PushTapTarget.acceptLiveInvite('inv1'),
    );
  });

  test('un reto por turnos abre la partida', () {
    for (final type in ['match_invite', 'match_turn', 'match_result']) {
      expect(
        pushTapTarget({'type': type, 'matchId': 'm1'}),
        const PushTapTarget.asyncMatch('m1'),
        reason: type,
      );
    }
  });

  test('un reto aceptado abre la sala', () {
    expect(
      pushTapTarget({
        'type': 'realtime_invite_accepted',
        'inviteId': 'inv1',
        'matchId': 'm1',
      }),
      const PushTapTarget.liveLobby('m1'),
    );
  });

  // Los avisos enviados antes de este cambio no traen los ids.
  test('sin ids, o de otro tipo, abre la lista como antes', () {
    expect(pushTapTarget({'type': 'realtime_invite'}),
        const PushTapTarget.notifications());
    expect(pushTapTarget({'type': 'match_turn'}),
        const PushTapTarget.notifications());
    expect(pushTapTarget({'type': 'streak_at_risk'}),
        const PushTapTarget.notifications());
    expect(pushTapTarget({}), const PushTapTarget.notifications());
  });
}
