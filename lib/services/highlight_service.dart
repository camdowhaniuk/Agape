import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/highlight.dart';
import 'highlight_firestore_repository.dart';

class HighlightService {
  HighlightService() {
    _setupAuthListener();
  }

  final Map<String, List<PassageHighlight>> _store = {};
  static const int _maxCustomColors = 8;
  final List<int> _customColors = [];
  File? _backingFile;
  bool _loaded = false;
  final HighlightFirestoreRepository _firestoreRepo = HighlightFirestoreRepository();
  String? _currentUserId;

  Future<void> ensureLoaded() async {
    if (_loaded) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // No user logged in - try to load from local file for backward compatibility
      await _loadFromLocalFile();
    } else {
      // User logged in - load from Firestore
      try {
        final highlights = await _firestoreRepo.loadHighlights(user.uid);
        _store.clear();
        _store.addAll(highlights);

        final customColors = await _firestoreRepo.loadCustomColors(user.uid);
        _customColors.clear();
        _customColors.addAll(customColors);

        if (_customColors.isEmpty) {
          _backfillCustomColors();
        }

        // If Firestore is empty but we have local highlights, migrate them
        if (_store.isEmpty) {
          await _migrateLocalHighlightsIfNeeded(user.uid);
        }
      } catch (e) {
        print('Error loading highlights from Firestore: $e');
        _store.clear();
        _customColors.clear();
      }
    }

    _loaded = true;
  }

  Future<void> _migrateLocalHighlightsIfNeeded(String userId) async {
    try {
      // Try to load from local file
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/highlights.json');

      if (!await file.exists()) return;

      final raw = await file.readAsString();
      if (raw.isEmpty) return;

      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) return;

      // Parse local highlights
      final Map<String, List<PassageHighlight>> localHighlights = {};
      final highlightsNode = decoded['highlights'];

      if (highlightsNode is Map<String, dynamic>) {
        highlightsNode.forEach((rawKey, value) {
          if (value is! List) return;
          final parts = rawKey.split('|');
          if (parts.length == 2) {
            final spans = <PassageHighlight>[];
            for (final item in value) {
              if (item is Map<String, dynamic>) {
                try {
                  final parsed = PassageHighlight.fromJson(item);
                  if (parsed.portions.isNotEmpty) {
                    spans.add(parsed);
                  }
                } catch (_) {
                  continue;
                }
              }
            }
            if (spans.isNotEmpty) {
              localHighlights[rawKey] = spans;
            }
          }
        });
      }

      if (localHighlights.isEmpty) return;

      print('Migrating ${localHighlights.length} chapters of highlights to Firestore...');

      // Migrate to Firestore
      _store.clear();
      _store.addAll(localHighlights);

      // Parse custom colors
      final custom = decoded['customColors'];
      if (custom is List) {
        _customColors.clear();
        _customColors.addAll(
          custom
              .whereType<num>()
              .map((value) => value.toInt())
              .where((value) => value > 0),
        );
      }

      // Persist to Firestore
      await _persist();

      print('Migration completed successfully!');
    } catch (e) {
      print('Error migrating local highlights: $e');
    }
  }

  Future<void> _loadFromLocalFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/highlights.json');
    _backingFile = file;
    if (await file.exists()) {
      try {
        final raw = await file.readAsString();
        if (raw.isNotEmpty) {
          final decoded = json.decode(raw);
          bool customColorsSeen = false;
          if (decoded is Map<String, dynamic>) {
            final highlightsNode = decoded['highlights'];
            if (highlightsNode is Map<String, dynamic>) {
              _loadHighlights(highlightsNode);
            } else if (decoded.isNotEmpty) {
              _loadHighlights(decoded);
            }
            final custom = decoded['customColors'];
            if (custom is List) {
              _customColors
                ..clear()
                ..addAll(
                  custom
                      .whereType<num>()
                      .map((value) => value.toInt())
                      .where((value) => value > 0),
                );
              customColorsSeen = true;
            }
          }
          if (!customColorsSeen) {
            _backfillCustomColors();
          }
        }
      } catch (_) {
        _store.clear();
        _customColors.clear();
      }
    } else {
      await file.create(recursive: true);
    }
  }

  Future<Map<int, List<VerseHighlight>>> highlightsFor(
    String book,
    int chapter,
  ) async {
    await ensureLoaded();
    final spans = _spansForChapter(book, chapter);
    final map = <int, List<VerseHighlight>>{};
    for (final span in spans) {
      for (final portion in _sortedPortions(span)) {
        final list = map.putIfAbsent(portion.verse, () => <VerseHighlight>[]);
        list.add(
          VerseHighlight(
            spanId: span.id,
            colorId: span.colorId,
            start: portion.start,
            end: portion.end,
            createdAt: span.createdAt,
            colorValue: span.colorValue,
          ),
        );
      }
    }
    map.forEach((_, list) => list.sort((a, b) => a.start.compareTo(b.start)));
    return map;
  }

  Future<List<VerseHighlight>> verseHighlights(
    String book,
    int chapter,
    int verse,
  ) async {
    await ensureLoaded();
    final spans = _spansForChapter(book, chapter);
    final list = <VerseHighlight>[];
    for (final span in spans) {
      for (final portion in span.portions) {
        if (portion.verse != verse) continue;
        list.add(
          VerseHighlight(
            spanId: span.id,
            colorId: span.colorId,
            start: portion.start,
            end: portion.end,
            createdAt: span.createdAt,
            colorValue: span.colorValue,
          ),
        );
      }
    }
    list.sort((a, b) => a.start.compareTo(b.start));
    return list;
  }

  Future<PassageHighlight?> highlightById(
    String book,
    int chapter,
    String spanId,
  ) async {
    await ensureLoaded();
    final spans = _spansForChapter(book, chapter);
    for (final span in spans) {
      if (span.id == spanId) return span;
    }
    return null;
  }

  Future<PassageHighlight> addHighlight({
    required String book,
    required int chapter,
    required List<HighlightPortion> portions,
    required int colorId,
    int? colorValue,
    String? excerpt,
    int? createdAt,
  }) async {
    await ensureLoaded();
    if (portions.isEmpty) {
      throw ArgumentError('Highlight portions must not be empty.');
    }
    final id = _newHighlightId();
    final span = PassageHighlight(
      id: id,
      colorId: colorId,
      colorValue: colorValue,
      createdAt: createdAt ?? DateTime.now().millisecondsSinceEpoch,
      excerpt: excerpt,
      portions: List<HighlightPortion>.from(portions),
    );
    final key = _resolveChapterKey(book, chapter);
    final list = _store.putIfAbsent(key, () => <PassageHighlight>[]);
    list.add(span);
    _ingestCustomColor(span);
    _sortChapterHighlights(list);
    await _persist();
    return span;
  }

  Future<void> updateHighlightColor({
    required String book,
    required int chapter,
    required String spanId,
    required int colorId,
    int? customColorValue,
  }) async {
    await ensureLoaded();
    final key = _resolveChapterKey(book, chapter);
    final spans = _store[key];
    if (spans == null) return;
    for (var i = 0; i < spans.length; i++) {
      final span = spans[i];
      if (span.id == spanId) {
        final updated = span.copyWith(
          colorId: colorId,
          colorValue: customColorValue,
        );
        spans[i] = updated;
        if (customColorValue != null && customColorValue > 0) {
          _addCustomColorInternal(customColorValue);
        }
        await _persist();
        return;
      }
    }
  }

  Future<void> removeHighlight({
    required String book,
    required int chapter,
    required String spanId,
  }) async {
    await ensureLoaded();
    final key = _resolveChapterKey(book, chapter);
    final spans = _store[key];
    if (spans == null) return;
    spans.removeWhere((span) => span.id == spanId);
    if (spans.isEmpty) {
      _store.remove(key);
    }
    await _persist();
  }

  List<int> get customColors {
    if (!_loaded) return const <int>[];
    return List<int>.unmodifiable(_customColors);
  }

  Future<void> addCustomColor(int colorValue) async {
    await ensureLoaded();
    if (colorValue <= 0) return;
    _addCustomColorInternal(colorValue);
    await _persist();
  }

  Future<void> clearAll() async {
    await ensureLoaded();
    _store.clear();
    _customColors.clear();
    await _persist();
  }

  Future<List<HighlightEntry>> allHighlights() async {
    await ensureLoaded();
    final entries = <HighlightEntry>[];
    _store.forEach((key, spans) {
      final parts = key.split('|');
      if (parts.length != 2) return;
      final bookKey = parts[0];
      final chapter = int.tryParse(parts[1]);
      if (chapter == null) return;
      final bookName = _formatBookName(bookKey);
      for (final span in spans) {
        entries.add(
          HighlightEntry(
            bookKey: bookKey,
            book: bookName,
            chapter: chapter,
            highlight: span,
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
      return a.startVerse.compareTo(b.startVerse);
    });

    return entries;
  }

  Future<void> removeHighlightEntry(HighlightEntry entry) async {
    await removeHighlight(
      book: entry.bookKey,
      chapter: entry.chapter,
      spanId: entry.highlight.id,
    );
  }

  Future<void> updateHighlightEntryColor(
    HighlightEntry entry,
    int newColorId, {
    int? customColorValue,
  }) async {
    await updateHighlightColor(
      book: entry.bookKey,
      chapter: entry.chapter,
      spanId: entry.highlight.id,
      colorId: newColorId,
      customColorValue: customColorValue,
    );
  }

  Future<void> _persist() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      // No user logged in - save to local file for backward compatibility
      await _persistToLocalFile();
      return;
    }

    // User logged in - save to Firestore
    try {
      // Save each chapter's highlights
      for (final entry in _store.entries) {
        await _firestoreRepo.saveChapterHighlights(
          user.uid,
          entry.key,
          entry.value,
        );
      }

      // Save custom colors
      await _firestoreRepo.saveCustomColors(user.uid, _customColors);
    } catch (e) {
      print('Error persisting highlights to Firestore: $e');
    }
  }

  Future<void> _persistToLocalFile() async {
    final file = _backingFile;
    if (file == null) return;
    final highlightsPayload = <String, dynamic>{};
    _store.forEach((key, spans) {
      highlightsPayload[key] = spans.map((span) => span.toJson()).toList();
    });
    final payload = <String, dynamic>{
      'highlights': highlightsPayload,
      'customColors': _customColors,
    };
    await file.writeAsString(json.encode(payload));
  }

  void _loadHighlights(Map<String, dynamic> source) {
    _store.clear();
    source.forEach((rawKey, value) {
      if (value is! List) return;
      final parts = rawKey.split('|');
      if (parts.length == 2) {
        final spans = <PassageHighlight>[];
        for (final item in value) {
          if (item is Map<String, dynamic>) {
            try {
              final parsed = PassageHighlight.fromJson(item);
              if (parsed.portions.isNotEmpty) {
                spans.add(parsed);
              }
            } catch (_) {
              continue;
            }
          } else if (item is Map) {
            try {
              final parsed = PassageHighlight.fromJson(
                item.cast<String, dynamic>(),
              );
              if (parsed.portions.isNotEmpty) {
                spans.add(parsed);
              }
            } catch (_) {
              continue;
            }
          }
        }
        if (spans.isNotEmpty) {
          _store[rawKey] = spans;
        }
        return;
      }

      if (parts.length == 3) {
        final book = parts[0];
        final chapter = int.tryParse(parts[1]);
        final verse = int.tryParse(parts[2]);
        if (chapter == null || verse == null) return;
        final chapterKey = '$book|$chapter';
        final spans = _store.putIfAbsent(
          chapterKey,
          () => <PassageHighlight>[],
        );
        for (final item in value) {
          if (item is! Map) continue;
          final map = item.cast<String, dynamic>();
          try {
            final colorId = (map['colorId'] as num).toInt();
            final start = (map['start'] as num).toInt();
            final end = (map['end'] as num).toInt();
            final createdAt = (map['createdAt'] as num?)?.toInt();
            final colorValue = (map['colorValue'] as num?)?.toInt();
            final excerpt = map['text'] as String?;
            if (end <= start) continue;
            final spanId =
                (map['spanId'] as String?) ??
                'legacy_${book}_${chapter}_${verse}_${start}_${end}_${createdAt ?? 0}';
            spans.add(
              PassageHighlight(
                id: spanId,
                colorId: colorId,
                colorValue: colorValue,
                createdAt: createdAt,
                excerpt: excerpt,
                portions: [
                  HighlightPortion(verse: verse, start: start, end: end),
                ],
              ),
            );
          } catch (_) {
            continue;
          }
        }
      }
    });

    if (_store.isEmpty) return;
    _mergeDuplicateChapterKeys();
    _store.values.forEach(_sortChapterHighlights);
  }

  List<PassageHighlight> _spansForChapter(String book, int chapter) {
    final key = _resolveChapterKey(book, chapter);
    return List<PassageHighlight>.from(
      _store[key] ?? const <PassageHighlight>[],
    );
  }

  List<HighlightPortion> _sortedPortions(PassageHighlight span) {
    final portions = List<HighlightPortion>.from(span.portions);
    portions.sort((a, b) {
      if (a.verse != b.verse) return a.verse.compareTo(b.verse);
      return a.start.compareTo(b.start);
    });
    return portions;
  }

  void _sortChapterHighlights(List<PassageHighlight> spans) {
    spans.sort((a, b) {
      final aTime = a.createdAt ?? 0;
      final bTime = b.createdAt ?? 0;
      if (aTime != bTime) return bTime.compareTo(aTime);
      final aStart = _earliestPortion(a)?.verse ?? 0;
      final bStart = _earliestPortion(b)?.verse ?? 0;
      return aStart.compareTo(bStart);
    });
  }

  HighlightPortion? _earliestPortion(PassageHighlight span) {
    if (span.portions.isEmpty) return null;
    final portions = _sortedPortions(span);
    return portions.first;
  }

  void _mergeDuplicateChapterKeys() {
    final canonical = <String, String>{};
    final merged = <String, List<PassageHighlight>>{};
    _store.forEach((key, spans) {
      final normalized = key.toLowerCase();
      final canonicalKey = canonical.putIfAbsent(normalized, () => key);
      final list = merged.putIfAbsent(canonicalKey, () => <PassageHighlight>[]);
      list.addAll(spans);
    });
    if (merged.isEmpty) return;
    _store
      ..clear()
      ..addEntries(merged.entries);
  }

  String _resolveChapterKey(String book, int chapter) {
    final desired = _chapterKey(book, chapter);
    final normalized = desired.toLowerCase();
    for (final existing in _store.keys) {
      if (existing.toLowerCase() == normalized) {
        return existing;
      }
    }
    return desired;
  }

  String _chapterKey(String book, int chapter) => '$book|$chapter';

  void _ingestCustomColor(PassageHighlight span) {
    final value = span.colorValue;
    if (value != null && value > 0) {
      _addCustomColorInternal(value);
    }
  }

  void _addCustomColorInternal(int colorValue) {
    _customColors.remove(colorValue);
    _customColors.insert(0, colorValue);
    while (_customColors.length > _maxCustomColors) {
      _customColors.removeLast();
    }
  }

  void _backfillCustomColors() {
    if (_store.isEmpty) return;
    final latestByColor = <int, int>{};
    _store.forEach((_, spans) {
      for (final span in spans) {
        final value = span.colorValue;
        if (value == null || value <= 0) continue;
        final timestamp = span.createdAt ?? 0;
        final existing = latestByColor[value];
        if (existing == null || timestamp > existing) {
          latestByColor[value] = timestamp;
        }
      }
    });
    if (latestByColor.isEmpty) return;
    final ordered = latestByColor.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in ordered) {
      _addCustomColorInternal(entry.key);
    }
  }

  void _setupAuthListener() {
    FirebaseAuth.instance.authStateChanges().listen((User? user) async {
      if (user == null) {
        // User logged out - clear highlights
        _currentUserId = null;
        _store.clear();
        _customColors.clear();
        _loaded = false;
      } else if (_currentUserId != user.uid) {
        // User logged in or switched - load their highlights
        _currentUserId = user.uid;
        _store.clear();
        _customColors.clear();
        _loaded = false;
        await ensureLoaded();
      }
    });
  }

  String _newHighlightId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36);

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
    required this.highlight,
  }) : verses = _computeVerses(highlight.portions);

  final String bookKey;
  final String book;
  final int chapter;
  final PassageHighlight highlight;
  final List<int> verses;

  int get startVerse => verses.isEmpty ? 0 : verses.first;
  int get endVerse => verses.isEmpty ? 0 : verses.last;
  int get verse => startVerse;

  String get reference {
    if (verses.isEmpty) return '$book $chapter';
    if (verses.length == 1) {
      return '$book $chapter:${verses.single}';
    }
    return '$book $chapter:${verses.first}-${verses.last}';
  }

  static List<int> _computeVerses(List<HighlightPortion> portions) {
    if (portions.isEmpty) return const <int>[];
    final list = portions.map((portion) => portion.verse).toList()
      ..sort((a, b) => a.compareTo(b));
    final deduped = <int>[];
    for (final verse in list) {
      if (deduped.isEmpty || deduped.last != verse) {
        deduped.add(verse);
      }
    }
    return deduped;
  }
}
