class ScriptureReference {
  const ScriptureReference({
    required this.book,
    required this.chapter,
    this.verse,
    this.endVerse,
  });

  final String book;
  final int chapter;
  final int? verse;
  final int? endVerse;

  String get display {
    if (verse == null) {
      return '$book $chapter';
    }
    if (endVerse != null && endVerse != verse) {
      return '$book $chapter:${verse!}–$endVerse';
    }
    return '$book $chapter:${verse!}';
  }
}

class ScriptureReferenceMatch {
  const ScriptureReferenceMatch({
    required this.reference,
    required this.start,
    required this.end,
    required this.matchedText,
  });

  final ScriptureReference reference;
  final int start;
  final int end;
  final String matchedText;
}

class ScriptureReferenceParser {
  static final List<_BookPattern> _patterns = _buildPatterns();

  static List<ScriptureReferenceMatch> extractMatches(String text) {
    if (text.isEmpty) return const <ScriptureReferenceMatch>[];
    final matches = <ScriptureReferenceMatch>[];
    final seen = <String>{};
    String? lastBook;
    int? lastChapter;

    for (final pattern in _patterns) {
      for (final match in pattern.expression.allMatches(text)) {
        final chapterStr = match.group(1);
        if (chapterStr == null) continue;
        if (_hasNumberedPrefix(text, match.start, pattern.canonical)) {
          continue;
        }
        final chapter = int.tryParse(chapterStr);
        if (chapter == null) continue;
        final verseStr = match.group(2);
        final verse = verseStr != null ? int.tryParse(verseStr) : null;
        int? endVerse;
        final endVerseStr = match.group(3);
        if (endVerseStr != null) {
          endVerse = int.tryParse(endVerseStr);
        }

        final start = match.start;
        final end = match.end;
        final key = '${pattern.canonical}-$chapter-${verse ?? 0}-${endVerse ?? 0}-$start';
        if (!seen.add(key)) continue;

        matches.add(
          ScriptureReferenceMatch(
            reference: ScriptureReference(
              book: pattern.canonical,
              chapter: chapter,
              verse: verse,
              endVerse: endVerse,
            ),
            start: start,
            end: end,
            matchedText: text.substring(start, end),
          ),
        );

        lastBook = pattern.canonical;
        lastChapter = chapter;

        var searchIndex = end;
        while (lastBook != null && searchIndex < text.length) {
          final colonMatch = _trailingChapterPattern.firstMatch(text.substring(searchIndex));
          if (colonMatch != null) {
            final chapterValue = int.tryParse(colonMatch.group(1) ?? '');
            final verseValue = int.tryParse(colonMatch.group(2) ?? '');
            final endVerseValue = int.tryParse(colonMatch.group(3) ?? '');
            if (chapterValue == null || verseValue == null) break;

            final raw = colonMatch.group(0)!;
            final trimmed = raw.replaceFirst(RegExp(r'^[\s,;]+'), '');
            final refStart = searchIndex + raw.length - trimmed.length;
            final refEnd = searchIndex + colonMatch.end;
            final dedupeKey = '${lastBook!}-$chapterValue-$verseValue-${endVerseValue ?? 0}-$refStart';
            if (seen.add(dedupeKey)) {
              matches.add(
                ScriptureReferenceMatch(
                  reference: ScriptureReference(
                    book: lastBook!,
                    chapter: chapterValue,
                    verse: verseValue,
                    endVerse: endVerseValue,
                  ),
                  start: refStart,
                  end: refEnd,
                  matchedText: text.substring(refStart, refEnd),
                ),
              );
            }

            lastChapter = chapterValue;
            searchIndex += colonMatch.end;
            continue;
          }

          final verseMatch = _trailingVersePattern.firstMatch(text.substring(searchIndex));
          if (verseMatch == null || lastChapter == null) {
            break;
          }

          final verseOnlyValue = int.tryParse(verseMatch.group(1) ?? '');
          final endVerseOnlyValue = int.tryParse(verseMatch.group(2) ?? '');
          if (verseOnlyValue == null) break;

          final raw = verseMatch.group(0)!;
          final trimmed = raw.replaceFirst(RegExp(r'^[\s,;]+'), '');
          final refStart = searchIndex + raw.length - trimmed.length;
          final refEnd = searchIndex + verseMatch.end;
          final dedupeKey = '${lastBook!}-${lastChapter!}-$verseOnlyValue-${endVerseOnlyValue ?? 0}-$refStart';
          if (seen.add(dedupeKey)) {
            matches.add(
              ScriptureReferenceMatch(
                reference: ScriptureReference(
                  book: lastBook!,
                  chapter: lastChapter!,
                  verse: verseOnlyValue,
                  endVerse: endVerseOnlyValue,
                ),
                start: refStart,
                end: refEnd,
                matchedText: text.substring(refStart, refEnd),
              ),
            );
          }

          searchIndex += verseMatch.end;
        }
      }
    }

    matches.sort((a, b) => a.start.compareTo(b.start));
    return matches;
  }

  static List<ScriptureReference> extract(String text) {
    return extractMatches(text)
        .map((match) => match.reference)
        .toList(growable: false);
  }

  static List<_BookPattern> _buildPatterns() {
    const books = <List<String>>[
      ['Genesis'],
      ['Exodus'],
      ['Leviticus'],
      ['Numbers'],
      ['Deuteronomy'],
      ['Joshua'],
      ['Judges'],
      ['Ruth'],
      ['1 Samuel', 'First Samuel'],
      ['2 Samuel', 'Second Samuel'],
      ['1 Kings', 'First Kings'],
      ['2 Kings', 'Second Kings'],
      ['1 Chronicles', 'First Chronicles'],
      ['2 Chronicles', 'Second Chronicles'],
      ['Ezra'],
      ['Nehemiah'],
      ['Esther'],
      ['Job'],
      ['Psalms', 'Psalm'],
      ['Proverbs'],
      ['Ecclesiastes'],
      ['Song of Solomon', 'Song of Songs', 'Canticles'],
      ['Isaiah'],
      ['Jeremiah'],
      ['Lamentations'],
      ['Ezekiel'],
      ['Daniel'],
      ['Hosea'],
      ['Joel'],
      ['Amos'],
      ['Obadiah'],
      ['Jonah'],
      ['Micah'],
      ['Nahum'],
      ['Habakkuk'],
      ['Zephaniah'],
      ['Haggai'],
      ['Zechariah'],
      ['Malachi'],
      ['Matthew'],
      ['Mark'],
      ['Luke'],
      ['John'],
      ['Acts'],
      ['Romans'],
      ['1 Corinthians', 'First Corinthians'],
      ['2 Corinthians', 'Second Corinthians'],
      ['Galatians'],
      ['Ephesians'],
      ['Philippians'],
      ['Colossians'],
      ['1 Thessalonians', 'First Thessalonians'],
      ['2 Thessalonians', 'Second Thessalonians'],
      ['1 Timothy', 'First Timothy'],
      ['2 Timothy', 'Second Timothy'],
      ['Titus'],
      ['Philemon'],
      ['Hebrews'],
      ['James'],
      ['1 Peter', 'First Peter'],
      ['2 Peter', 'Second Peter'],
      ['1 John', 'First John'],
      ['2 John', 'Second John'],
      ['3 John', 'Third John'],
      ['Jude'],
      ['Revelation', 'Revelation of John', 'Apocalypse'],
    ];

    return books
        .expand((variants) => variants.map((name) => _BookPattern(
              canonical: variants.first,
              expression: _buildExpression(name),
            )))
        .toList(growable: false);
  }

  static RegExp _buildExpression(String name) {
    final pattern = name
        .replaceAll(RegExp(r'\s+'), r'\s+')
        .replaceAll('1', '1')
        .replaceAll('2', '2')
        .replaceAll('3', '3');
    return RegExp(
      r'\b' + pattern + r'\b\s+(\d{1,3})(?::(\d{1,3})(?:[-–](\d{1,3}))?)?',
      caseSensitive: false,
    );
  }
}

final RegExp _trailingChapterPattern = RegExp(
  r'^\s*[,;]\s*(\d{1,3}):(\d{1,3})(?:[-–](\d{1,3}))?',
);

final RegExp _trailingVersePattern = RegExp(
  r'^\s*[,;]\s*(\d{1,3})(?:[-–](\d{1,3}))?',
);

class _BookPattern {
  const _BookPattern({required this.canonical, required this.expression});
  final String canonical;
  final RegExp expression;
}

const Set<String> _booksWithNumericPrefixes = {
  'John',
};

bool _hasNumberedPrefix(String text, int start, String canonical) {
  if (!_booksWithNumericPrefixes.contains(canonical)) return false;
  var index = start - 1;
  while (index >= 0 && text.codeUnitAt(index) <= 0x20) {
    index--;
  }
  if (index < 0) return false;
  final char = text[index];
  return char == '1' || char == '2' || char == '3';
}
