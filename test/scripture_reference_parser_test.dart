import 'package:flutter_test/flutter_test.dart';

import 'package:agape/utils/scripture_reference.dart';

void main() {
  group('ScriptureReferenceParser trailing references', () {
    test('captures trailing chapter references sharing the book', () {
      const text = 'Jesus warned in Matthew 5:22, 10:28 about judgment.';
      final matches = ScriptureReferenceParser.extractMatches(text);
      expect(matches, hasLength(2));

      expect(matches[0].reference.book, 'Matthew');
      expect(matches[0].reference.chapter, 5);
      expect(matches[0].reference.verse, 22);

      expect(matches[1].reference.book, 'Matthew');
      expect(matches[1].reference.chapter, 10);
      expect(matches[1].reference.verse, 28);
      expect(matches[1].matchedText.trim(), '10:28');
    });

    test('captures trailing chapter changes separated by semicolons', () {
      const text = 'Consider John 3:16; 4:24 for context.';
      final matches = ScriptureReferenceParser.extractMatches(text);
      expect(matches, hasLength(2));

      expect(matches[0].reference.book, 'John');
      expect(matches[0].reference.chapter, 3);
      expect(matches[0].reference.verse, 16);

      expect(matches[1].reference.book, 'John');
      expect(matches[1].reference.chapter, 4);
      expect(matches[1].reference.verse, 24);
      expect(matches[1].matchedText.trim(), '4:24');
    });

    test('extract keeps compatibility with extracted list for verse ranges', () {
      const text = 'Look at Matthew 5:22, 23-24.';
      final refs = ScriptureReferenceParser.extract(text);
      expect(refs, hasLength(2));
      expect(refs[0].chapter, 5);
      expect(refs[0].verse, 22);
      expect(refs[1].chapter, 5);
      expect(refs[1].verse, 23);
      expect(refs[1].endVerse, 24);
    });

    test('does not duplicate numbered books like 1 John', () {
      const text = 'Victory is promised in 1 John 5:4-5.';
      final matches = ScriptureReferenceParser.extractMatches(text);
      expect(matches, hasLength(1));
      expect(matches.first.reference.book, '1 John');
      expect(matches.first.reference.chapter, 5);
      expect(matches.first.reference.verse, 4);
      expect(matches.first.reference.endVerse, 5);

      final refs = ScriptureReferenceParser.extract(text);
      expect(refs, hasLength(1));
      expect(refs.first.book, '1 John');
    });
  });
}
