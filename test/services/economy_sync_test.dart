import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/economy_service.dart';

/// `EconomyService` is a price list the client shows; `index.ts` holds the
/// same numbers and is what actually charges. Nothing links them.
///
/// This is the same trap the life balance fell into — and here the failure
/// is quieter and worse: a client that advertises 300 coins while the
/// server charges 400 doesn't error, it just takes more money than the
/// player agreed to. No exception, no log, no way to notice from the app.
///
/// The test reads `index.ts` instead of restating its values, so the only
/// way to make it pass is to change both sides.
void main() {
  final indexTs = File('functions/src/index.ts').readAsStringSync();

  int serverConstant(String name) {
    final match = RegExp('^const $name = (-?\\d+);', multiLine: true)
        .firstMatch(indexTs);

    expect(
      match,
      isNotNull,
      reason: 'functions/src/index.ts no declara `const $name`. Si lo '
          'renombraste, actualiza este test para que siga vigilando.',
    );

    return int.parse(match!.group(1)!);
  }

  group('precios en monedas', () {
    test('comprar una vida', () {
      expect(serverConstant('BUY_FULL_LIFE_COST'),
          EconomyService.buyFullLifeCost);
    });

    test('crear un tema IA desde cero', () {
      expect(serverConstant('CREATE_AI_TOPIC_COST'),
          EconomyService.createAiTopicCost);
    });

    test('crear un tema IA reutilizando el pool', () {
      expect(serverConstant('CREATE_AI_TOPIC_FROM_POOL_COST'),
          EconomyService.createAiTopicFromPoolCost);
    });

    test('crear un tema IA que ya existe', () {
      expect(serverConstant('CREATE_AI_TOPIC_EXISTING_COST'),
          EconomyService.createAiTopicExistingCost);
    });

    test('ampliar un tema IA', () {
      expect(serverConstant('EXPAND_AI_TOPIC_COST'),
          EconomyService.expandAiTopicCost);
    });
  });

  group('recompensas en monedas', () {
    test('nivel perfecto', () {
      expect(serverConstant('SOLO_PERFECT_LEVEL_COINS'),
          EconomyService.soloPerfectLevelCoins);
    });

    test('nivel muy bueno', () {
      expect(serverConstant('SOLO_GREAT_LEVEL_COINS'),
          EconomyService.soloGreatLevelCoins);
    });

    test('nivel aprobado', () {
      expect(serverConstant('SOLO_GOOD_LEVEL_COINS'),
          EconomyService.soloGoodLevelCoins);
    });

    test('completar una categoría', () {
      expect(serverConstant('COMPLETE_FIXED_CATEGORY_COINS'),
          EconomyService.completeFixedCategoryCoins);
    });

    test('bloque de aciertos del reto diario', () {
      expect(serverConstant('DAILY_COINS_PER_BLOCK'),
          EconomyService.dailyCoinsPerBlock);
      expect(serverConstant('DAILY_CORRECT_PER_COIN_BLOCK'),
          EconomyService.dailyCorrectPerCoinBlock);
    });

    test('subir de nivel en el reto diario', () {
      expect(serverConstant('DAILY_LEVEL_UP_COINS'),
          EconomyService.dailyLevelUpCoins);
    });
  });

  group('límites y umbrales de temas IA', () {
    test('pases gratis al empezar', () {
      expect(serverConstant('FIRST_AI_TOPIC_FREE_PASSES'),
          EconomyService.firstAiTopicFreePasses);
    });

    test('temas máximos por cuenta', () {
      expect(serverConstant('MAX_AI_TOPICS_PER_USER'),
          EconomyService.maxAiTopicsPerUser);
    });

    test('usos para considerar un tema popular', () {
      expect(serverConstant('AI_TOPIC_POPULAR_USAGE_THRESHOLD'),
          EconomyService.aiTopicPopularUsageThreshold);
    });

    test('niveles por tema', () {
      expect(serverConstant('AI_LEVELS_PER_TOPIC'),
          EconomyService.aiLevelsPerTopic);
    });

    test('preguntas por nivel', () {
      expect(serverConstant('AI_QUESTIONS_PER_LEVEL'),
          EconomyService.aiQuestionsPerLevel);
    });

    test('niveles que se generan por delante', () {
      expect(serverConstant('AI_GENERATION_BUFFER_LEVELS'),
          EconomyService.aiGenerationBufferLevels);
    });

    test('niveles generados de entrada', () {
      expect(serverConstant('AI_INITIAL_GENERATED_LEVELS'),
          EconomyService.aiInitialGeneratedLevels);
    });
  });

  group('la escala de recompensas se mantiene ordenada', () {
    test('perfecto paga más que muy bueno, y este más que aprobado', () {
      expect(
        EconomyService.soloPerfectLevelCoins,
        greaterThan(EconomyService.soloGreatLevelCoins),
      );
      expect(
        EconomyService.soloGreatLevelCoins,
        greaterThan(EconomyService.soloGoodLevelCoins),
      );
    });

    test('la racha diaria paga más cuanto más larga', () {
      expect(
        EconomyService.dailyStreak7DaysCoins,
        greaterThan(EconomyService.dailyStreak3DaysCoins),
      );
      expect(
        EconomyService.dailyStreak14DaysCoins,
        greaterThan(EconomyService.dailyStreak7DaysCoins),
      );
    });

    // Reusar el trabajo de otro jugador deberia salir mas barato que
    // encargar un tema nuevo, o el pool no tiene sentido economico.
    test('reutilizar el pool es más barato que crear de cero', () {
      expect(
        EconomyService.createAiTopicFromPoolCost,
        lessThan(EconomyService.createAiTopicCost),
      );
    });
  });
}
