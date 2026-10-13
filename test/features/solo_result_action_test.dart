import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/features/solo/level_play_screen.dart';

void main() {
  group('soloResultAction', () {
    test('a failed level offers a retry, not the locked next level', () {
      // 1/10 and 2/10 on Cine level 1: the server keeps level 2 locked.
      for (final correct in [0, 1, 2, 3]) {
        expect(
          soloResultAction(
            correct: correct,
            total: 10,
            alreadyPassed: false,
            levelNumber: 1,
            levelCount: 10,
          ),
          SoloResultAction.retry,
          reason: '$correct/10',
        );
      }
    });

    test('passing at 40% or more offers the next level', () {
      for (final correct in [4, 7, 10]) {
        expect(
          soloResultAction(
            correct: correct,
            total: 10,
            alreadyPassed: false,
            levelNumber: 1,
            levelCount: 10,
          ),
          SoloResultAction.next,
          reason: '$correct/10',
        );
      }
    });

    test('failing a replay of a level passed before still offers the next', () {
      expect(
        soloResultAction(
          correct: 1,
          total: 10,
          alreadyPassed: true,
          levelNumber: 1,
          levelCount: 10,
        ),
        SoloResultAction.next,
      );
    });

    test('passing the last level only offers going back', () {
      expect(
        soloResultAction(
          correct: 9,
          total: 10,
          alreadyPassed: false,
          levelNumber: 10,
          levelCount: 10,
        ),
        SoloResultAction.back,
      );
    });

    test('failing the last level offers a retry', () {
      expect(
        soloResultAction(
          correct: 1,
          total: 10,
          alreadyPassed: false,
          levelNumber: 10,
          levelCount: 10,
        ),
        SoloResultAction.retry,
      );
    });

    test('an unknown level count never offers a next level', () {
      expect(
        soloResultAction(
          correct: 9,
          total: 10,
          alreadyPassed: false,
          levelNumber: 1,
          levelCount: null,
        ),
        SoloResultAction.back,
      );
    });

    test('a level with no questions counts as failed', () {
      expect(
        soloResultAction(
          correct: 0,
          total: 0,
          alreadyPassed: false,
          levelNumber: 1,
          levelCount: 10,
        ),
        SoloResultAction.retry,
      );
    });
  });
}
