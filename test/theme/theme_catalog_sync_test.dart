import 'dart:io';

import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/theme/app_theme.dart';
import 'package:trivia_ia_flutter/theme/app_themes.dart';

/// A theme's price exists twice: here, for what the store shows, and in
/// `THEME_PRICES` in `index.ts`, for what actually leaves the player's
/// balance. Only the server's copy is authoritative — `purchaseTheme`
/// ignores whatever the client sends — so a drift wouldn't overcharge
/// anyone, it would advertise one price and charge another.
///
/// Same shape as `economy_sync_test.dart` and `life_balance_sync_test.dart`:
/// read the server's table instead of restating it.
void main() {
  final indexTs = File('functions/src/index.ts').readAsStringSync();

  final block = RegExp(
    r'const THEME_PRICES: Record<string, number> = \{([\s\S]*?)\};',
  ).firstMatch(indexTs)?.group(1);

  Map<String, int> serverPrices() {
    expect(
      block,
      isNotNull,
      reason: 'index.ts ya no declara `THEME_PRICES`. Si cambió de forma, '
          'actualiza este test para que siga vigilando el precio.',
    );

    return {
      for (final m in RegExp(r'"([\w-]+)":\s*(\d+)').allMatches(block!))
        m.group(1)!: int.parse(m.group(2)!),
    };
  }

  group('el catalogo cuadra con el servidor', () {
    test('cada tema de pago tiene precio en el servidor', () {
      final prices = serverPrices();

      for (final spec in AppThemes.all.where((s) => !s.isFree)) {
        expect(
          prices.containsKey(spec.id),
          isTrue,
          reason: 'THEME_PRICES no cubre "${spec.id}", asi que comprarlo '
              'fallaria con invalid-argument',
        );
        expect(
          spec.price,
          prices[spec.id],
          reason: 'la tienda muestra ${spec.price} y el servidor cobra '
              '${prices[spec.id]} por "${spec.id}"',
        );
      }
    });

    // Al reves tambien: un precio en el servidor sin tema en el cliente es
    // un id que nadie puede comprar y que, si se compra desde una version
    // vieja, no se puede pintar.
    test('el servidor no cobra por temas que el cliente no conoce', () {
      for (final id in serverPrices().keys) {
        expect(
          AppThemes.exists(id),
          isTrue,
          reason: 'THEME_PRICES cobra por "$id" y AppThemes no lo tiene',
        );
      }
    });

    // El tema gratis no debe estar en la tabla: si lo estuviera, se cobraria
    // por lo que todo el mundo ya tiene.
    test('el tema por defecto no se cobra', () {
      expect(serverPrices().containsKey(AppThemes.defaultId), isFalse);
      expect(AppThemes.byId(AppThemes.defaultId).isFree, isTrue);
    });
  });

  group('el catalogo esta bien formado', () {
    test('los ids no se repiten', () {
      final ids = AppThemes.all.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('un id desconocido cae al tema por defecto', () {
      // Un jugador que compró un tema en una versión más nueva debe ver la
      // app base, no un fallo.
      expect(AppThemes.byId('no-existe').id, AppThemes.defaultId);
      expect(AppThemes.byId(null).id, AppThemes.defaultId);
    });

    test('cada tema trae tres muestras para la tienda', () {
      for (final spec in AppThemes.all) {
        expect(spec.preview, hasLength(3), reason: spec.id);
      }
    });
  });

  group('el tema juguetón se distingue del clásico', () {
    final playful = AppThemes.byId(AppThemes.playfulId);
    final base = AppThemes.byId(AppThemes.defaultId);

    // Lo que define el diseño: contorno marcado y sombra sólida. Si un
    // refactor los igualara al clásico, el jugador pagaría por nada.
    test('dibuja contorno y el clasico no', () {
      expect(base.surfaces.hasBorder, isFalse);
      expect(playful.surfaces.hasBorder, isTrue);
      expect(playful.surfaces.side, isNotNull);
    });

    test('su sombra es solida, sin desenfoque', () {
      expect(playful.surfaces.shadowBlur, 0);
      expect(base.surfaces.shadowBlur, greaterThan(0));
    });

    test('sus botones tienen labio para poder hundirse', () {
      expect(playful.surfaces.buttonLip, greaterThan(0));
      expect(base.surfaces.buttonLip, 0);
    });

    // El diseño fue explícito en no tocar la paleta: el cambio es de peso y
    // profundidad, no de color.
    test('conserva la paleta del clasico', () {
      expect(playful.colorScheme, base.colorScheme);
      expect(playful.scaffoldBackground, base.scaffoldBackground);
    });
  });

  group('AppSurfaces', () {
    test('sin contorno no produce BorderSide', () {
      expect(AppSurfaces.standard.side, isNull);
    });

    // La promesa del barrido: enrutar 37 superficies por el token no cambia
    // ni un pixel del tema clasico. Si `standard` empezara a imponer lo
    // suyo, restilaria toda la app de golpe sin que nadie lo pidiera.
    group('el tema clasico devuelve lo que le den, intacto', () {
      test('conserva la ausencia de borde', () {
        expect(AppSurfaces.standard.borderOr(null), isNull);
      });

      test('conserva el borde que trae la pantalla', () {
        final own = Border.all(color: const Color(0xFF123456), width: 1.5);
        expect(AppSurfaces.standard.borderOr(own), same(own));
      });

      test('conserva la sombra que trae la pantalla', () {
        final own = [
          const BoxShadow(color: Color(0x22000000), blurRadius: 7),
        ];
        expect(AppSurfaces.standard.shadowsOr(own), same(own));
      });

      test('conserva la ausencia de sombra', () {
        expect(AppSurfaces.standard.shadowsOr(null), isNull);
      });
    });

    group('el tema juguetón impone lo suyo', () {
      final playful = AppThemes.byId(AppThemes.playfulId).surfaces;

      test('pone contorno donde no habia ninguno', () {
        expect(playful.borderOr(null), isNotNull);
      });

      test('sustituye el borde de la pantalla', () {
        final own = Border.all(color: const Color(0xFF123456), width: 1.5);
        final result = playful.borderOr(own);

        expect(result, isNotNull);
        expect(result!.top.color, playful.borderColor);
        expect(result.top.width, playful.borderWidth);
      });

      test('sustituye la sombra por la suya, solida', () {
        final own = [
          const BoxShadow(color: Color(0x22000000), blurRadius: 7),
        ];
        final result = playful.shadowsOr(own);

        expect(result, hasLength(1));
        expect(result!.first.blurRadius, 0);
        expect(result.first.color, playful.shadowColor);
      });

      test('pone sombra donde no habia ninguna', () {
        expect(playful.shadowsOr(null), hasLength(1));
      });
    });

    test('lerp interpola el grosor y el desenfoque', () {
      final playful = AppThemes.byId(AppThemes.playfulId).surfaces;
      final mid = AppSurfaces.standard.lerp(playful, 1.0);

      expect(mid.borderWidth, playful.borderWidth);
      expect(mid.shadowBlur, playful.shadowBlur);
      expect(mid.buttonLip, playful.buttonLip);
    });
  });
}
