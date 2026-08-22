import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/frame_service.dart';

/// Frames are the cosmetic a player earns by climbing the PvP ladder, and
/// the unlock rules are mirrored in `firestore.rules`
/// (`unlockedFramesForLeague`) so a client can't equip one it never
/// reached. These tests pin the client half of that mirror.
void main() {
  final service = FrameService.instance;

  List<String> unlockedIds(String bestLeagueId) => service
      .unlockedLeagueFrames(bestLeagueId: bestLeagueId)
      .map((frame) => frame.id)
      .toList();

  group('unlockedLeagueFrames', () {
    test('la liga alcanzada desbloquea la suya y todas las anteriores', () {
      expect(unlockedIds('bronze'), ['bronze']);
      expect(unlockedIds('silver'), ['bronze', 'silver']);
      expect(unlockedIds('gold'), ['bronze', 'silver', 'gold']);
    });

    test('maestro desbloquea el catálogo entero', () {
      expect(
        unlockedIds('master'),
        ['bronze', 'silver', 'gold', 'platinum', 'diamond', 'master'],
      );
      expect(unlockedIds('master').length, service.leagueFrames.length);
    });

    // Un id que no existe no debe abrir nada: el fallback conservador es
    // bronce, no el catalogo completo.
    test('una liga desconocida cae a bronce', () {
      expect(unlockedIds('platino_de_oro'), ['bronze']);
      expect(unlockedIds(''), ['bronze']);
    });
  });

  group('isFrameUnlocked', () {
    test('un marco por debajo de la liga alcanzada está disponible', () {
      expect(
        service.isFrameUnlocked(frameId: 'silver', bestLeagueId: 'gold'),
        isTrue,
      );
    });

    test('un marco por encima no lo está', () {
      expect(
        service.isFrameUnlocked(frameId: 'diamond', bestLeagueId: 'gold'),
        isFalse,
      );
    });

    test('el marco de la propia liga sí', () {
      expect(
        service.isFrameUnlocked(frameId: 'gold', bestLeagueId: 'gold'),
        isTrue,
      );
    });
  });

  group('safestEquippedFrame', () {
    test('respeta un marco que el jugador sí tiene', () {
      expect(
        service.safestEquippedFrame(
          equippedFrame: 'silver',
          bestLeagueId: 'gold',
        ),
        'silver',
      );
    });

    // El caso que esta funcion existe para cubrir: alguien equipo un marco
    // y luego bajo de liga, o el dato llego manipulado.
    test('degrada a la liga real un marco que ya no corresponde', () {
      expect(
        service.safestEquippedFrame(
          equippedFrame: 'master',
          bestLeagueId: 'silver',
        ),
        'silver',
      );
    });

    test('sin marco equipado usa bronce si la liga lo permite', () {
      expect(
        service.safestEquippedFrame(
          equippedFrame: null,
          bestLeagueId: 'gold',
        ),
        'bronze',
      );
    });

    test('un id inventado no se cuela', () {
      expect(
        service.safestEquippedFrame(
          equippedFrame: 'marco_dorado_hackeado',
          bestLeagueId: 'gold',
        ),
        'gold',
      );
    });
  });

  group('frameById', () {
    test('resuelve cada liga del catálogo', () {
      for (final frame in service.leagueFrames) {
        expect(service.frameById(frame.id).id, frame.id);
      }
    });

    test('cae a bronce ante un id vacío o desconocido', () {
      expect(service.frameById(null).id, 'bronze');
      expect(service.frameById('').id, 'bronze');
      expect(service.frameById('   ').id, 'bronze');
      expect(service.frameById('no_existe').id, 'bronze');
    });
  });
}
