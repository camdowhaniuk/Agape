/// Service to manage Bible navigation history across widget rebuilds
class BibleNavigationService {
  static final BibleNavigationService instance = BibleNavigationService._();
  BibleNavigationService._();

  final List<BibleLocation> _history = [];
  static const int _maxHistorySize = 50;
  bool _isNavigatingBack = false;

  bool get canGoBack => _history.isNotEmpty;
  bool get isNavigatingBack => _isNavigatingBack;

  void pushHistory({
    required String book,
    required int chapter,
    int? verse,
    double scrollAlignment = 0.0,
  }) {
    if (_isNavigatingBack) return;

    final location = BibleLocation(
      book: book,
      chapter: chapter,
      verse: verse,
      scrollAlignment: scrollAlignment,
    );

    // Don't add duplicate consecutive entries
    if (_history.isNotEmpty && _history.last == location) {
      return;
    }

    _history.add(location);

    // Maintain max size
    if (_history.length > _maxHistorySize) {
      _history.removeAt(0);
    }
  }

  BibleLocation? popHistory() {
    if (_history.isEmpty) return null;
    return _history.removeLast();
  }

  void setNavigatingBack(bool value) {
    _isNavigatingBack = value;
  }

  void clear() {
    _history.clear();
    _isNavigatingBack = false;
  }
}

class BibleLocation {
  const BibleLocation({
    required this.book,
    required this.chapter,
    this.verse,
    this.scrollAlignment = 0.0,
  });

  final String book;
  final int chapter;
  final int? verse;
  final double scrollAlignment;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BibleLocation &&
          runtimeType == other.runtimeType &&
          book == other.book &&
          chapter == other.chapter &&
          verse == other.verse;

  @override
  int get hashCode => Object.hash(book, chapter, verse);
}
