import '../data/verse_of_the_day_verses.dart';
import '../services/bible_service.dart';

/// Model for Verse of the Day data
class DailyVerse {
  const DailyVerse({
    required this.book,
    required this.chapter,
    required this.verse,
    required this.text,
  });

  final String book;
  final int chapter;
  final int verse;
  final String text;

  String get reference => '$book $chapter:$verse';
}

/// Service to manage Verse of the Day functionality
class VerseOfTheDayService {
  static final VerseOfTheDayService instance = VerseOfTheDayService._();
  VerseOfTheDayService._();

  final BibleService _bibleService = BibleService();

  /// Get today's verse based on deterministic daily rotation
  /// Uses day of year to ensure same verse for all users on same day
  Future<DailyVerse?> getTodaysVerse() async {
    try {
      final now = DateTime.now();
      final dayOfYear = _getDayOfYear(now);

      // Deterministic rotation: day of year modulo verse count
      final verseIndex = dayOfYear % VerseOfTheDayData.verses.length;
      final verseData = VerseOfTheDayData.verses[verseIndex];

      final book = verseData['book'] as String;
      final chapter = verseData['chapter'] as int;
      final verseNumber = verseData['verse'] as int;

      // Fetch the verse text from BibleService
      final chapterData = await _bibleService.fetchChapter(book, chapter);
      if (chapterData == null) return null;

      // Find the specific verse
      final verseMap = chapterData.firstWhere(
        (v) => (v['verse'] as num).toInt() == verseNumber,
        orElse: () => <String, dynamic>{},
      );

      if (verseMap.isEmpty) return null;

      final text = verseMap['text'] as String? ?? '';
      if (text.isEmpty) return null;

      return DailyVerse(
        book: book,
        chapter: chapter,
        verse: verseNumber,
        text: text,
      );
    } catch (e) {
      // Return null on error - caller can handle gracefully
      return null;
    }
  }

  /// Calculate day of year (1-366)
  int _getDayOfYear(DateTime date) {
    final startOfYear = DateTime(date.year, 1, 1);
    final difference = date.difference(startOfYear);
    return difference.inDays + 1; // +1 because Jan 1 = day 1, not day 0
  }

  /// Get verse for a specific date (useful for testing)
  Future<DailyVerse?> getVerseForDate(DateTime date) async {
    final dayOfYear = _getDayOfYear(date);
    final verseIndex = dayOfYear % VerseOfTheDayData.verses.length;
    final verseData = VerseOfTheDayData.verses[verseIndex];

    final book = verseData['book'] as String;
    final chapter = verseData['chapter'] as int;
    final verseNumber = verseData['verse'] as int;

    try {
      final chapterData = await _bibleService.fetchChapter(book, chapter);
      if (chapterData == null) return null;

      final verseMap = chapterData.firstWhere(
        (v) => (v['verse'] as num).toInt() == verseNumber,
        orElse: () => <String, dynamic>{},
      );

      if (verseMap.isEmpty) return null;

      final text = verseMap['text'] as String? ?? '';
      if (text.isEmpty) return null;

      return DailyVerse(
        book: book,
        chapter: chapter,
        verse: verseNumber,
        text: text,
      );
    } catch (e) {
      return null;
    }
  }
}
