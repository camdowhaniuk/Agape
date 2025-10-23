// lib/services/bible_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'usfm_utils.dart';

/// Hybrid Bible service for WEB:
/// 1) Tries bundled assets: assets/web/metadata.json + assets/web/books/<Book>.json
/// 2) If missing, fetches from bible-api.com (WEB) and caches per-chapter JSON
///    to <app-docs>/web_cache/<Book>/<chapter>.json for offline use.
class BibleService {
  BibleService({this.translationId = 'web'});
  final String translationId;

  List<String>? _booksCache;
  final Map<String, int> _chapterCountCache = {};
  Directory? _cacheDir;

  // -------- Red-letter support (verse-level ranges) --------
  bool _redLoaded = false;
  final Map<String, Map<int, Set<int>>> _redVerses = {};

  Future<void> loadRedLetterRanges() async {
    if (_redLoaded) return;
    Future<void> mergeFromAsset(String path) async {
      try {
        final raw = await rootBundle.loadString(path);
        final data = json.decode(raw) as Map<String, dynamic>;
        data.forEach((book, chapters) {
          final byChapter = _redVerses.putIfAbsent(book, () => <int, Set<int>>{});
          (chapters as Map<String, dynamic>).forEach((chStr, items) {
            final ch = int.tryParse(chStr);
            if (ch == null) return;
            final verses = byChapter.putIfAbsent(ch, () => <int>{});
            for (final item in (items as List)) {
              if (item is int) {
                verses.add(item);
              } else if (item is String) {
                final m = RegExp(r'^(\d+)\s*[-–]\s*(\d+)$').firstMatch(item);
                if (m != null) {
                  final a = int.parse(m.group(1)!);
                  final b = int.parse(m.group(2)!);
                  final start = a <= b ? a : b;
                  final end = a <= b ? b : a;
                  for (var v = start; v <= end; v++) {
                    verses.add(v);
                  }
                } else {
                  final n = int.tryParse(item);
                  if (n != null) verses.add(n);
                }
              }
            }
          });
        });
      } catch (_) {
        // ignore missing/invalid asset
      }
    }

    await mergeFromAsset('assets/redletter_ranges.json');
    // Optional extended ranges file; merge if present
    await mergeFromAsset('assets/redletter_ranges_extended.json');
    await mergeFromAsset('assets/redletter_ranges_extra.json');
    _redLoaded = true;
  }

  Set<int> redVersesFor(String book, int chapter) {
    final byChapter = _redVerses[book];
    if (byChapter == null) return const <int>{} ;
    return byChapter[chapter] ?? const <int>{};
  }

  Future<Directory> _getCacheDir() async {
    if (_cacheDir != null) return _cacheDir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/web_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  // ---------- BOOKS / METADATA ----------
  Future<List<String>> getBooks() async {
    // First: try assets metadata.json
    try {
      final metaStr = await rootBundle.loadString('assets/web/metadata.json');
      final meta = json.decode(metaStr) as Map<String, dynamic>;
      final books = (meta['books'] as List)
          .map((b) => (b as Map)['name'] as String)
          .toList()
          .cast<String>();
      _booksCache = books;
      for (final b in (meta['books'] as List).cast<Map>()) {
        _chapterCountCache[b['name'] as String] = (b['chapters'] as num).toInt();
      }
      return books;
    } catch (_) {
      // Fall back to standard 66-book list + chapter counts
      const data = <Map<String, dynamic>>[
        {"name":"Genesis","chapters":50},{"name":"Exodus","chapters":40},{"name":"Leviticus","chapters":27},{"name":"Numbers","chapters":36},{"name":"Deuteronomy","chapters":34},
        {"name":"Joshua","chapters":24},{"name":"Judges","chapters":21},{"name":"Ruth","chapters":4},{"name":"1 Samuel","chapters":31},{"name":"2 Samuel","chapters":24},
        {"name":"1 Kings","chapters":22},{"name":"2 Kings","chapters":25},{"name":"1 Chronicles","chapters":29},{"name":"2 Chronicles","chapters":36},
        {"name":"Ezra","chapters":10},{"name":"Nehemiah","chapters":13},{"name":"Esther","chapters":10},{"name":"Job","chapters":42},{"name":"Psalms","chapters":150},
        {"name":"Proverbs","chapters":31},{"name":"Ecclesiastes","chapters":12},{"name":"Song of Solomon","chapters":8},{"name":"Isaiah","chapters":66},
        {"name":"Jeremiah","chapters":52},{"name":"Lamentations","chapters":5},{"name":"Ezekiel","chapters":48},{"name":"Daniel","chapters":12},{"name":"Hosea","chapters":14},
        {"name":"Joel","chapters":3},{"name":"Amos","chapters":9},{"name":"Obadiah","chapters":1},{"name":"Jonah","chapters":4},{"name":"Micah","chapters":7},
        {"name":"Nahum","chapters":3},{"name":"Habakkuk","chapters":3},{"name":"Zephaniah","chapters":3},{"name":"Haggai","chapters":2},{"name":"Zechariah","chapters":14},
        {"name":"Malachi","chapters":4},
        {"name":"Matthew","chapters":28},{"name":"Mark","chapters":16},{"name":"Luke","chapters":24},{"name":"John","chapters":21},{"name":"Acts","chapters":28},
        {"name":"Romans","chapters":16},{"name":"1 Corinthians","chapters":16},{"name":"2 Corinthians","chapters":13},{"name":"Galatians","chapters":6},
        {"name":"Ephesians","chapters":6},{"name":"Philippians","chapters":4},{"name":"Colossians","chapters":4},{"name":"1 Thessalonians","chapters":5},
        {"name":"2 Thessalonians","chapters":3},{"name":"1 Timothy","chapters":6},{"name":"2 Timothy","chapters":4},{"name":"Titus","chapters":3},
        {"name":"Philemon","chapters":1},{"name":"Hebrews","chapters":13},{"name":"James","chapters":5},{"name":"1 Peter","chapters":5},{"name":"2 Peter","chapters":3},
        {"name":"1 John","chapters":5},{"name":"2 John","chapters":1},{"name":"3 John","chapters":1},{"name":"Jude","chapters":1},{"name":"Revelation","chapters":22},
      ];
      final books = <String>[];
      for (final m in data) {
        books.add(m["name"] as String);
        _chapterCountCache[m["name"] as String] = m["chapters"] as int;
      }
      _booksCache = books;
      return books;
    }
  }

  Future<int> getChapterCount(String book) async {
    if (_chapterCountCache.containsKey(book)) return _chapterCountCache[book]!;
    await getBooks();
    return _chapterCountCache[book] ?? 1;
  }

  // ---------- CHAPTER FETCH ----------
  Future<List<Map<String, dynamic>>?> fetchChapter(String book, int chapter) async {
    // 0) Try USFM WoC asset first for exact red-letter
    final usfm = await _fetchChapterFromUSFM(book, chapter);
    if (usfm != null) return usfm;

    // 1) Try assets/books/<Book>.json
    final assetPath = 'assets/web/books/$book.json';
    try {
      final raw = await rootBundle.loadString(assetPath);
      final parsed = json.decode(raw) as Map<String, dynamic>;
      final ch = (parsed['chapters'] as Map<String, dynamic>)['$chapter'] as List?;
      if (ch != null) {
        return ch.map<Map<String, dynamic>>((v) => {
          'verse': (v['verse'] as num).toInt(),
          'text': v['text'] as String,
          'html': v['html'],
          'osis': v['osis'],
        }).toList();
      }
    } catch (_) {
      // asset missing → continue to cache/network
    }

    // 2) Try cached file in documents dir
    final cacheDir = await _getCacheDir();
    final file = File('${cacheDir.path}/$book/$chapter.json');
    if (await file.exists()) {
      final parsed = json.decode(await file.readAsString());
      return (parsed as List).cast<Map>().map<Map<String, dynamic>>((v) => {
        'verse': (v['verse'] as num).toInt(),
        'text': v['text'] as String,
        'html': v['html'],
        'osis': v['osis'],
      }).toList();
    }

    // 3) Fetch from bible-api.com (WEB) and cache
    final ref = Uri.encodeComponent('$book $chapter');
    final url = Uri.parse('https://bible-api.com/$ref?translation=$translationId');
    final res = await http.get(url);
    if (res.statusCode == 200) {
      final data = json.decode(res.body) as Map<String, dynamic>;
      final verses = (data['verses'] as List).map<Map<String, dynamic>>((v) => {
        'verse': (v['verse'] as num).toInt(),
        'text': v['text'] as String,
        'html': null,
        'osis': null,
      }).toList();

      // write cache
      final dir = Directory('${cacheDir.path}/$book');
      if (!await dir.exists()) await dir.create(recursive: true);
      await file.writeAsString(json.encode(verses));

      return verses;
    }

    return null;
  }

  // ---- USFM (Words of Christ) parsing ----
  Future<List<Map<String, dynamic>>?> _fetchChapterFromUSFM(String book, int chapter) async {
    final asset = 'assets/web_woc/$book.usfm';
    String raw;
    try {
      raw = await rootBundle.loadString(asset);
    } catch (_) {
      return null; // asset not present
    }

    int curChapter = 0;
    int curVerse = 0;
    bool inWj = false;
    final Map<int, _VerseAccumulator> verseMap = {};

    _VerseAccumulator accForCurrentVerse() {
      return verseMap.putIfAbsent(curVerse, () => _VerseAccumulator());
    }

    void pushSpace() {
      if (curChapter != chapter || curVerse <= 0) return;
      final acc = accForCurrentVerse();
      acc.appendSpace(inWj);
    }

    void pushTextChunk(String chunk, {bool? overrideWj}) {
      if (curChapter != chapter || curVerse <= 0) return;
      if (chunk.isEmpty) return;
      final normalized = chunk.replaceAll('\r', ' ').replaceAll('\n', ' ');
      for (final match in RegExp(r'\s+|\S+').allMatches(normalized)) {
        final piece = match.group(0)!;
        if (piece.trim().isEmpty) {
          pushSpace();
        } else {
          final acc = accForCurrentVerse();
          acc.appendRaw(piece, overrideWj ?? inWj);
        }
      }
    }

    final length = raw.length;
    int index = 0;

    while (index < length) {
      final char = raw[index];
      if (char == '\\') {
        int j = index + 1;
        while (j < length && RegExp(r'[A-Za-z+*]').hasMatch(raw[j])) {
          j++;
        }
        if (j >= length) {
          break;
        }
        final tag = raw.substring(index + 1, j);
        int k = j;
        while (k < length && raw[k] == ' ') {
          k++;
        }

        String readNumber() {
          int m = k;
          while (m < length && RegExp(r'[0-9]').hasMatch(raw[m])) {
            m++;
          }
          final numStr = raw.substring(k, m);
          index = m;
          return numStr;
        }

        if (tag == 'c') {
          final numStr = readNumber();
          final parsed = int.tryParse(numStr);
          if (parsed != null) {
            curChapter = parsed;
            curVerse = 0;
          }
          continue;
        }

        if (tag == 'v') {
          final numStr = readNumber();
          final parsed = int.tryParse(numStr);
          if (parsed != null) {
            curVerse = parsed;
          }
          continue;
        }

        if (tag == 'wj') {
          inWj = true;
          index = k;
          continue;
        }
        if (tag == 'wj*') {
          inWj = false;
          index = k;
          continue;
        }

        if (tag == 'p' || tag == 'q' || tag == 'qs') {
          pushSpace();
          index = k;
          continue;
        }

        if (tag == 'f') {
          // Skip footnotes (\f)
          final closingTag = '\\f*';
          final closing = raw.indexOf(closingTag, k);
          if (closing == -1) {
            index = length;
          } else {
            index = closing + closingTag.length;
          }
          continue;
        }

        if (tag == 'x') {
          // Extract cross-references (\x ... \xt ... \x*)
          final closingTag = '\\x*';
          final closing = raw.indexOf(closingTag, k);
          if (closing == -1) {
            index = length;
            continue;
          }

          // Extract the content between \x and \x*
          final xContent = raw.substring(k, closing);

          // Look for \xt tag which contains the actual reference text
          final xtMatch = RegExp(r'\\xt\s+(.+?)(?=\\|$)').firstMatch(xContent);
          if (xtMatch != null && curChapter == chapter && curVerse > 0) {
            final referenceText = xtMatch.group(1)?.trim() ?? '';
            if (referenceText.isNotEmpty) {
              final acc = accForCurrentVerse();
              acc.addCrossReference(referenceText);
            }
          }

          index = closing + closingTag.length;
          continue;
        }

        if (tag == 'w' || tag == '+w') {
          final closingTag = '\\$tag*';
          final closeIndex = raw.indexOf(closingTag, k);
          if (closeIndex == -1) {
            index = length;
            continue;
          }
          final content = raw.substring(k, closeIndex);
          final cleaned = cleanUsfmWord(content);
          pushTextChunk(cleaned, overrideWj: inWj);
          index = closeIndex + closingTag.length;
          continue;
        }

        // Skip other tags without content.
        index = k;
      } else if (char == ' ' || char == '\t') {
        pushSpace();
        index++;
      } else if (char == '\n') {
        pushSpace();
        index++;
      } else if (char == '\r') {
        index++;
      } else {
        int nextSlash = raw.indexOf('\\', index);
        if (nextSlash == -1) nextSlash = length;
        final textChunk = raw.substring(index, nextSlash);
        pushTextChunk(textChunk);
        index = nextSlash;
      }
    }

    if (verseMap.isEmpty) return null;
    final verses = <Map<String, dynamic>>[];
    final keys = verseMap.keys.toList()..sort();
    for (final verseNumber in keys) {
      final acc = verseMap[verseNumber]!;
      final normalizedText = acc.buildText();
      verses.add({
        'verse': verseNumber,
        'text': normalizedText,
        'segments': acc.segments
            .map((seg) => {
                  'text': seg.text.toString(),
                  'wj': seg.isWj,
                })
            .toList(),
        'crossReferences': acc.crossReferences,
      });
    }
    return verses;
  }
}

class _Seg {
  _Seg(this.text, this.isWj);
  final StringBuffer text;
  final bool isWj;
}

class _VerseAccumulator {
  final StringBuffer buffer = StringBuffer();
  final List<_Seg> segments = <_Seg>[];
  final List<String> crossReferences = <String>[];
  bool _lastWasSpace = true;

  void appendRaw(String value, bool isWj) {
    if (value.isEmpty) return;
    buffer.write(value);
    _lastWasSpace = value.trim().isEmpty ? true : value.endsWith(' ');
    if (segments.isNotEmpty && segments.last.isWj == isWj) {
      segments.last.text.write(value);
    } else {
      segments.add(_Seg(StringBuffer(value), isWj));
    }
  }

  void appendSpace(bool isWj) {
    if (_lastWasSpace) return;
    buffer.write(' ');
    _lastWasSpace = true;
    if (segments.isNotEmpty && segments.last.isWj == isWj) {
      segments.last.text.write(' ');
    } else {
      segments.add(_Seg(StringBuffer(' '), isWj));
    }
  }

  void addCrossReference(String reference) {
    if (reference.isNotEmpty) {
      crossReferences.add(reference);
    }
  }

  void removeTrailingText(String textToRemove) {
    if (textToRemove.isEmpty) return;

    // Remove from buffer
    final bufferContent = buffer.toString();
    if (bufferContent.endsWith(textToRemove)) {
      buffer.clear();
      buffer.write(bufferContent.substring(0, bufferContent.length - textToRemove.length));
    }

    // Remove from segments
    int remaining = textToRemove.length;
    while (remaining > 0 && segments.isNotEmpty) {
      final lastSeg = segments.last;
      final segText = lastSeg.text.toString();
      if (segText.length <= remaining) {
        remaining -= segText.length;
        segments.removeLast();
      } else {
        // Partial removal from last segment
        final newText = segText.substring(0, segText.length - remaining);
        lastSeg.text.clear();
        lastSeg.text.write(newText);
        remaining = 0;
      }
    }

    // Update _lastWasSpace flag
    if (buffer.isEmpty) {
      _lastWasSpace = true;
    } else {
      final content = buffer.toString();
      _lastWasSpace = content.isEmpty || content.endsWith(' ');
    }
  }

  String buildText() {
    var text = buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    // Remove footnote/cross-reference markers (standalone numbers or symbols)
    // Pattern: space followed by single digit/symbol followed by space or end of string
    text = text.replaceAll(RegExp(r'\s+[+\-*0-9](\s+|$)'), ' ');
    // Pattern: single digit/symbol at start followed by space
    text = text.replaceAll(RegExp(r'^[+\-*0-9]\s+'), '');
    // Pattern: single digit/symbol at end preceded by space
    text = text.replaceAll(RegExp(r'\s+[+\-*0-9]$'), '');
    return text.trim();
  }
}
