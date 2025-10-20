import 'dart:ui' show MaskFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart' show rootBundle;
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../models/highlight.dart';
import '../services/bible_service.dart';
import '../services/highlight_service.dart';
import '../services/usfm_utils.dart';
import '../services/user_state_service.dart';
import '../utils/highlight_colors.dart';
import '../widgets/header_pill.dart';

class BibleScreen extends StatefulWidget {
  const BibleScreen({
    super.key,
    this.onScrollVisibilityChange,
    this.navVisible = true,
    this.initialBook,
    this.initialChapter,
    this.initialVerse,
    this.navVisibilityResetTick = 0,
  });

  final void Function(bool)? onScrollVisibilityChange;
  final bool navVisible;
  final String? initialBook;
  final int? initialChapter;
  final int? initialVerse;
  final int navVisibilityResetTick;

  @override
  State<BibleScreen> createState() => _BibleScreenState();
}

class _BibleScreenState extends State<BibleScreen> {
  final _service = BibleService();
  final HighlightService _highlightService = HighlightService();
  final UserStateService _userStateService = UserStateService.instance;
  final ItemScrollController _itemScrollController = ItemScrollController();
  final ItemPositionsListener _itemPositionsListener =
      ItemPositionsListener.create();
  double? _lastScrollPixels;
  bool _navVisibilityArmed = false;
  bool _navVisibilityPrimed = false;
  bool _hasExplicitInitialTarget = false;

  List<String> _books = [];
  String _selectedBook = 'John';
  int _selectedChapter = 1;
  int? _selectedVerse;

  List<_ChapterRef> _chapterRefs = const [];
  final Map<String, int> _bookStartIndex = {};
  final Map<String, int> _bookChapterCounts = {};
  bool _chapterIndexReady = false;
  final Map<_ChapterRef, _ChapterState> _chapterStates = {};
  final Map<_ChapterRef, Future<_ChapterState>> _chapterLoaders = {};
  final Map<String, _USFMBookData?> _usfmBookCache = {};
  final Set<String> _missingUsfmBooks = {};

  bool _pendingInitialJump = false;
  int _initialListIndex = 0;
  String _visibleBook = 'John';
  int _visibleChapter = 1;
  bool _headerVisible = true;
  _ColorChoice _lastHighlightChoice = const _ColorChoice(paletteIndex: 0);
  List<Color> _savedCustomColors = const <Color>[];
  _HighlightDraft? _activeHighlightDraft;
  double _storedAlignment = 0.0;
  double _lastVisibleAlignment = 0.0;
  int? _storedVisibleVerse;
  int? _currentVisibleVerse;
  double? _currentVisibleAlignment;
  bool _initialViewportSettling = false;
  bool _restoringLocation = false;
  int? _restoreTargetVerse;
  double? _restoreTargetAlignment;
  bool _suppressPositionUpdates = false;

  _VisibleVerseInfo? _visibleVerseInfo(_ChapterState state) {
    final mediaTop = MediaQuery.of(context).padding.top;
    const headerPadding = 120.0;
    const sectionPadding = 24.0;
    final thresholdY = mediaTop + headerPadding + sectionPadding;
    final bool log = _restoringLocation;
    if (log) {
      debugPrint(
        '[Bible] visibleVerseInfo threshold=$thresholdY entries=${state.verseKeys.length}',
      );
    }

    final entries = state.verseKeys.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in entries) {
      final ctx = entry.value.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null ||
          !box.attached ||
          !box.hasSize ||
          box.size.height == 0) {
        continue;
      }
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      if (log) {
        debugPrint('[Bible] verse ${entry.key} top=$top bottom=$bottom');
      }
      if (bottom > thresholdY && top < thresholdY + 400) {
        final verse = entry.key;
        final alignment = ((thresholdY - top) / box.size.height).clamp(
          0.0,
          1.0,
        );
        if (log) {
          debugPrint('[Bible] choose verse=$verse alignment=$alignment');
        }
        return _VisibleVerseInfo(verse, alignment);
      }
    }
    if (entries.isEmpty) return null;
    final fallbackVerse =
        _storedVisibleVerse ?? _currentVisibleVerse ?? _selectedVerse;
    if (fallbackVerse != null && state.verseKeys.containsKey(fallbackVerse)) {
      if (log) {
        debugPrint('[Bible] fallback stored verse=$fallbackVerse');
      }
      return _VisibleVerseInfo(
        fallbackVerse,
        _currentVisibleAlignment ?? _storedAlignment,
      );
    }
    final first = entries.first;
    if (log) {
      debugPrint('[Bible] default first verse=${first.key}');
    }
    return _VisibleVerseInfo(first.key, 0.0);
  }

  final Set<String> _redLetterBooks = const {'Matthew', 'Mark', 'Luke', 'John'};
  bool _jesusSpeakingOpenQuote = false;
  final RegExp _jesusAttribution = RegExp(
    r'\bJesus\s+(said|says|answered|replied|asked|began\s+to\s+say|cried\s+out|declared|spoke)\b',
    caseSensitive: false,
  );
  final RegExp _quoteMarks = RegExp(r'["“”]');

  @override
  void initState() {
    super.initState();
    _navVisibilityPrimed = true;
    _hasExplicitInitialTarget =
        widget.initialBook != null ||
        widget.initialChapter != null ||
        widget.initialVerse != null;
    _selectedBook = widget.initialBook ?? _selectedBook;
    _selectedChapter = widget.initialChapter ?? _selectedChapter;
    _selectedVerse = widget.initialVerse;

    _itemPositionsListener.itemPositions.addListener(
      _handleItemPositionsChange,
    );
    _loadInitialData();
  }

  @override
  void didUpdateWidget(covariant BibleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.navVisibilityResetTick != oldWidget.navVisibilityResetTick) {
      _navVisibilityArmed = false;
      _navVisibilityPrimed = true;
      _lastScrollPixels = null;
      if (!_headerVisible) {
        setState(() => _headerVisible = true);
      }
    }
  }

  Widget _buildChapterItem(
    BuildContext context,
    int index,
    TextTheme textTheme,
    bool isDark,
  ) {
    final ref = _chapterRefs[index];
    _ensureChapterState(ref);
    if (index + 1 < _chapterRefs.length) {
      _ensureChapterState(_chapterRefs[index + 1]);
    }

    final state = _chapterStates[ref];
    final theme = Theme.of(context);
    final baseStyle = textTheme.bodyLarge!.copyWith(
      fontSize: 18,
      height: 1.6,
      color: isDark ? Colors.white70 : Colors.black87,
    );
    final redStyle = baseStyle.copyWith(
      color: isDark ? Colors.red[300] : Colors.red[700],
      fontWeight: FontWeight.w600,
    );

    if (state == null || state.verses == null) {
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.5,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Loading ${ref.book} ${ref.chapter}…',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    if (state.error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${ref.book} ${ref.chapter}', style: textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Unable to load this chapter.\n${state.error}',
              style: textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ),
      );
    }

    final verses = state.verses ?? const <Map<String, dynamic>>[];
    state.jesusSpeakingOpenQuote = false;
    final highlightVerse =
        (ref.book == _selectedBook && ref.chapter == _selectedChapter)
        ? _selectedVerse
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${ref.book} ${ref.chapter}',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _ChapterInlineText(
            baseStyle: baseStyle,
            redStyle: redStyle,
            verses: verses,
            verseKeys: state.verseKeys,
            selectedVerse: highlightVerse,
            selectedBook: ref.book,
            chapterState: state,
            isDark: isDark,
            book: ref.book,
            chapter: ref.chapter,
            onHighlightStart: _handleHighlightDragStart,
            onHighlightUpdate: _handleHighlightDragUpdate,
            onHighlightEnd: _handleHighlightDragEnd,
            onHighlightTap: _handleHighlightTap,
            spanBuilder:
                ({
                  required String book,
                  required String verseText,
                  required TextStyle baseStyle,
                  required TextStyle redStyle,
                  _ChapterState? chapterState,
                }) => _buildJesusRedLetterSpans(
                  book: book,
                  verseText: verseText,
                  baseStyle: baseStyle,
                  redStyle: redStyle,
                  chapterState: chapterState,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderOverlay({
    required BuildContext context,
    required String title,
    required bool isDark,
    required double topPadding,
  }) {
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, topPadding + 8, 16, 12),
        child: Align(
          alignment: Alignment.topLeft,
          child: IgnorePointer(
            ignoring: !_headerVisible,
            child: AnimatedSlide(
              offset: _headerVisible ? Offset.zero : const Offset(0, -0.35),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _headerVisible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: HeaderPill(
                  title: title,
                  isDark: isDark,
                  onTap: _showReferencePicker,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _itemPositionsListener.itemPositions.removeListener(
      _handleItemPositionsChange,
    );
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    debugPrint('[Bible] loadInitialData start');
    await _service.loadRedLetterRanges();
    await _highlightService.ensureLoaded();
    _syncSavedCustomColors();
    if (_hasExplicitInitialTarget) {
      _restoringLocation = false;
      _storedAlignment = 0.0;
      _storedVisibleVerse = null;
      _restoreTargetVerse = null;
      _restoreTargetAlignment = null;
    } else {
      _restoringLocation = await _restoreLastLocation();
    }
    await _loadBooks();
    if (_restoringLocation) {
      Future.microtask(_restoreToStoredLocation);
    }
  }

  Future<bool> _restoreLastLocation() async {
    final stored = await _userStateService.readString('bible.lastLocation');
    if (stored == null) return false;
    final parts = stored.split('|');
    if (parts.length < 3) return false;
    final book = parts[0];
    final chapter = int.tryParse(parts[1]) ?? 1;
    final verseValue = int.tryParse(parts[2]) ?? 0;
    debugPrint('[Bible] restoreLastLocation -> $stored');
    _selectedBook = book;
    _selectedChapter = chapter;
    _selectedVerse = verseValue > 0 ? verseValue : null;
    if (parts.length >= 4) {
      _storedAlignment = (double.tryParse(parts[3]) ?? 0.0).clamp(0.0, 1.0);
      _lastVisibleAlignment = _storedAlignment;
      _currentVisibleAlignment = _storedAlignment;
    }
    if (parts.length >= 5) {
      final visibleParsed = int.tryParse(parts[4]) ?? 0;
      _storedVisibleVerse = visibleParsed > 0 ? visibleParsed : null;
    }
    _currentVisibleVerse = _storedVisibleVerse ?? _selectedVerse;
    _currentVisibleAlignment = _storedAlignment;
    debugPrint(
      '[Bible] restore state -> book=$_selectedBook chapter=$_selectedChapter verse=$_selectedVerse storedAlignment=$_storedAlignment storedVisible=$_storedVisibleVerse',
    );
    _restoreTargetVerse = _storedVisibleVerse ?? _selectedVerse;
    _restoreTargetAlignment = _storedAlignment;
    return true;
  }

  Future<void> _restoreToStoredLocation() async {
    final targetVerse = _restoreTargetVerse;
    if (targetVerse == null) {
      _restoringLocation = false;
      return;
    }

    final index = chapterIndexFor(_selectedBook, _selectedChapter);
    if (index == -1) {
      _restoringLocation = false;
      return;
    }

    final ref = chapterRefForIndex(index);
    if (ref == null) {
      _restoringLocation = false;
      return;
    }

    if (!_itemScrollController.isAttached) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_itemScrollController.isAttached) return;
        _restoreToStoredLocation();
      });
      return;
    }

    _suppressPositionUpdates = true;

    // Jump immediately to the stored chapter.
    _itemScrollController.jumpTo(index: index);

    // Ensure the chapter data is loaded.
    final state = await _ensureChapterState(ref);
    if (!mounted || state.verses == null) {
      _suppressPositionUpdates = false;
      _restoringLocation = false;
      return;
    }

    final alignment = _restoreTargetAlignment ?? _storedAlignment;
    debugPrint(
      '[Bible] restore target verse=$targetVerse alignment=$alignment index=$index',
    );
    _scheduleVerseScrollForRef(
      ref,
      targetVerse,
      index: index,
      alignment: alignment.clamp(0.05, 0.95),
    );

    Future.delayed(const Duration(milliseconds: 80), () {
      if (!mounted || _restoreTargetVerse == null) return;
      final state = _chapterStates[ref];
      if (state == null) return;
      final info = _visibleVerseInfo(state);
      debugPrint(
        '[Bible] post-restore check verse=${info?.verse} align=${info?.alignment}',
      );
      if (info == null || info.verse != targetVerse) {
        _scheduleVerseScrollForRef(
          ref,
          targetVerse,
          index: index,
          alignment: alignment.clamp(0.05, 0.95),
        );
      }
      _restoreTargetVerse = null;
      _suppressPositionUpdates = false;
      _saveLastLocation(alignment: alignment);
    });

    _restoringLocation = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _armNavVisibility());
  }

  Future<void> _loadBooks() async {
    final books = await _service.getBooks();
    if (!mounted) return;
    setState(() {
      _books = books;
      if (!_books.contains(_selectedBook) && _books.isNotEmpty) {
        _selectedBook = _books.first;
        _selectedChapter = 1;
        _selectedVerse = null;
      }
    });

    await _buildChapterIndex(books);
  }

  Future<void> _buildChapterIndex(List<String> books) async {
    if (mounted) {
      setState(() {
        _chapterIndexReady = false;
      });
    }

    if (books.isEmpty) {
      if (!mounted) return;
      setState(() {
        _chapterRefs = const [];
        _bookStartIndex.clear();
        _bookChapterCounts.clear();
        _chapterIndexReady = true;
      });
      return;
    }

    final refs = <_ChapterRef>[];
    final startIndices = <String, int>{};
    final chapterCounts = <String, int>{};

    for (final book in books) {
      final count = await _service.getChapterCount(book);
      chapterCounts[book] = count;
      startIndices[book] = refs.length;
      for (var chapter = 1; chapter <= count; chapter++) {
        refs.add(_ChapterRef(book: book, chapter: chapter));
      }
    }

    if (!mounted) return;

    final selectedStart = startIndices[_selectedBook];
    final selectedCount = chapterCounts[_selectedBook];
    int initialIndex = 0;
    if (selectedStart != null && selectedCount != null) {
      final clampedChapter = _selectedChapter.clamp(1, selectedCount);
      initialIndex = selectedStart + (clampedChapter - 1);
      if (initialIndex < 0 || initialIndex >= refs.length) {
        initialIndex = 0;
      }
    }

    setState(() {
      _chapterRefs = List.unmodifiable(refs);
      _bookStartIndex
        ..clear()
        ..addAll(startIndices);
      _bookChapterCounts
        ..clear()
        ..addAll(chapterCounts);
      _initialListIndex = initialIndex;
      _visibleBook = _selectedBook;
      _visibleChapter = _selectedChapter;
      _chapterIndexReady = true;
      _pendingInitialJump = true;
      _lastVisibleAlignment = _storedAlignment;
    });

    if (_chapterRefs.isNotEmpty) {
      _ensureChapterState(_chapterRefs[_initialListIndex]);
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _jumpToInitialPosition(),
      );
    }
  }

  int chapterIndexFor(String book, int chapter) {
    final start = _bookStartIndex[book];
    final count = _bookChapterCounts[book];
    if (start == null || count == null) return -1;
    if (chapter < 1 || chapter > count) return -1;
    return start + (chapter - 1);
  }

  _ChapterRef? chapterRefForIndex(int index) {
    if (index < 0 || index >= _chapterRefs.length) return null;
    return _chapterRefs[index];
  }

  Future<_ChapterState> _ensureChapterState(_ChapterRef ref) {
    if (_chapterLoaders.containsKey(ref)) {
      return _chapterLoaders[ref]!;
    }

    final state = _chapterStates.putIfAbsent(ref, () => _ChapterState());
    if (state.verses != null || state.error != null) {
      return Future.value(state);
    }

    final future = _loadChapterState(ref, state);
    _chapterLoaders[ref] = future;
    future.whenComplete(() => _chapterLoaders.remove(ref));
    return future;
  }

  Future<_ChapterState> _loadChapterState(
    _ChapterRef ref,
    _ChapterState state,
  ) async {
    state.isLoading = true;
    try {
      final data =
          await _service.fetchChapter(ref.book, ref.chapter) ??
          <Map<String, dynamic>>[];
      state.verses = data;
      state.redVerses = _service.redVersesFor(ref.book, ref.chapter);
      state.jesusSpeakingOpenQuote = false;
      state.error = null;
      state.verseKeys
        ..clear()
        ..addEntries(
          data.map(
            (v) => MapEntry(
              (v['verse'] as num).toInt(),
              GlobalKey<_VerseInlineState>(),
            ),
          ),
        );
      final highlightMap = await _highlightService.highlightsFor(
        ref.book,
        ref.chapter,
      );
      state.highlights
        ..clear()
        ..addEntries(highlightMap.entries);
      await _applyUsfmSegments(ref, state);
    } catch (error) {
      state.error = error.toString();
    } finally {
      state.isLoading = false;
      if (mounted) setState(() {});
    }

    return state;
  }

  void _scheduleVerseScrollForRef(
    _ChapterRef ref,
    int verse, {
    int? index,
    int attempt = 0,
    double? alignment,
  }) {
    if (attempt > 8) return;
    final chapterIndex = index ?? chapterIndexFor(ref.book, ref.chapter);
    if (chapterIndex == -1) return;
    final state = _chapterStates[ref];
    if (state == null || state.verses == null) {
      _ensureChapterState(ref).then((_) {
        if (!mounted) return;
        _scheduleVerseScrollForRef(
          ref,
          verse,
          index: chapterIndex,
          attempt: attempt + 1,
          alignment: alignment,
        );
      });
      return;
    }

    final key = state.verseKeys[verse];
    final context = key?.currentContext;
    if (context != null) {
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: alignment ?? 0.12,
      );
      return;
    }

    Future.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      _scheduleVerseScrollForRef(
        ref,
        verse,
        index: chapterIndex,
        attempt: attempt + 1,
        alignment: alignment,
      );
    });
  }

  Future<void> _applyUsfmSegments(_ChapterRef ref, _ChapterState state) async {
    final bookData = await _ensureUsfmBookData(ref.book);
    if (bookData == null) return;
    final chapterSegments = bookData.segments[ref.chapter];
    if (chapterSegments == null) return;
    final verses = state.verses;
    if (verses == null) return;

    final redVerses = <int>{...state.redVerses};
    for (final verseMap in verses) {
      final verseNumber = (verseMap['verse'] as num?)?.toInt();
      if (verseNumber == null) continue;
      final segList = chapterSegments[verseNumber];
      if (segList == null || segList.isEmpty) continue;

      final cleanedSegments = <Map<String, dynamic>>[];
      for (final seg in segList) {
        final cleanedText = cleanUsfmWord(seg.text).trim();
        if (cleanedText.isEmpty) continue;
        cleanedSegments.add({'text': cleanedText, 'wj': seg.isWj});
      }
      if (cleanedSegments.isEmpty) continue;

      verseMap['segments'] = cleanedSegments;
      if (cleanedSegments.any((seg) => seg['wj'] == true)) {
        redVerses.add(verseNumber);
      }
    }
    final predefinedRed = bookData.redVerses[ref.chapter];
    if (predefinedRed != null) {
      redVerses.addAll(predefinedRed);
    }
    state.redVerses = redVerses;
  }

  String? _verseTextFor(_ChapterState state, int verse) {
    final verses = state.verses;
    if (verses == null) return null;
    for (final entry in verses) {
      final vNum = (entry['verse'] as num?)?.toInt();
      if (vNum == verse) {
        final text = entry['text'] as String?;
        return text?.replaceAll('\n', ' ').trim();
      }
    }
    return null;
  }

  int _clampOffset(int value, int max) {
    if (value < 0) return 0;
    if (value > max) return max;
    return value;
  }

  Future<void> _handleHighlightTap(
    String book,
    int chapter,
    int verse,
    VerseHighlight highlight,
  ) async {
    final selection = await showModalBottomSheet<_HighlightSelection>(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF121215)
          : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final isDark = theme.brightness == Brightness.dark;
        final palette = highlightPalette(isDark);
        final savedCustoms = _savedCustomColors;

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Highlight Options',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Pick a color',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withOpacity(0.7),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 70,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemBuilder: (context, index) {
                      final color = palette[index];
                      final selected =
                          highlight.colorValue == null &&
                          index == highlight.colorId;
                      return GestureDetector(
                        onTap: () => Navigator.of(
                          sheetContext,
                        ).pop(_HighlightSelection.palette(index)),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOut,
                          width: selected ? 48 : 40,
                          height: selected ? 48 : 40,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? Colors.white.withOpacity(
                                      isDark ? 0.95 : 0.85,
                                    )
                                  : Colors.black.withOpacity(
                                      isDark ? 0.4 : 0.12,
                                    ),
                              width: selected ? 2.4 : 1.4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(
                                  isDark ? 0.45 : 0.18,
                                ),
                                blurRadius: selected ? 18 : 12,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(width: 18),
                    itemCount: palette.length,
                  ),
                ),
                if (savedCustoms.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Saved colors',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.7),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 70,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemBuilder: (context, index) {
                        final color = savedCustoms[index];
                        final selected =
                            highlight.colorValue != null &&
                            highlight.colorValue == color.value;
                        return GestureDetector(
                          onTap: () => Navigator.of(sheetContext).pop(
                            _HighlightSelection.custom(
                              paletteIndex: highlight.colorId,
                              color: color,
                            ),
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            curve: Curves.easeOut,
                            width: selected ? 48 : 40,
                            height: selected ? 48 : 40,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: selected
                                    ? Colors.white.withOpacity(
                                        isDark ? 0.95 : 0.85,
                                      )
                                    : Colors.black.withOpacity(
                                        isDark ? 0.4 : 0.12,
                                      ),
                                width: selected ? 2.4 : 1.4,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(
                                    isDark ? 0.45 : 0.18,
                                  ),
                                  blurRadius: selected ? 18 : 12,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(width: 18),
                      itemCount: savedCustoms.length,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurface,
                    side: BorderSide(
                      color: theme.colorScheme.onSurface.withOpacity(
                        isDark ? 0.3 : 0.2,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                  ),
                  onPressed: () async {
                    final initialColor = highlightColorForHighlight(
                      highlight,
                      dark: isDark,
                    );
                    final custom = await _pickCustomHighlightColor(
                      sheetContext,
                      initialColor,
                      isDark,
                    );
                    if (custom != null) {
                      Navigator.of(sheetContext).pop(
                        _HighlightSelection.custom(
                          paletteIndex: highlight.colorId,
                          color: custom,
                        ),
                      );
                    }
                  },
                  icon: ShaderMask(
                    shaderCallback: (rect) => const SweepGradient(
                      colors: [
                        Color(0xFFFF5252),
                        Color(0xFFFFEB3B),
                        Color(0xFF4CAF50),
                        Color(0xFF40C4FF),
                        Color(0xFF7C4DFF),
                        Color(0xFFFF5252),
                      ],
                    ).createShader(rect),
                    child: const Icon(
                      Icons.colorize_rounded,
                      color: Colors.white,
                    ),
                  ),
                  label: const Text('Color wheel'),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Remove highlight'),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(const _HighlightSelection.delete()),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selection == null) return;

    final ref = _ChapterRef(book: book, chapter: chapter);
    final state = _chapterStates[ref];
    if (state == null) return;
    final spanId = highlight.spanId;
    final span = await _highlightService.highlightById(book, chapter, spanId);
    if (span == null) return;

    if (selection.delete) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          final verses = span.portions.map((p) => p.verse).toList()..sort();
          final reference = verses.isEmpty
              ? '$book $chapter'
              : verses.length == 1
              ? '$book $chapter:${verses.single}'
              : '$book $chapter:${verses.first}-${verses.last}';
          return AlertDialog(
            title: const Text('Remove highlight?'),
            content: Text('Delete the highlight for $reference?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('Delete'),
              ),
            ],
          );
        },
      );
      if (confirm != true) return;
      await _highlightService.removeHighlight(
        book: book,
        chapter: chapter,
        spanId: spanId,
      );
    } else {
      final paletteIndex = selection.paletteIndex ?? span.colorId;
      final customColor = selection.customColor;
      final bool colorUnchanged =
          paletteIndex == span.colorId &&
          ((customColor == null && span.colorValue == null) ||
              (customColor != null &&
                  span.colorValue != null &&
                  customColor.value == span.colorValue));
      if (colorUnchanged) return;
      await _highlightService.updateHighlightColor(
        book: book,
        chapter: chapter,
        spanId: spanId,
        colorId: paletteIndex,
        customColorValue: customColor?.value,
      );
      _lastHighlightChoice = _ColorChoice(
        paletteIndex: paletteIndex,
        customColor: customColor,
      );
    }

    await _reloadHighlightsForState(ref, state);
    _syncSavedCustomColors();
  }

  Future<Color?> _pickCustomHighlightColor(
    BuildContext context,
    Color initial,
    bool isDark,
  ) async {
    Color tempColor = initial;
    return showDialog<Color>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF121215) : Colors.white,
          title: const Text('Pick a highlight color'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return ColorPicker(
                pickerColor: tempColor,
                onColorChanged: (color) => setState(() => tempColor = color),
                enableAlpha: false,
                displayThumbColor: true,
                paletteType: PaletteType.hsvWithHue,
                pickerAreaBorderRadius: const BorderRadius.all(
                  Radius.circular(12),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(tempColor),
              child: const Text('Use color'),
            ),
          ],
        );
      },
    );
  }

  void _handleHighlightDragStart(
    String book,
    int chapter,
    int verse,
    int offset,
  ) {
    final ref = _ChapterRef(book: book, chapter: chapter);
    final state = _chapterStates[ref];
    if (state == null) return;
    final verseLength = _verseLength(state, verse);
    if (verseLength == 0) return;
    final startOffset = _clampOffset(offset, verseLength);
    final original = <int, List<VerseHighlight>>{};
    state.highlights.forEach((key, value) {
      original[key] = List<VerseHighlight>.from(value);
    });
    original.putIfAbsent(verse, () => <VerseHighlight>[]);
    _activeHighlightDraft = _HighlightDraft(
      ref: ref,
      startVerse: verse,
      startOffset: startOffset,
      originalHighlights: original,
    );
    _restoreHighlightsFromMap(state, original);
    if (mounted) setState(() {});
  }

  void _handleHighlightDragUpdate(
    String book,
    int chapter,
    int verse,
    int startOffset,
    int currentOffset,
    Offset globalPosition,
  ) {
    final draft = _activeHighlightDraft;
    if (draft == null) return;
    if (draft.ref.book != book || draft.ref.chapter != chapter) {
      return;
    }
    final state = _chapterStates[draft.ref];
    if (state == null) return;
    final target =
        _edgeForPosition(state, globalPosition) ??
        _VerseEdge(
          verse: verse,
          offset: _clampOffset(currentOffset, _verseLength(state, verse)),
        );

    draft.currentVerse = target.verse;
    draft.currentOffset = _clampOffset(
      target.offset,
      _verseLength(state, target.verse),
    );
    _applyHighlightPreview(draft, _lastHighlightChoice, state);
    if (mounted) setState(() {});
  }

  Future<void> _handleHighlightDragEnd(
    String book,
    int chapter,
    int verse,
    int startOffset,
    int endOffset,
    Offset globalPosition,
  ) async {
    final draft = _activeHighlightDraft;
    if (draft == null) return;
    if (draft.ref.book != book || draft.ref.chapter != chapter) {
      _activeHighlightDraft = null;
      return;
    }
    final state = _chapterStates[draft.ref];
    if (state == null) {
      _activeHighlightDraft = null;
      return;
    }
    final target =
        _edgeForPosition(state, globalPosition) ??
        _VerseEdge(
          verse: verse,
          offset: _clampOffset(endOffset, _verseLength(state, verse)),
        );

    draft.currentVerse = target.verse;
    draft.currentOffset = _clampOffset(
      target.offset,
      _verseLength(state, target.verse),
    );

    if (!draft.hasSelection) {
      _restoreHighlightsFromMap(state, draft.originalHighlights);
      _activeHighlightDraft = null;
      if (mounted) setState(() {});
      return;
    }

    final startEdge = draft.minEdge;
    final endEdge = draft.maxEdge;
    final choice = _lastHighlightChoice;
    final portions = <HighlightPortion>[];
    final excerptBuffer = StringBuffer();

    for (final verseNumber in _versesBetween(startEdge.verse, endEdge.verse)) {
      final verseText = _verseTextFor(state, verseNumber);
      if (verseText == null || verseText.isEmpty) continue;
      final length = verseText.length;
      var verseStart = verseNumber == startEdge.verse ? startEdge.offset : 0;
      var verseEnd = verseNumber == endEdge.verse ? endEdge.offset : length;
      verseStart = _clampOffset(verseStart, length);
      verseEnd = _clampOffset(verseEnd, length);
      if (verseEnd <= verseStart) continue;

      portions.add(
        HighlightPortion(verse: verseNumber, start: verseStart, end: verseEnd),
      );

      final excerpt = _excerptForRange(verseText, verseStart, verseEnd);
      if (excerpt != null) {
        if (excerptBuffer.isNotEmpty) excerptBuffer.write(' ');
        excerptBuffer.write(excerpt);
      }
    }

    if (portions.isEmpty) {
      _restoreHighlightsFromMap(state, draft.originalHighlights);
      _activeHighlightDraft = null;
      if (mounted) setState(() {});
      return;
    }

    try {
      final excerpt = excerptBuffer.toString().trim();
      await _highlightService.addHighlight(
        book: draft.ref.book,
        chapter: draft.ref.chapter,
        portions: portions,
        colorId: choice.paletteIndex,
        colorValue: choice.customColor?.value,
        excerpt: excerpt.isEmpty ? null : excerpt,
      );
      _activeHighlightDraft = null;
      await _reloadHighlightsForState(draft.ref, state);
      _syncSavedCustomColors();
    } catch (_) {
      _restoreHighlightsFromMap(state, draft.originalHighlights);
      _activeHighlightDraft = null;
      if (mounted) setState(() {});
    }
  }

  void _applyHighlightPreview(
    _HighlightDraft draft,
    _ColorChoice choice,
    _ChapterState state,
  ) {
    final updated = draft.cloneOriginals();
    if (!draft.hasSelection) {
      _restoreHighlightsFromMap(state, updated);
      return;
    }

    final startEdge = draft.minEdge;
    final endEdge = draft.maxEdge;

    for (final verseNumber in _versesBetween(startEdge.verse, endEdge.verse)) {
      final verseText = _verseTextFor(state, verseNumber);
      if (verseText == null || verseText.isEmpty) continue;
      final length = verseText.length;
      var verseStart = verseNumber == startEdge.verse ? startEdge.offset : 0;
      var verseEnd = verseNumber == endEdge.verse ? endEdge.offset : length;
      verseStart = _clampOffset(verseStart, length);
      verseEnd = _clampOffset(verseEnd, length);
      if (verseEnd <= verseStart) continue;

      final list = List<VerseHighlight>.from(updated[verseNumber] ?? const []);
      list.add(
        VerseHighlight(
          spanId: draft.previewSpanId,
          colorId: choice.paletteIndex,
          colorValue: choice.customColor?.value,
          start: verseStart,
          end: verseEnd,
        ),
      );
      list.sort((a, b) => a.start.compareTo(b.start));
      updated[verseNumber] = list;
    }

    _restoreHighlightsFromMap(state, updated);
  }

  void _restoreHighlightsFromMap(
    _ChapterState state,
    Map<int, List<VerseHighlight>> source,
  ) {
    state.highlights
      ..clear()
      ..addEntries(
        source.entries
            .where((entry) => entry.value.isNotEmpty)
            .map(
              (entry) =>
                  MapEntry(entry.key, List<VerseHighlight>.from(entry.value)),
            ),
      );
  }

  Future<void> _reloadHighlightsForState(
    _ChapterRef ref,
    _ChapterState state,
  ) async {
    final refreshed = await _highlightService.highlightsFor(
      ref.book,
      ref.chapter,
    );
    _restoreHighlightsFromMap(state, refreshed);
    if (mounted) setState(() {});
  }

  int _verseLength(_ChapterState state, int verse) {
    final text = _verseTextFor(state, verse);
    return text?.length ?? 0;
  }

  Iterable<int> _versesBetween(int startVerse, int endVerse) sync* {
    final lower = startVerse <= endVerse ? startVerse : endVerse;
    final upper = startVerse <= endVerse ? endVerse : startVerse;
    for (var verseNumber = lower; verseNumber <= upper; verseNumber++) {
      yield verseNumber;
    }
  }

  _VerseEdge? _edgeForPosition(_ChapterState state, Offset globalPosition) {
    final infos = <_VerseLayoutInfo>[];
    state.verseKeys.forEach((verse, key) {
      final ctx = key.currentContext;
      final renderBox = ctx?.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) return;
      final topLeft = renderBox.localToGlobal(Offset.zero);
      infos.add(
        _VerseLayoutInfo(
          verse: verse,
          top: topLeft.dy,
          bottom: topLeft.dy + renderBox.size.height,
          state: key.currentState,
        ),
      );
    });
    if (infos.isEmpty) return null;
    infos.sort((a, b) => a.verse.compareTo(b.verse));

    if (globalPosition.dy <= infos.first.top) {
      return _VerseEdge(verse: infos.first.verse, offset: 0);
    }

    for (final info in infos) {
      if (globalPosition.dy < info.top) {
        return _VerseEdge(verse: info.verse, offset: 0);
      }
      if (globalPosition.dy <= info.bottom) {
        final verseState = info.state;
        if (verseState != null) {
          final offset = verseState.offsetForGlobalPosition(globalPosition);
          return _VerseEdge(verse: info.verse, offset: offset);
        }
        return _VerseEdge(verse: info.verse, offset: 0);
      }
    }

    final last = infos.last;
    final length = _verseLength(state, last.verse);
    return _VerseEdge(verse: last.verse, offset: length);
  }

  String? _excerptForRange(String verseText, int start, int end) {
    if (verseText.isEmpty) return null;
    final safeEnd = _clampOffset(end, verseText.length);
    final safeStart = _clampOffset(start, verseText.length);
    if (safeEnd <= safeStart) return null;
    final excerpt = verseText.substring(safeStart, safeEnd).trim();
    return excerpt.isEmpty ? null : excerpt;
  }

  void _syncSavedCustomColors() {
    final values = _highlightService.customColors;
    final colors = values.map((value) => Color(value)).toList(growable: false);
    if (!mounted) return;
    setState(() {
      _savedCustomColors = colors;
    });
  }

  Future<_USFMBookData?> _ensureUsfmBookData(String book) async {
    if (_usfmBookCache.containsKey(book)) {
      return _usfmBookCache[book];
    }
    if (_missingUsfmBooks.contains(book)) return null;

    try {
      String raw;
      try {
        raw = await rootBundle.loadString('assets/web_woc/$book.usfm');
      } catch (_) {
        final fallbackName = book.replaceAll(' ', '_');
        raw = await rootBundle.loadString('assets/web_woc/$fallbackName.usfm');
      }
      final parsed = _parseUsfm(raw);
      _usfmBookCache[book] = parsed;
      return parsed;
    } catch (_) {
      _missingUsfmBooks.add(book);
      _usfmBookCache[book] = null;
      return null;
    }
  }

  _USFMBookData _parseUsfm(String raw) {
    final segmentsByChapter = <int, Map<int, List<_USFMSegment>>>{};
    final redVerseByChapter = <int, Set<int>>{};

    int currentChapter = 0;
    int currentVerse = 0;
    bool inWj = false;

    void push(String text) {
      if (currentChapter <= 0 || currentVerse <= 0) return;
      if (text.isEmpty) return;
      final chapterMap = segmentsByChapter.putIfAbsent(
        currentChapter,
        () => <int, List<_USFMSegment>>{},
      );
      final verseList = chapterMap.putIfAbsent(
        currentVerse,
        () => <_USFMSegment>[],
      );
      if (verseList.isNotEmpty && verseList.last.isWj == inWj) {
        verseList.last.text += text;
      } else {
        verseList.add(_USFMSegment(text, inWj));
      }
      if (inWj) {
        redVerseByChapter
            .putIfAbsent(currentChapter, () => <int>{})
            .add(currentVerse);
      }
    }

    final buffer = StringBuffer();
    final length = raw.length;
    int index = 0;

    void flushBuffer() {
      if (buffer.isEmpty) return;
      push(buffer.toString());
      buffer.clear();
    }

    while (index < length) {
      final char = raw[index];
      if (char == '\\') {
        flushBuffer();
        int j = index + 1;
        while (j < length && RegExp(r'[A-Za-z*]').hasMatch(raw[j])) {
          j++;
        }
        final tag = raw.substring(index + 1, j);
        int k = j;
        while (k < length && raw[k] == ' ') {
          k++;
        }
        int m = k;
        while (m < length && RegExp(r'[0-9]').hasMatch(raw[m])) {
          m++;
        }
        final numberText = raw.substring(k, m);
        switch (tag) {
          case 'c':
            currentChapter = int.tryParse(numberText) ?? currentChapter;
            currentVerse = 0;
            break;
          case 'v':
            currentVerse = int.tryParse(numberText) ?? currentVerse;
            break;
          case 'wj':
            inWj = true;
            break;
          case 'wj*':
            inWj = false;
            break;
        }
        index = m;
        continue;
      } else {
        int nextSlash = raw.indexOf('\\', index);
        if (nextSlash == -1) nextSlash = length;
        final textChunk = raw.substring(index, nextSlash);
        buffer.write(textChunk);
        index = nextSlash;
      }
    }
    flushBuffer();

    // Normalize whitespace in segments
    segmentsByChapter.forEach((chapter, verseMap) {
      verseMap.forEach((verse, segList) {
        for (var i = 0; i < segList.length; i++) {
          final seg = segList[i];
          seg.text = seg.text
              .replaceAll('\r', '')
              .replaceAll('\n', ' ')
              .replaceAll(RegExp(r'\s+'), ' ');
        }
      });
    });

    return _USFMBookData(segmentsByChapter, redVerseByChapter);
  }

  void _handleItemPositionsChange() {
    final positions = _itemPositionsListener.itemPositions.value;
    if (positions.isEmpty) return;
    if (_restoringLocation || _suppressPositionUpdates) return;
    if (_pendingInitialJump || !_chapterIndexReady) {
      return;
    }

    ItemPosition? topMost;
    for (final position in positions) {
      if (position.itemTrailingEdge <= 0) continue;
      if (topMost == null ||
          position.itemLeadingEdge < topMost.itemLeadingEdge) {
        topMost = position;
      }
    }
    topMost ??= positions.first;

    final ref = chapterRefForIndex(topMost.index);
    if (ref == null) return;
    final topRef = ref;

    if (_initialViewportSettling) {
      if (topMost.itemLeadingEdge < -0.2) {
        return;
      }
      _initialViewportSettling = false;
    }

    if (ref.book != _visibleBook || ref.chapter != _visibleChapter) {
      setState(() {
        _visibleBook = ref.book;
        _visibleChapter = ref.chapter;
        if (_selectedVerse != null &&
            (ref.book != _selectedBook || ref.chapter != _selectedChapter)) {
          _selectedVerse = null;
        }
        if (_selectedVerse == null) {
          _selectedBook = ref.book;
          _selectedChapter = ref.chapter;
        }
      });
    }

    final state = _chapterStates[topRef];
    if (state != null) {
      final info = _visibleVerseInfo(state);
      if (info != null) {
        _currentVisibleVerse = info.verse;
        _currentVisibleAlignment = info.alignment;
      }
    }

    if (_restoreTargetVerse == null ||
        _currentVisibleVerse == _restoreTargetVerse) {
      debugPrint(
        '[Bible] save alignment -> verse=$_currentVisibleVerse align=$_currentVisibleAlignment',
      );
      _saveLastLocation(alignment: _currentVisibleAlignment);
    }

    if (topMost.index + 1 < _chapterRefs.length) {
      _ensureChapterState(_chapterRefs[topMost.index + 1]);
    }
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (!_navVisibilityArmed) {
      if (_navVisibilityPrimed &&
          notification is UserScrollNotification &&
          notification.direction != ScrollDirection.idle) {
        _navVisibilityArmed = true;
      }
      _lastScrollPixels = notification.metrics.pixels;
      return false;
    }
    final current = notification.metrics.pixels;
    final previous = _lastScrollPixels ?? current;
    final delta = current - previous;
    _lastScrollPixels = current;
    if (delta.abs() > 6) {
      if (delta > 0) {
        widget.onScrollVisibilityChange?.call(false);
        if (_headerVisible) {
          setState(() => _headerVisible = false);
        }
      } else {
        widget.onScrollVisibilityChange?.call(true);
        if (!_headerVisible) {
          setState(() => _headerVisible = true);
        }
      }
    }
    return false;
  }

  void _armNavVisibility() {
    _navVisibilityArmed = false;
    _navVisibilityPrimed = true;
  }

  void _jumpToInitialPosition() {
    if (!_chapterIndexReady || !_pendingInitialJump) return;
    if (!_itemScrollController.isAttached) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _jumpToInitialPosition(),
      );
      return;
    }

    final alignment = _storedAlignment.clamp(0.0, 1.0);
    debugPrint(
      '[Bible] jumpToInitialPosition -> index=$_initialListIndex alignment=$alignment book=$_selectedBook chapter=$_selectedChapter verse=$_selectedVerse',
    );
    _itemScrollController.jumpTo(index: _initialListIndex);
    if (alignment != 0.0) {
      _itemScrollController.scrollTo(
        index: _initialListIndex,
        alignment: alignment,
        duration: const Duration(milliseconds: 10),
      );
    }
    _pendingInitialJump = false;
    _initialViewportSettling = true;

    final ref = chapterRefForIndex(_initialListIndex);
    if (ref != null) {
      setState(() {
        _selectedBook = ref.book;
        _selectedChapter = ref.chapter;
        _visibleBook = ref.book;
        _visibleChapter = ref.chapter;
        _currentVisibleVerse ??= _storedVisibleVerse ?? _selectedVerse;
        _currentVisibleAlignment ??= _storedAlignment;
      });
    }

    final verseToRestore = _selectedVerse ?? _storedVisibleVerse;
    if (ref != null && verseToRestore != null) {
      _ensureChapterState(ref).then((_) {
        _scheduleVerseScrollForRef(
          ref,
          verseToRestore,
          index: _initialListIndex,
          alignment: _storedAlignment,
        );
      });
    }

    _storedVisibleVerse = null;

    if (!_initialViewportSettling) {
      _saveLastLocation();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _armNavVisibility());
  }

  void _saveLastLocation({double? alignment}) {
    if (alignment != null) {
      final clamped = alignment.clamp(0.0, 1.0);
      _lastVisibleAlignment = clamped;
      _currentVisibleAlignment = clamped;
    }
    final savedVerse = _selectedVerse ?? _currentVisibleVerse ?? 0;
    final effectiveAlignment =
        (_currentVisibleAlignment ?? _lastVisibleAlignment).clamp(0.0, 1.0);
    final visibleVerse = _currentVisibleVerse ?? savedVerse;
    final payload =
        '$_selectedBook|$_selectedChapter|$savedVerse|$effectiveAlignment|$visibleVerse';
    _storedAlignment = effectiveAlignment;
    _storedVisibleVerse = visibleVerse > 0 ? visibleVerse : null;
    debugPrint('[Bible] saveLastLocation -> $payload');
    _userStateService.writeString('bible.lastLocation', payload);
  }

  Future<void> _showReferencePicker() async {
    final books = _books.isEmpty ? await _service.getBooks() : _books;
    if (!mounted) return;

    final result = await showModalBottomSheet<_ReferenceSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ReferencePickerSheet(
          service: _service,
          books: books,
          initialBook: _selectedBook,
          initialChapter: _selectedChapter,
          initialVerse: _selectedVerse,
        );
      },
    );

    if (result == null) return;

    final bookChanged = result.book != _selectedBook;
    final chapterChanged = bookChanged || result.chapter != _selectedChapter;
    final verseChanged = result.verse != _selectedVerse;

    if (bookChanged || chapterChanged) {
      await _jumpToChapter(result.book, result.chapter, verse: result.verse);
    } else if (verseChanged) {
      setState(() => _selectedVerse = result.verse);
      _currentVisibleVerse = result.verse;
      _currentVisibleAlignment = 0.0;
      if (result.verse != null) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToVerse(result.verse!),
        );
      }
      _saveLastLocation(alignment: 0);
    }
  }

  void _scrollToVerse(int verse, {int attempt = 0}) {
    final chapterIndex = chapterIndexFor(_selectedBook, _selectedChapter);
    if (chapterIndex == -1) return;
    final ref = chapterRefForIndex(chapterIndex);
    if (ref == null) return;

    if (!_itemScrollController.isAttached) {
      if (attempt > 6) return;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToVerse(verse, attempt: attempt + 1),
      );
      return;
    }

    _itemScrollController
        .scrollTo(
          index: chapterIndex,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: 0,
        )
        .then((_) {
          if (!mounted) return;
          setState(() => _selectedVerse = verse);
          _currentVisibleVerse = verse;
          _currentVisibleAlignment = 0.0;
          _scheduleVerseScrollForRef(ref, verse, index: chapterIndex);
        });
    _saveLastLocation(alignment: 0);
  }

  Future<void> _jumpToChapter(
    String book,
    int chapter, {
    int? verse,
    bool animate = true,
    int attempt = 0,
  }) async {
    final index = chapterIndexFor(book, chapter);
    if (index == -1) return;
    final ref = chapterRefForIndex(index);
    if (ref == null) return;

    await _ensureChapterState(ref);

    if (!_itemScrollController.isAttached) {
      if (attempt > 6) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _jumpToChapter(
          book,
          chapter,
          verse: verse,
          animate: animate,
          attempt: attempt + 1,
        );
      });
      return;
    }

    if (animate) {
      await _itemScrollController.scrollTo(
        index: index,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0,
      );
    } else {
      _itemScrollController.jumpTo(index: index);
    }

    if (!mounted) return;
    setState(() {
      _selectedBook = book;
      _selectedChapter = chapter;
      _selectedVerse = verse;
      if (verse != null) {
        _currentVisibleVerse = verse;
        _currentVisibleAlignment = 0.0;
      }
    });

    if (verse != null) {
      _scheduleVerseScrollForRef(ref, verse, index: index);
    }

    _saveLastLocation(alignment: 0);
  }

  List<InlineSpan> _buildJesusRedLetterSpans({
    required String book,
    required String verseText,
    required TextStyle baseStyle,
    required TextStyle redStyle,
    _ChapterState? chapterState,
  }) {
    final bool isRedLetterBook = _redLetterBooks.contains(book);
    if (!isRedLetterBook) {
      return [TextSpan(text: verseText, style: baseStyle)];
    }

    final bool attributesToJesus = _jesusAttribution.hasMatch(verseText);
    final parts = <String>[];
    final matches = _quoteMarks.allMatches(verseText).toList();
    var last = 0;
    for (final m in matches) {
      if (m.start > last) parts.add(verseText.substring(last, m.start));
      parts.add(verseText.substring(m.start, m.end));
      last = m.end;
    }
    if (last < verseText.length) parts.add(verseText.substring(last));

    final bool initialOpenQuote =
        chapterState?.jesusSpeakingOpenQuote ?? _jesusSpeakingOpenQuote;

    if (parts.isEmpty) {
      return [
        initialOpenQuote
            ? TextSpan(text: verseText, style: redStyle)
            : TextSpan(text: verseText, style: baseStyle),
      ];
    }

    var insideQuote = initialOpenQuote;
    final spans = <InlineSpan>[];
    for (final piece in parts) {
      if (_quoteMarks.hasMatch(piece)) {
        insideQuote = !insideQuote;
        spans.add(TextSpan(text: piece, style: baseStyle));
      } else {
        final paintRed = insideQuote && (attributesToJesus || initialOpenQuote);
        spans.add(
          TextSpan(text: piece, style: paintRed ? redStyle : baseStyle),
        );
      }
    }

    final bool updatedQuoteState =
        insideQuote && (attributesToJesus || initialOpenQuote);
    if (chapterState != null) {
      chapterState.jesusSpeakingOpenQuote = updatedQuoteState;
    } else {
      _jesusSpeakingOpenQuote = updatedQuoteState;
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final mediaPadding = MediaQuery.of(context).padding;
    final bottomPad = widget.navVisible
        ? (mediaPadding.bottom + 24)
        : (mediaPadding.bottom + 8);

    final headerTitle =
        (_selectedVerse != null &&
            _visibleBook == _selectedBook &&
            _visibleChapter == _selectedChapter)
        ? '$_visibleBook $_visibleChapter:${_selectedVerse!}'
        : '$_visibleBook $_visibleChapter';

    if (!_chapterIndexReady) {
      return Scaffold(
        backgroundColor: isDark ? Colors.black : Colors.white,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_chapterRefs.isEmpty) {
      return Scaffold(
        backgroundColor: isDark ? Colors.black : Colors.white,
        body: const Center(child: Text('No chapters available.')),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: _handleScrollNotification,
            child: ScrollablePositionedList.builder(
              padding: EdgeInsets.fromLTRB(
                16,
                mediaPadding.top + 120,
                16,
                bottomPad,
              ),
              itemCount: _chapterRefs.length,
              itemScrollController: _itemScrollController,
              itemPositionsListener: _itemPositionsListener,
              initialScrollIndex: _initialListIndex,
              itemBuilder: (context, index) =>
                  _buildChapterItem(context, index, textTheme, isDark),
            ),
          ),
          _buildHeaderOverlay(
            context: context,
            title: headerTitle,
            isDark: isDark,
            topPadding: mediaPadding.top,
          ),
          if (_shouldShowInitialLoader(isDark))
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  color: Colors.black.withOpacity(isDark ? 0.4 : 0.12),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _shouldShowInitialLoader(bool isDark) {
    if (_chapterRefs.isEmpty) return true;
    final index = chapterIndexFor(_visibleBook, _visibleChapter);
    if (index == -1) return true;
    final state = _chapterStates[_chapterRefs[index]];
    if (state == null) return true;
    if (state.error != null) return false;
    return state.verses == null || state.isLoading;
  }
}

typedef _VerseSpanBuilder =
    List<InlineSpan> Function({
      required String book,
      required String verseText,
      required TextStyle baseStyle,
      required TextStyle redStyle,
      _ChapterState? chapterState,
    });

class _ChapterInlineText extends StatelessWidget {
  const _ChapterInlineText({
    required this.baseStyle,
    required this.redStyle,
    required this.verses,
    required this.verseKeys,
    required this.selectedVerse,
    required this.selectedBook,
    required this.spanBuilder,
    this.chapterState,
    required this.isDark,
    required this.book,
    required this.chapter,
    this.onHighlightStart,
    this.onHighlightUpdate,
    this.onHighlightEnd,
    this.onHighlightTap,
  });

  final TextStyle baseStyle;
  final TextStyle redStyle;
  final List<Map<String, dynamic>> verses;
  final Map<int, GlobalKey<_VerseInlineState>> verseKeys;
  final int? selectedVerse;
  final String selectedBook;
  final _VerseSpanBuilder spanBuilder;
  final _ChapterState? chapterState;
  final bool isDark;
  final String book;
  final int chapter;
  final void Function(String book, int chapter, int verse, int startOffset)?
  onHighlightStart;
  final void Function(
    String book,
    int chapter,
    int verse,
    int startOffset,
    int currentOffset,
    Offset globalPosition,
  )?
  onHighlightUpdate;
  final Future<void> Function(
    String book,
    int chapter,
    int verse,
    int startOffset,
    int endOffset,
    Offset globalPosition,
  )?
  onHighlightEnd;
  final void Function(
    String book,
    int chapter,
    int verse,
    VerseHighlight highlight,
  )?
  onHighlightTap;

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    final lineHeight = baseStyle.height ?? 1.0;

    for (final v in verses) {
      final verseNum = v['verse'] as int;
      final verseText = (v['text'] as String).replaceAll('\n', ' ').trim();
      if (verseText.isEmpty) continue;
      final isSelected = verseNum == selectedVerse;
      final rawHighlights =
          chapterState?.highlights[verseNum] ?? const <VerseHighlight>[];
      final verseHighlights = List<VerseHighlight>.from(rawHighlights)
        ..sort((a, b) => a.start.compareTo(b.start));

      List<InlineSpan> textSpans;
      final segments = v['segments'];
      if (segments is List && segments.isNotEmpty) {
        final composed = _composeSegments(
          verseText: verseText,
          segments: segments.cast<Map<String, dynamic>>(),
          baseStyle: baseStyle,
          redStyle: redStyle,
          highlights: verseHighlights,
        );
        if (composed != null && composed.isNotEmpty) {
          textSpans = composed;
        } else {
          textSpans = spanBuilder(
            book: selectedBook,
            verseText: verseText,
            baseStyle: baseStyle,
            redStyle: redStyle,
            chapterState: chapterState,
          );
          textSpans = _applyHighlightsToSpans(
            textSpans,
            verseHighlights,
            baseStyle,
          );
        }
      } else if (chapterState?.redVerses.contains(verseNum) ?? false) {
        textSpans = spanBuilder(
          book: selectedBook,
          verseText: verseText,
          baseStyle: baseStyle,
          redStyle: redStyle,
          chapterState: chapterState,
        );
        textSpans = _applyHighlightsToSpans(
          textSpans,
          verseHighlights,
          baseStyle,
        );
      } else {
        textSpans = _applyHighlightsToSpans(
          [TextSpan(text: verseText, style: baseStyle)],
          verseHighlights,
          baseStyle,
        );
      }

      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: _VerseInline(
            key: verseKeys[verseNum],
            verseNumber: verseNum,
            verseText: verseText,
            verseSpans: textSpans,
            baseStyle: baseStyle,
            isSelected: isSelected,
            lineHeight: lineHeight,
            verseHighlights: verseHighlights,
            onHighlightStart: onHighlightStart == null
                ? null
                : (offset) =>
                      onHighlightStart!(book, chapter, verseNum, offset),
            onHighlightUpdate: onHighlightUpdate == null
                ? null
                : (startOffset, currentOffset, globalPosition) =>
                      onHighlightUpdate!(
                        book,
                        chapter,
                        verseNum,
                        startOffset,
                        currentOffset,
                        globalPosition,
                      ),
            onHighlightEnd: onHighlightEnd == null
                ? null
                : (startOffset, endOffset, globalPosition) {
                    onHighlightEnd!(
                      book,
                      chapter,
                      verseNum,
                      startOffset,
                      endOffset,
                      globalPosition,
                    );
                  },
            onHighlightTap: onHighlightTap == null
                ? null
                : (highlight) =>
                      onHighlightTap!(book, chapter, verseNum, highlight),
          ),
        ),
      );

      spans.add(const TextSpan(text: ' '));
    }

    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
      textAlign: TextAlign.start,
      softWrap: true,
    );
  }

  List<InlineSpan>? _composeSegments({
    required String verseText,
    required List<Map<String, dynamic>> segments,
    required TextStyle baseStyle,
    required TextStyle redStyle,
    required List<VerseHighlight> highlights,
  }) {
    if (verseText.isEmpty) return null;

    final spans = <InlineSpan>[];
    int cursor = 0;

    for (final seg in segments) {
      final raw = (seg['text'] as String?)?.trim();
      if (raw == null || raw.isEmpty) continue;
      final isWj = seg['wj'] == true;
      final index = verseText.indexOf(raw, cursor);
      if (index == -1) {
        return null;
      }
      if (index > cursor) {
        spans.addAll(
          _sliceWithHighlights(
            verseText: verseText,
            start: cursor,
            end: index,
            baseStyle: baseStyle,
            highlights: highlights,
          ),
        );
      }
      spans.addAll(
        _sliceWithHighlights(
          verseText: verseText,
          start: index,
          end: index + raw.length,
          baseStyle: isWj ? redStyle : baseStyle,
          highlights: highlights,
        ),
      );
      cursor = index + raw.length;
    }

    if (cursor < verseText.length) {
      spans.addAll(
        _sliceWithHighlights(
          verseText: verseText,
          start: cursor,
          end: verseText.length,
          baseStyle: baseStyle,
          highlights: highlights,
        ),
      );
    }

    return spans;
  }

  List<InlineSpan> _applyHighlightsToSpans(
    List<InlineSpan> spans,
    List<VerseHighlight> highlights,
    TextStyle fallbackStyle,
  ) {
    if (highlights.isEmpty) return spans;

    final bool dark = isDark;
    final sorted = List<VerseHighlight>.from(highlights)
      ..sort((a, b) => a.start.compareTo(b.start));

    Color? colorAt(int position) {
      for (final h in sorted) {
        if (position >= h.start && position < h.end) {
          return highlightColorForHighlight(h, dark: dark);
        }
      }
      return null;
    }

    final result = <InlineSpan>[];
    int globalOffset = 0;

    for (final span in spans) {
      if (span is! TextSpan) {
        result.add(span);
        continue;
      }
      final text = span.text ?? '';
      if (text.isEmpty) {
        result.add(span);
        continue;
      }
      final baseStyle = span.style ?? fallbackStyle;
      int localIndex = 0;
      while (localIndex < text.length) {
        final absolute = globalOffset + localIndex;
        final color = colorAt(absolute);
        int chunkEnd = localIndex + 1;
        while (chunkEnd < text.length &&
            colorAt(globalOffset + chunkEnd) == color) {
          chunkEnd++;
        }
        final segmentText = text.substring(localIndex, chunkEnd);
        TextStyle segmentStyle = baseStyle;
        if (color != null) {
          segmentStyle = baseStyle.merge(
            TextStyle(
              background: Paint()
                ..color = color
                ..style = PaintingStyle.fill
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.6),
            ),
          );
        }
        result.add(TextSpan(text: segmentText, style: segmentStyle));
        localIndex = chunkEnd;
      }
      globalOffset += text.length;
    }

    return result;
  }

  List<InlineSpan> _sliceWithHighlights({
    required String verseText,
    required int start,
    required int end,
    required TextStyle baseStyle,
    required List<VerseHighlight> highlights,
  }) {
    if (start >= end) return const [];
    final text = verseText.substring(start, end);
    return _applyHighlightsToSpans(
      [TextSpan(text: text, style: baseStyle)],
      highlights,
      baseStyle,
    );
  }
}

class _VerseInline extends StatefulWidget {
  const _VerseInline({
    super.key,
    required this.verseNumber,
    required this.verseText,
    required this.verseSpans,
    required this.baseStyle,
    required this.isSelected,
    required this.lineHeight,
    required this.verseHighlights,
    this.onHighlightStart,
    this.onHighlightUpdate,
    this.onHighlightEnd,
    this.onHighlightTap,
  });

  final int verseNumber;
  final String verseText;
  final List<InlineSpan> verseSpans;
  final TextStyle baseStyle;
  final bool isSelected;
  final double lineHeight;
  final List<VerseHighlight> verseHighlights;
  final void Function(int offset)? onHighlightStart;
  final void Function(
    int startOffset,
    int currentOffset,
    Offset globalPosition,
  )?
  onHighlightUpdate;
  final void Function(int startOffset, int endOffset, Offset globalPosition)?
  onHighlightEnd;
  final void Function(VerseHighlight highlight)? onHighlightTap;

  @override
  State<_VerseInline> createState() => _VerseInlineState();
}

class _VerseInlineState extends State<_VerseInline> {
  int? _dragStartOffset;
  Offset? _lastGlobalPosition;

  TextSpan _buildRichTextSpan(TextStyle numberStyle) {
    return TextSpan(
      style: widget.baseStyle.copyWith(height: widget.lineHeight),
      children: [
        TextSpan(text: '${widget.verseNumber}', style: numberStyle),
        const TextSpan(text: ' '),
        ...widget.verseSpans,
        const TextSpan(text: ' '),
      ],
    );
  }

  TextPainter _createTextPainter(TextStyle numberStyle, double maxWidth) {
    final painter = TextPainter(
      text: _buildRichTextSpan(numberStyle),
      textDirection: TextDirection.ltr,
      maxLines: null,
    );
    painter.layout(maxWidth: maxWidth);
    return painter;
  }

  int _offsetForPosition(Offset position, TextStyle numberStyle) {
    final renderBox = context.findRenderObject() as RenderBox?;
    final width = renderBox?.size.width ?? double.infinity;
    final painter = _createTextPainter(numberStyle, width);
    final textPosition = painter.getPositionForOffset(position);
    final prefixLength = widget.verseNumber.toString().length + 1;
    var offset = textPosition.offset - prefixLength;
    if (offset < 0) offset = 0;
    final maxLength = widget.verseText.length;
    if (offset > maxLength) offset = maxLength;
    return offset;
  }

  TextStyle _numberStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return widget.baseStyle.copyWith(
      fontSize: (widget.baseStyle.fontSize ?? 18) * 0.6,
      color: isDark ? Colors.purple[200] : Colors.purple,
      fontWeight: FontWeight.bold,
      height: 1.0,
    );
  }

  int offsetForGlobalPosition(Offset globalPosition) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) {
      return widget.verseText.length;
    }
    final local = renderBox.globalToLocal(globalPosition);
    final numberStyle = _numberStyle(context);
    return _offsetForPosition(local, numberStyle);
  }

  Offset _fallbackGlobalPosition() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return Offset.zero;
    final center = renderBox.size.center(Offset.zero);
    return renderBox.localToGlobal(center);
  }

  void _handleLongPressStart(
    LongPressStartDetails details,
    TextStyle numberStyle,
  ) {
    final offset = _offsetForPosition(details.localPosition, numberStyle);
    _dragStartOffset = offset;
    _lastGlobalPosition = details.globalPosition;
    widget.onHighlightStart?.call(offset);
  }

  void _handleLongPressMove(
    LongPressMoveUpdateDetails details,
    TextStyle numberStyle,
  ) {
    final start = _dragStartOffset;
    if (start == null) return;
    final current = _offsetForPosition(details.localPosition, numberStyle);
    _lastGlobalPosition = details.globalPosition;
    widget.onHighlightUpdate?.call(start, current, details.globalPosition);
  }

  void _handleLongPressEnd(LongPressEndDetails details, TextStyle numberStyle) {
    final start = _dragStartOffset;
    if (start == null) return;
    final end = _offsetForPosition(details.localPosition, numberStyle);
    _dragStartOffset = null;
    _lastGlobalPosition = details.globalPosition;
    widget.onHighlightEnd?.call(start, end, details.globalPosition);
    _lastGlobalPosition = null;
  }

  void _handleLongPressCancel() {
    final start = _dragStartOffset;
    if (start == null) return;
    _dragStartOffset = null;
    final global = _lastGlobalPosition ?? _fallbackGlobalPosition();
    _lastGlobalPosition = null;
    widget.onHighlightEnd?.call(start, start, global);
  }

  VerseHighlight? _highlightAtOffset(int offset) {
    for (final highlight in widget.verseHighlights) {
      if (offset >= highlight.start && offset < highlight.end) {
        return highlight;
      }
    }
    return null;
  }

  void _handleTapUp(TapUpDetails details, TextStyle numberStyle) {
    if (widget.onHighlightTap == null) return;
    final offset = _offsetForPosition(details.localPosition, numberStyle);
    final highlight = _highlightAtOffset(offset);
    if (highlight != null) {
      widget.onHighlightTap?.call(highlight);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final highlightColor = widget.isSelected
        ? (isDark
              ? Colors.white.withOpacity(0.1)
              : Colors.amber[100]?.withOpacity(0.45))
        : null;
    final numberStyle = _numberStyle(context);

    final richTextSpan = _buildRichTextSpan(numberStyle);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPressStart: (details) =>
              _handleLongPressStart(details, numberStyle),
          onLongPressMoveUpdate: (details) =>
              _handleLongPressMove(details, numberStyle),
          onLongPressEnd: (details) =>
              _handleLongPressEnd(details, numberStyle),
          onLongPressCancel: _handleLongPressCancel,
          onTapUp: (details) => _handleTapUp(details, numberStyle),
          child: SizedBox(
            width: maxWidth,
            child: Container(
              decoration: BoxDecoration(
                color: highlightColor,
                borderRadius: BorderRadius.circular(widget.isSelected ? 8 : 4),
              ),
              padding: EdgeInsets.symmetric(
                horizontal: widget.isSelected ? 6 : 0,
                vertical: widget.isSelected ? 2 : 0,
              ),
              child: RichText(text: richTextSpan, softWrap: true),
            ),
          ),
        );
      },
    );
  }
}

class _VerseLayoutInfo {
  _VerseLayoutInfo({
    required this.verse,
    required this.top,
    required this.bottom,
    required this.state,
  });

  final int verse;
  final double top;
  final double bottom;
  final _VerseInlineState? state;
}

class _HighlightDraft {
  _HighlightDraft({
    required this.ref,
    required this.startVerse,
    required this.startOffset,
    required Map<int, List<VerseHighlight>> originalHighlights,
    String? previewSpanId,
  }) : currentVerse = startVerse,
       currentOffset = startOffset,
       previewSpanId =
           previewSpanId ??
           '_draft_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
       originalHighlights = originalHighlights.map(
         (key, value) => MapEntry(key, List<VerseHighlight>.from(value)),
       );

  final _ChapterRef ref;
  final int startVerse;
  final int startOffset;
  int currentVerse;
  int currentOffset;
  final String previewSpanId;
  final Map<int, List<VerseHighlight>> originalHighlights;

  _VerseEdge get startEdge =>
      _VerseEdge(verse: startVerse, offset: startOffset);

  _VerseEdge get currentEdge =>
      _VerseEdge(verse: currentVerse, offset: currentOffset);

  _VerseEdge get minEdge =>
      startEdge.compareTo(currentEdge) <= 0 ? startEdge : currentEdge;

  _VerseEdge get maxEdge =>
      startEdge.compareTo(currentEdge) <= 0 ? currentEdge : startEdge;

  bool get hasSelection {
    final min = minEdge;
    final max = maxEdge;
    if (min.verse == max.verse) {
      return max.offset > min.offset;
    }
    return true;
  }

  Map<int, List<VerseHighlight>> cloneOriginals() {
    final clone = <int, List<VerseHighlight>>{};
    originalHighlights.forEach((key, value) {
      clone[key] = List<VerseHighlight>.from(value);
    });
    return clone;
  }
}

class _VerseEdge {
  const _VerseEdge({required this.verse, required this.offset});

  final int verse;
  final int offset;

  int compareTo(_VerseEdge other) {
    final verseCompare = verse.compareTo(other.verse);
    if (verseCompare != 0) return verseCompare;
    return offset.compareTo(other.offset);
  }
}

class _ColorChoice {
  const _ColorChoice({required this.paletteIndex, this.customColor});

  final int paletteIndex;
  final Color? customColor;
}

class _HighlightSelection {
  const _HighlightSelection._({
    this.paletteIndex,
    this.customColor,
    this.delete = false,
  });

  const _HighlightSelection.palette(int paletteIndex)
    : this._(paletteIndex: paletteIndex);

  const _HighlightSelection.custom({
    required int paletteIndex,
    required Color color,
  }) : this._(paletteIndex: paletteIndex, customColor: color);

  const _HighlightSelection.delete() : this._(delete: true);

  final int? paletteIndex;
  final Color? customColor;
  final bool delete;
}

class _ChapterState {
  List<Map<String, dynamic>>? verses;
  Set<int> redVerses = const <int>{};
  final Map<int, GlobalKey<_VerseInlineState>> verseKeys = {};
  final Map<int, List<VerseHighlight>> highlights = {};
  bool isLoading = false;
  String? error;
  bool jesusSpeakingOpenQuote = false;
}

class _VisibleVerseInfo {
  _VisibleVerseInfo(this.verse, this.alignment);

  final int verse;
  final double alignment;
}

class _ChapterRef {
  const _ChapterRef({required this.book, required this.chapter});

  final String book;
  final int chapter;

  @override
  int get hashCode => Object.hash(book.toLowerCase(), chapter);

  @override
  bool operator ==(Object other) {
    return other is _ChapterRef &&
        other.chapter == chapter &&
        other.book.toLowerCase() == book.toLowerCase();
  }
}

class _USFMBookData {
  _USFMBookData(this.segments, this.redVerses);

  final Map<int, Map<int, List<_USFMSegment>>> segments;
  final Map<int, Set<int>> redVerses;
}

class _USFMSegment {
  _USFMSegment(this.text, this.isWj);
  String text;
  final bool isWj;
}

class _ReferenceSelection {
  const _ReferenceSelection({
    required this.book,
    required this.chapter,
    this.verse,
  });

  final String book;
  final int chapter;
  final int? verse;
}

class _ReferencePickerSheet extends StatefulWidget {
  const _ReferencePickerSheet({
    required this.service,
    required this.books,
    required this.initialBook,
    required this.initialChapter,
    this.initialVerse,
  });

  final BibleService service;
  final List<String> books;
  final String initialBook;
  final int initialChapter;
  final int? initialVerse;

  @override
  State<_ReferencePickerSheet> createState() => _ReferencePickerSheetState();
}

class _ReferencePickerSheetState extends State<_ReferencePickerSheet> {
  late String _book;
  late int _chapter;
  int? _verse;

  late List<String> _books;
  int _chapterCount = 1;
  List<Map<String, dynamic>> _verses = [];
  bool _loadingChapters = true;
  bool _loadingVerses = true;

  final TextEditingController _searchController = TextEditingController();

  _ReferenceStage _stage = _ReferenceStage.book;

  @override
  void initState() {
    super.initState();
    _books = widget.books;
    _book = widget.initialBook;
    _chapter = widget.initialChapter;
    _verse = widget.initialVerse;
    _stage = _ReferenceStage.book;
    _loadChapterCountAndVerses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadChapterCountAndVerses() async {
    setState(() {
      _loadingChapters = true;
      _loadingVerses = true;
    });

    final count = await widget.service.getChapterCount(_book);
    if (!mounted) return;
    final adjustedChapter = _chapter.clamp(1, count);

    setState(() {
      _chapterCount = count;
      _chapter = adjustedChapter;
      _loadingChapters = false;
    });

    await _loadVerses();
  }

  Future<void> _loadVerses() async {
    setState(() => _loadingVerses = true);
    final data =
        await widget.service.fetchChapter(_book, _chapter) ??
        <Map<String, dynamic>>[];
    if (!mounted) return;
    setState(() {
      _verses = data;
      if (_verse != null &&
          !_verses.any((v) => (v['verse'] as int) == _verse)) {
        _verse = null;
      }
      _loadingVerses = false;
    });
  }

  Future<void> _selectBook(String book) async {
    if (_book == book && _stage == _ReferenceStage.book) {
      setState(() => _stage = _ReferenceStage.chapter);
      return;
    }

    setState(() {
      _book = book;
      _chapter = 1;
      _verse = null;
      _stage = _ReferenceStage.chapter;
    });
    await _loadChapterCountAndVerses();
  }

  Future<void> _selectChapter(int chapter, {int? verse}) async {
    if (_chapter == chapter &&
        _stage == _ReferenceStage.chapter &&
        verse == null) {
      setState(() => _stage = _ReferenceStage.verse);
      return;
    }

    setState(() {
      _chapter = chapter;
      _verse = null;
      _stage = _ReferenceStage.verse;
    });

    await _loadVerses();
    if (!mounted) return;

    if (verse != null && _verses.any((v) => (v['verse'] as int) == verse)) {
      setState(() => _verse = verse);
    }
  }

  void _selectVerse(int verse) {
    setState(() => _verse = verse);
  }

  void _goBack() {
    setState(() {
      switch (_stage) {
        case _ReferenceStage.book:
          break;
        case _ReferenceStage.chapter:
          _stage = _ReferenceStage.book;
          break;
        case _ReferenceStage.verse:
          _stage = _ReferenceStage.chapter;
          break;
      }
    });
  }

  Future<_ReferenceSelection?> _applyCombinedReference(String input) async {
    final raw = input.trim();
    if (raw.isEmpty) return null;

    final lower = raw.toLowerCase();
    final booksByLen = [..._books]
      ..sort((a, b) => b.length.compareTo(a.length));
    String? matchedBook;
    int matchEnd = 0;
    for (final book in booksByLen) {
      final normalizedBook = _normalizeRef(book);
      final normalizedInput = _normalizeRef(lower);
      if (normalizedInput.startsWith(normalizedBook)) {
        matchedBook = book;
        matchEnd =
            lower.length - (normalizedInput.length - normalizedBook.length);
        break;
      }
    }
    if (matchedBook == null) return null;

    final chapterCount = await widget.service.getChapterCount(matchedBook);
    final rest = raw.substring(matchEnd).trim();
    if (rest.isEmpty) {
      return _ReferenceSelection(
        book: matchedBook,
        chapter: _chapter,
        verse: null,
      );
    }

    final colonOrSpace = RegExp(r'^(\d+)\s*(?::|\s)\s*(\d+)$');
    final m1 = colonOrSpace.firstMatch(rest);
    int? chapter;
    int? verse;
    if (m1 != null) {
      chapter = int.tryParse(m1.group(1)!);
      verse = int.tryParse(m1.group(2)!);
    } else {
      final digits = RegExp(r'^\d+$');
      if (digits.hasMatch(rest) && rest.length >= 2) {
        for (int i = 1; i < rest.length; i++) {
          final ch = int.tryParse(rest.substring(0, i));
          final vs = int.tryParse(rest.substring(i));
          if (ch != null && vs != null && ch >= 1 && ch <= chapterCount) {
            chapter = ch;
            verse = vs;
            break;
          }
        }
        chapter ??= int.tryParse(rest);
      } else {
        chapter = int.tryParse(rest);
      }
    }

    if (chapter == null) return null;
    return _ReferenceSelection(
      book: matchedBook,
      chapter: chapter,
      verse: verse,
    );
  }

  String _normalizeRef(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  Widget _buildBookStage(ThemeData theme, ColorScheme scheme) {
    return Column(
      key: const ValueKey('stage-book'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Scrollbar(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: _books.length,
              itemBuilder: (context, index) {
                final book = _books[index];
                final selected = book == _book;
                return ListTile(
                  onTap: () => _selectBook(book),
                  title: Text(
                    book,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: selected ? FontWeight.w600 : null,
                      color: selected ? scheme.primary : null,
                    ),
                  ),
                  trailing: selected
                      ? Icon(Icons.check, color: scheme.primary)
                      : null,
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChapterStage(ThemeData theme) {
    return Column(
      key: const ValueKey('stage-chapter'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Chapters in $_book',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        if (_loadingChapters)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: List.generate(_chapterCount, (i) => i + 1).map((
                  chapter,
                ) {
                  final selected = chapter == _chapter;
                  return ChoiceChip(
                    label: Text('$chapter'),
                    selected: selected,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onSelected: (value) {
                      if (value) _selectChapter(chapter);
                    },
                  );
                }).toList(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildVerseStage(ThemeData theme) {
    return Column(
      key: const ValueKey('stage-verse'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Verses in $_book $_chapter',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        if (_loadingVerses)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (_verses.isEmpty)
          const Expanded(child: Center(child: Text('No verses available.')))
        else
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _verses.map((v) => v['verse'] as int).map((verse) {
                  final selected = verse == _verse;
                  return ChoiceChip(
                    label: Text('$verse'),
                    selected: selected,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onSelected: (value) {
                      if (value) _selectVerse(verse);
                    },
                  );
                }).toList(),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget stage;
    switch (_stage) {
      case _ReferenceStage.book:
        stage = _buildBookStage(theme, scheme);
        break;
      case _ReferenceStage.chapter:
        stage = _buildChapterStage(theme);
        break;
      case _ReferenceStage.verse:
        stage = _buildVerseStage(theme);
        break;
    }

    return FractionallySizedBox(
      heightFactor: 0.9,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: theme.brightness == Brightness.dark
                  ? Colors.black.withOpacity(0.5)
                  : Colors.black.withOpacity(0.16),
              blurRadius: 24,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withOpacity(0.28),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (_stage != _ReferenceStage.book)
                      IconButton(
                        tooltip: 'Back',
                        onPressed: _goBack,
                        icon: const Icon(Icons.arrow_back),
                      ),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          labelText: 'Search (e.g., John 3:16)',
                          prefixIcon: const Icon(Icons.search),
                          border: const OutlineInputBorder(),
                          suffixIcon: _searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Clear',
                                  icon: const Icon(Icons.close),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                ),
                        ),
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (value) async {
                          final sel = await _applyCombinedReference(value);
                          if (!mounted) return;
                          if (sel != null) Navigator.of(context).pop(sel);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () async {
                        final sel = await _applyCombinedReference(
                          _searchController.text,
                        );
                        if (!mounted) return;
                        if (sel != null) Navigator.of(context).pop(sel);
                      },
                      child: const Text('Go'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: stage,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _ReferenceStage { book, chapter, verse }
