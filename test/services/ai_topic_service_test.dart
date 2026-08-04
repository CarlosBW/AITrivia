import 'package:flutter_test/flutter_test.dart';
import 'package:trivia_ia_flutter/services/ai_topic_service.dart';

void main() {
  // This predicate decides whether a failed suggestion call strands the
  // player or lets them continue with the title they typed. Getting it
  // wrong in either direction is a real bug: too narrow restores the
  // dead-end this was written to remove, too wide sends them on to a
  // second identical refusal from createAiTopic.
  group('isRecoverableSuggestionFailure', () {
    test('recovers when the model itself failed', () {
      // What suggestAiTopicTitles throws after exhausting its retries —
      // an outage, a bad API key, a rate limit, a malformed response.
      expect(isRecoverableSuggestionFailure('internal'), isTrue);
    });

    test('recovers when the call never completed', () {
      expect(isRecoverableSuggestionFailure('unavailable'), isTrue);
      expect(isRecoverableSuggestionFailure('deadline-exceeded'), isTrue);
    });

    test('does not recover from the AI-topic cap', () {
      // createAiTopic enforces MAX_AI_TOPICS_PER_USER too, so offering
      // "create it anyway" here would just fail again a tap later.
      expect(isRecoverableSuggestionFailure('resource-exhausted'), isFalse);
    });

    test('does not recover from a rejection of the request itself', () {
      for (final code in [
        'invalid-argument',
        'unauthenticated',
        'permission-denied',
        'failed-precondition',
        'already-exists',
      ]) {
        expect(
          isRecoverableSuggestionFailure(code),
          isFalse,
          reason: '$code is about the request, not the service',
        );
      }
    });

    test('treats an unknown code as non-recoverable', () {
      expect(isRecoverableSuggestionFailure(''), isFalse);
      expect(isRecoverableSuggestionFailure('not-a-real-code'), isFalse);
    });
  });
}
