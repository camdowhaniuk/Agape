import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/highlight.dart';

class HighlightService {
  HighlightService();

  final Map<String, List<VerseHighlight>> _store = {};
  File? _backingFile;
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/highlights.json');
    _backingFile = file;
    if (await file.exists()) {
      try {
        final raw = await file.readAsString();
        if (raw.isNotEmpty) {
          final decoded = json.decode(raw) as Map<String, dynamic>;
          decoded.forEach((key, value) {
            final list = (value as List)
                .map(
                  (item) => VerseHighlight.fromJson(
                    (item as Map).cast<String, dynamic>(),
                  ),
                )
                .toList();
            _store[key] = list;
          });
        }
      } catch (_) {
        _store.clear();
      }
    } else {
      await file.create(recursive: true);
    }
    _loaded = true;
  }

  String _key(String book, int chapter, int verse) {
    return '$book|$chapter|$verse';
  }

  String _legacyKey(String book, int chapter, int verse) {
    return '${book.toLowerCase()}|$chapter|$verse';
  }

  Future<Map<int, List<VerseHighlight>>> highlightsFor(
    String book,
    int chapter,
  ) async {
    await ensureLoaded();
    final map = <int, List<VerseHighlight>>{};
    _store.forEach((key, value) {
      final parts = key.split('|');
      if (parts.length != 3) return;
      final storedBook = parts[0];
      final ch = int.tryParse(parts[1]);
      final vs = int.tryParse(parts[2]);
      if (storedBook.toLowerCase() == book.toLowerCase() &&
          ch == chapter &&
          vs != null) {
        map[vs] = List<VerseHighlight>.from(value);
      }
    });
    return map;
  }

  Future<List<VerseHighlight>> verseHighlights(
    String book,
    int chapter,
    int verse,
  ) async {
    await ensureLoaded();
    final key = _key(book, chapter, verse);
    final legacy = _legacyKey(book, chapter, verse);
    final list = _store[key] ?? _store[legacy] ?? const <VerseHighlight>[];
    return List<VerseHighlight>.from(list);
  }

  Future<void> setVerseHighlights(
    String book,
    int chapter,
    int verse,
    List<VerseHighlight> highlights,
  ) async {
    await ensureLoaded();
    final key = _key(book, chapter, verse);
    final legacyKey = _legacyKey(book, chapter, verse);
    if (highlights.isEmpty) {
      _store.remove(key);
      _store.remove(legacyKey);
    } else {
      _store[key] = List<VerseHighlight>.from(highlights);
      if (legacyKey != key) {
        _store.remove(legacyKey);
      }
    }
    await _persist();
  }

  Future<void> clearAll() async {
    await ensureLoaded();
    _store.clear();
    await _persist();
  }

  Future<List<HighlightEntry>> allHighlights() async {
    await ensureLoaded();
    final entries = <HighlightEntry>[];
    _store.forEach((key, highlights) {
      final parts = key.split('|');
      if (parts.length != 3) return;
      final bookKey = parts[0];
      final chapter = int.tryParse(parts[1]);
      final verse = int.tryParse(parts[2]);
      if (chapter == null || verse == null) return;
      final bookName = _formatBookName(bookKey);
      for (final highlight in highlights) {
        entries.add(
          HighlightEntry(
            bookKey: bookKey,
            book: bookName,
            chapter: chapter,
            verse: verse,
            highlight: highlight,
          ),
        );
      }
    });

    entries.sort((a, b) {
      final aTime = a.highlight.createdAt ?? 0;
      final bTime = b.highlight.createdAt ?? 0;
      if (aTime != bTime) return bTime.compareTo(aTime);
      final bookCompare = a.book.compareTo(b.book);
      if (bookCompare != 0) return bookCompare;
      if (a.chapter != b.chapter) return a.chapter.compareTo(b.chapter);
      if (a.verse != b.verse) return a.verse.compareTo(b.verse);
      return a.highlight.start.compareTo(b.highlight.start);
    });

    return entries;
  }

  Future<void> removeHighlight(HighlightEntry entry) async {
    await ensureLoaded();
    final key = _key(entry.bookKey, entry.chapter, entry.verse);
    final legacyKey = _legacyKey(entry.bookKey, entry.chapter, entry.verse);
    final list = List<VerseHighlight>.from(
      _store[key] ?? _store[legacyKey] ?? const <VerseHighlight>[],
    );
    list.removeWhere(
      (h) =>
          h.start == entry.highlight.start &&
          h.end == entry.highlight.end &&
          (h.colorId == entry.highlight.colorId || entry.highlight.colorId == -1),
    );
    if (list.isEmpty) {
      _store.remove(key);
      _store.remove(legacyKey);
    } else {
      _store[key] = list;
      if (legacyKey != key) {
        _store.remove(legacyKey);
      }
    }
    await _persist();
  }

  Future<void> updateHighlightColor(
    HighlightEntry entry,
    int newColorId,
  ) async {
    await ensureLoaded();
    final key = _key(entry.bookKey, entry.chapter, entry.verse);
    final legacyKey = _legacyKey(entry.bookKey, entry.chapter, entry.verse);
    final list = List<VerseHighlight>.from(
      _store[key] ?? _store[legacyKey] ?? const <VerseHighlight>[],
    );
    bool updated = false;
    for (var i = 0; i < list.length; i++) {
      final h = list[i];
      if (h.start == entry.highlight.start && h.end == entry.highlight.end) {
        list[i] = h.copyWith(colorId: newColorId);
        updated = true;
        break;
      }
    }
    if (!updated) return;
    _store[key] = list;
    if (legacyKey != key) {
      _store.remove(legacyKey);
    }
    await _persist();
  }

  Future<void> _persist() async {
    final file = _backingFile;
    if (file == null) return;
    final data = <String, dynamic>{};
    _store.forEach((key, value) {
      data[key] = value.map((e) => e.toJson()).toList();
    });
    await file.writeAsString(json.encode(data));
  }

  String _formatBookName(String raw) {
    if (raw.isEmpty) return raw;
    final parts = raw.split(' ');
    return parts
        .map((part) {
          if (part.isEmpty) return part;
          if (part.length == 1) return part.toUpperCase();
          return '${part[0].toUpperCase()}${part.substring(1)}';
        })
        .join(' ')
        .replaceAll('  ', ' ')
        .trim();
  }
}

class HighlightEntry {
  HighlightEntry({
    required this.bookKey,
    required this.book,
    required this.chapter,
    required this.verse,
    required this.highlight,
  });

  final String bookKey;
  final String book;
  final int chapter;
  final int verse;
  final VerseHighlight highlight;

  String get reference => '$book $chapter:$verse';
}
