import {test, describe} from "node:test";
import assert from "node:assert/strict";

import {
  AI_TOPIC_SIMILARITY_THRESHOLD,
  aiTopicPoolId,
  jaccardWordOverlap,
  levenshteinDistance,
  stripAccents,
  titleSimilarity,
} from "./ai_topic_similarity";

/**
 * Whether `findSimilarAiTopics` would offer `candidate` as a reusable
 * match for what the player typed.
 * @param {string} typed What the player typed, normalized.
 * @param {string} candidate An existing pool entry's normalized title.
 * @return {boolean} True if it clears the match threshold.
 */
function wouldOffer(typed: string, candidate: string): boolean {
  return titleSimilarity(typed, candidate) >= AI_TOPIC_SIMILARITY_THRESHOLD;
}

describe("levenshteinDistance", () => {
  test("is zero for identical strings", () => {
    assert.equal(levenshteinDistance("dinosaurios", "dinosaurios"), 0);
  });

  test("counts single-character edits", () => {
    assert.equal(levenshteinDistance("roma", "rosa"), 1);
    assert.equal(levenshteinDistance("cine", "vino"), 2);
  });

  test("equals the other string's length when one side is empty", () => {
    assert.equal(levenshteinDistance("", "marvel"), 6);
    assert.equal(levenshteinDistance("marvel", ""), 6);
  });
});

describe("jaccardWordOverlap", () => {
  test("ignores word order", () => {
    assert.equal(jaccardWordOverlap("marvel movies", "movies marvel"), 1);
  });

  test("is zero when no words are shared", () => {
    assert.equal(jaccardWordOverlap("antiguo egipto", "formula uno"), 0);
  });

  test("scores partial overlap between zero and one", () => {
    // {historia, de, roma} vs {historia, de, grecia}: 2 shared of 4 total.
    assert.equal(
      jaccardWordOverlap("historia de roma", "historia de grecia"), 0.5
    );
  });
});

describe("stripAccents", () => {
  test("removes diacritics but keeps the letters", () => {
    assert.equal(stripAccents("perú"), "peru");
    assert.equal(stripAccents("geografía"), "geografia");
  });
});

describe("titleSimilarity", () => {
  test("scores identical titles as a perfect match", () => {
    assert.equal(titleSimilarity("dinosaurios", "dinosaurios"), 1);
  });

  test("treats accent variants as the same topic", () => {
    assert.equal(titleSimilarity("perú", "peru"), 1);
    assert.ok(wouldOffer("perú", "peru"));
  });

  test("matches a typo in a long title", () => {
    assert.ok(wouldOffer("dinosaurios", "dinosaurios "));
    assert.ok(wouldOffer("exploracion espacial", "exploracion espaciales"));
  });

  test("matches reordered words", () => {
    assert.ok(wouldOffer("peliculas de marvel", "marvel peliculas de"));
  });

  // Regression: an edit-distance ratio on short titles put unrelated
  // topics one or two edits apart ("roma"/"rosa" scored 0.75), which
  // offered the player a completely different topic to reuse.
  test("does not match unrelated short titles", () => {
    assert.ok(!wouldOffer("roma", "rosa"));
    assert.ok(!wouldOffer("cine", "vino"));
    assert.ok(!wouldOffer("gato", "pato"));
  });

  test("still matches unrelated-length titles by shared words", () => {
    assert.ok(wouldOffer("roma", "roma"));
  });

  test("does not match entirely different topics", () => {
    assert.ok(!wouldOffer("antiguo egipto", "formula uno"));
  });
});

describe("aiTopicPoolId", () => {
  test("is deterministic for the same title and language", () => {
    assert.equal(
      aiTopicPoolId("dinosaurios", "es"), aiTopicPoolId("dinosaurios", "es")
    );
  });

  test("separates the same title across languages", () => {
    assert.notEqual(
      aiTopicPoolId("dinosaurios", "es"), aiTopicPoolId("dinosaurios", "en")
    );
  });

  test("defaults any non-English language code to Spanish", () => {
    assert.equal(aiTopicPoolId("dinosaurios", undefined), "es__dinosaurios");
    assert.equal(aiTopicPoolId("dinosaurios", "pt"), "es__dinosaurios");
  });

  test("collapses accents and punctuation into one id", () => {
    assert.equal(
      aiTopicPoolId("perú", "es"), aiTopicPoolId("peru", "es")
    );
    assert.equal(aiTopicPoolId("formula 1", "es"), "es__formula-1");
  });

  test("falls back to a placeholder when nothing survives slugging", () => {
    assert.equal(aiTopicPoolId("!!!", "es"), "es__topic");
  });
});
