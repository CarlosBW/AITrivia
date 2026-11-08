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

  group('solicitud de amistad', () {
    test('pendiente: los botones son la accion, no hay texto', () {
      expect(notificationCta(l10n, 'friend_request'), isNull);
    });

    test('ya respondida: dice como quedo', () {
      expect(
        notificationCta(l10n, 'friend_request',
            data: {'resolution': 'accepted'}),
        l10n.notificationsFriendRequestAccepted,
      );
      expect(
        notificationCta(l10n, 'friend_request',
            data: {'resolution': 'rejected'}),
        l10n.notificationsFriendRequestRejected,
      );
    });

    test('quien la mando sale del id del aviso', () {
      expect(
        friendRequestSenderUid('friend_request__abc123__', const {}),
        'abc123',
      );
    });

    test('si el aviso trae fromUid, manda ese', () {
      expect(
        friendRequestSenderUid('friend_request__abc123__', {'fromUid': 'x9'}),
        'x9',
      );
    });

    test('un id que no es de solicitud no da remitente', () {
      expect(friendRequestSenderUid('autoId42', const {}), isNull);
      expect(friendRequestSenderUid('friend_request____', const {}), isNull);
    });
  });
}
