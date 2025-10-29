import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/note.dart';
import '../services/highlight_service.dart';
import '../services/notes_service.dart';
import 'note_editor_screen.dart';
import 'highlights_screen.dart';
import '../widgets/notes_section_list.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({
    super.key,
    this.onScrollVisibilityChange,
    this.navVisible = true,
    this.navVisibilityResetTick = 0,
    this.onHighlightSelected,
  });

  final void Function(bool)? onScrollVisibilityChange;
  final bool navVisible;
  final int navVisibilityResetTick;
  final void Function(HighlightEntry entry)? onHighlightSelected;

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final NotesService _notesService = NotesService.instance;
  late final ValueNotifier<List<Note>> _notesNotifier;
  late final ValueNotifier<Map<String, List<Note>>> _groupedNotes;
  late final ValueNotifier<List<Note>> _pinnedNotes;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  late final ScrollController _scrollController;
  String _searchQuery = '';
  bool _isLoading = true;
  bool _showNavChrome = true;

  @override
  void initState() {
    super.initState();
    _showNavChrome = widget.navVisible;
    _notesNotifier = ValueNotifier<List<Note>>(_notesService.notes);
    final initialNotes = _notesNotifier.value;
    _groupedNotes = ValueNotifier<Map<String, List<Note>>>(
      _notesService.groupNotesByDisplayDate(
        initialNotes.where((note) => !note.pinned).toList(),
      ),
    );
    _pinnedNotes = ValueNotifier<List<Note>>(
      initialNotes.where((note) => note.pinned).toList(),
    );
    _searchController = TextEditingController();
    _searchController.addListener(_handleSearchChanged);
    _searchFocusNode = FocusNode();
    _scrollController = ScrollController()
      ..addListener(_handleScrollDirectionChanged);
    _notesService.notesListenable.addListener(_handleNotesChanged);
    _preload();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onScrollVisibilityChange?.call(_showNavChrome);
    });
  }

  @override
  void didUpdateWidget(covariant NotesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.navVisibilityResetTick != oldWidget.navVisibilityResetTick) {
      _setNavChromeVisible(true, force: true);
    } else if (widget.navVisible != oldWidget.navVisible &&
        widget.navVisible != _showNavChrome) {
      _setNavChromeVisible(widget.navVisible, force: true);
    }
  }

  Future<void> _preload() async {
    final loaded = await _notesService.loadNotes();
    _notesNotifier.value = loaded;
    _applyFilter();
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openHighlights() async {
    final selected = await Navigator.of(context).push<HighlightEntry>(
      MaterialPageRoute(builder: (_) => const HighlightsScreen()),
    );
    if (selected != null) {
      widget.onHighlightSelected?.call(selected);
    }
  }

  void _handleNotesChanged() {
    _syncNotesFromService();
  }

  void _syncNotesFromService() {
    final latest = _notesService.notes;
    _notesNotifier.value = latest;
    _applyFilter();
  }

  @override
  void dispose() {
    _notesService.notesListenable.removeListener(_handleNotesChanged);
    _notesNotifier.dispose();
    _groupedNotes.dispose();
    _pinnedNotes.dispose();
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    _searchFocusNode.dispose();
    _scrollController
      ..removeListener(_handleScrollDirectionChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator.adaptive()),
      );
    }

    return ValueListenableBuilder<List<Note>>(
      valueListenable: _pinnedNotes,
      builder: (context, pinnedNotes, __) {
        return ValueListenableBuilder<Map<String, List<Note>>>(
          valueListenable: _groupedNotes,
          builder: (context, grouped, _) {
            final entries = grouped.entries.toList();
            final theme = Theme.of(context);
            final colorScheme = theme.colorScheme;
            final isDark = theme.brightness == Brightness.dark;
            final totalNotes =
                pinnedNotes.length +
                grouped.values.fold<int>(0, (sum, notes) => sum + notes.length);
            const double navBarHeight = 56;
            final media = MediaQuery.of(context);
            final bottomInset = media.padding.bottom + navBarHeight + 32;
            final bool hasResults =
                pinnedNotes.isNotEmpty ||
                entries.any((entry) => entry.value.isNotEmpty);

            final sectionWidgets = <Widget>[const SizedBox(height: 8)];

            if (hasResults) {
              if (pinnedNotes.isNotEmpty) {
                sectionWidgets.addAll([
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                    child: Text(
                      'Pinned',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface.withValues(
                          alpha: isDark ? 0.92 : 0.72,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: NotesSectionList(
                      notes: pinnedNotes,
                      metadataBuilder: _metadataFor,
                      leadingBuilder: (_) =>
                          const Icon(Icons.push_pin_outlined),
                      onNoteTap: _openNote,
                      onDelete: _handleDeleteNote,
                      onTogglePin: _handleTogglePin,
                      isCompact: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                ]);
              }
              for (final entry in entries) {
                sectionWidgets.addAll([
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                    child: Text(
                      entry.key,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface.withValues(
                          alpha: isDark ? 0.9 : 0.7,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: NotesSectionList(
                      notes: entry.value,
                      metadataBuilder: _metadataFor,
                      leadingBuilder: (note) => note.pinned
                          ? const Icon(Icons.push_pin_outlined)
                          : null,
                      onNoteTap: _openNote,
                      onDelete: _handleDeleteNote,
                      onTogglePin: _handleTogglePin,
                    ),
                  ),
                ]);
              }
              sectionWidgets.add(SizedBox(height: bottomInset + 72));
            } else {
              sectionWidgets.addAll([
                SizedBox(height: media.padding.top + 160),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.note_add_outlined,
                        size: 44,
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: isDark ? 0.5 : 0.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'No results',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface.withValues(
                            alpha: isDark ? 0.86 : 0.7,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _searchQuery.isEmpty
                            ? 'Start a new note or pin your favorites to see them here.'
                            : 'Try a different search term or clear the filter to view all notes.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: isDark ? 0.7 : 0.65,
                          ),
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
                SizedBox(height: bottomInset + 72),
              ]);
            }

            return Scaffold(
              backgroundColor: Colors.black,
              body: Stack(
                children: [
                  GestureDetector(
                    onTap: _toggleChrome,
                    child: CustomScrollView(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      slivers: [
                      SliverAppBar.large(
                        backgroundColor: Colors.black,
                        surfaceTintColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        stretch: true,
                        stretchTriggerOffset: 120,
                        onStretchTrigger: _handleStretchTrigger,
                        automaticallyImplyLeading: false,
                        leading: IconButton(
                          icon: const Icon(Icons.border_color_rounded),
                          tooltip: 'Highlights',
                          onPressed: _openHighlights,
                        ),
                        actions: [
                          IconButton(
                            icon: const Icon(Icons.more_horiz_rounded),
                            tooltip: 'More options',
                            onPressed: _showOverflowMenu,
                          ),
                        ],
                        flexibleSpace: LayoutBuilder(
                          builder: (context, constraints) {
                            final titleStyle = theme.textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w700);
                            final subtitleStyle = theme.textTheme.bodySmall
                                ?.copyWith(
                                  color: Colors.grey[500],
                                );
                            return FlexibleSpaceBar(
                              titlePadding: const EdgeInsetsDirectional.only(
                                start: 20,
                                bottom: 16,
                              ),
                              title: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Notes', style: titleStyle),
                                  Text(
                                    '$totalNotes Notes',
                                    style: subtitleStyle,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      SliverList(
                        delegate: SliverChildListDelegate(sectionWidgets),
                      ),
                    ],
                    ),
                  ),
                  Positioned(
                    left: 56,
                    right: 56,
                    top: media.padding.top + 8,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      opacity: _showNavChrome ? 1 : 0,
                      child: IgnorePointer(
                        ignoring: !_showNavChrome,
                        child: _buildTopSearchBar(context),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatDate(Note note) {
    final date = note.sortDate;
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.month}/${date.day}/${date.year}';
  }

  void _showOverflowMenu() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        void closeWithMessage(String message) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(this.context).showSnackBar(
            SnackBar(
              content: Text(message),
              duration: const Duration(seconds: 2),
            ),
          );
        }

        return SafeArea(
          child: ListTileTheme(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.grid_view_rounded),
                  title: const Text('View as Gallery'),
                  onTap: () => closeWithMessage('Gallery view coming soon.'),
                ),
                ListTile(
                  leading: const Icon(Icons.sort_rounded),
                  title: const Text('Sort By…'),
                  onTap: () => closeWithMessage('Sorting options coming soon.'),
                ),
                ListTile(
                  leading: const Icon(Icons.calendar_view_month_rounded),
                  title: const Text('Group By Date…'),
                  onTap: () =>
                      closeWithMessage('Date grouping settings coming soon.'),
                ),
                const Divider(height: 8),
                ListTile(
                  leading: const Icon(Icons.create_new_folder_outlined),
                  title: const Text('New Folder'),
                  onTap: () =>
                      closeWithMessage('Folder management coming soon.'),
                ),
                ListTile(
                  leading: const Icon(Icons.select_all_outlined),
                  title: const Text('Select Notes'),
                  onTap: () => closeWithMessage('Multi-select coming soon.'),
                ),
                ListTile(
                  leading: const Icon(Icons.image_rounded),
                  title: const Text('View Attachments'),
                  onTap: () =>
                      closeWithMessage('Attachment viewer coming soon.'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _metadataFor(Note note) {
    final date = _formatDate(note);
    final sections = <String>[date];
    if (note.folder != null && note.folder!.isNotEmpty) {
      sections.add(note.folder!);
    }
    if (note.preview.isNotEmpty) {
      sections.add(note.preview);
    }
    return sections.join(' • ');
  }

  void _openNote(Note note) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          return NoteEditorScreen(noteId: note.id);
        },
      ),
    );
  }

  void _handleSearchChanged() {
    final text = _searchController.text;
    if (text == _searchQuery) return;
    setState(() => _searchQuery = text);
    _applyFilter();
  }

  void _handleScrollDirectionChanged() {
    if (!_scrollController.hasClients) return;
    final direction = _scrollController.position.userScrollDirection;
    if (direction == ScrollDirection.reverse) {
      _setNavChromeVisible(false);
    } else if (direction == ScrollDirection.forward) {
      _setNavChromeVisible(true);
    }
  }

  void _setNavChromeVisible(bool visible, {bool force = false}) {
    if (!force && visible == _showNavChrome) return;
    if (!mounted) return;
    setState(() => _showNavChrome = visible);
    widget.onScrollVisibilityChange?.call(visible);
  }

  void _toggleChrome() {
    // Toggle chrome visibility (search bar and new note button)
    setState(() {
      _showNavChrome = !_showNavChrome;
    });
    // Toggle navbar visibility
    widget.onScrollVisibilityChange?.call(_showNavChrome);
  }

  void _applyFilter() {
    final query = _searchQuery.trim().toLowerCase();
    final base = _notesNotifier.value;
    final filtered = query.isEmpty
        ? base
        : base.where((note) {
            final haystack = <String>[
              note.title,
              note.preview,
              note.folder ?? '',
              ...note.tags,
            ].join(' ').toLowerCase();
            return haystack.contains(query);
          }).toList();
    final pinned = filtered.where((note) => note.pinned).toList();
    final unpinned = filtered.where((note) => !note.pinned).toList();
    _pinnedNotes.value = pinned;
    _groupedNotes.value = _notesService.groupNotesByDisplayDate(unpinned);
  }

  Future<void> _handleStretchTrigger() async {
    if (!mounted) return;
    _setNavChromeVisible(true, force: true);
  }

  Widget _buildTopSearchBar(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 250),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Search',
                        hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 15,
                          fontWeight: FontWeight.w400,
                        ),
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      textInputAction: TextInputAction.search,
                      cursorColor: scheme.primary,
                      style: const TextStyle(fontSize: 15, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'New note',
          iconSize: 22,
          padding: const EdgeInsets.all(8),
          onPressed: _composeNewNote,
          icon: const Icon(Icons.edit_outlined, color: Colors.white),
        ),
      ],
    );
  }

  Future<void> _handleTogglePin(Note note) async {
    final newPinned = !note.pinned;
    await _notesService.togglePinned(note.id);
    if (!mounted) return;
    _syncNotesFromService();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(newPinned ? 'Pinned to top' : 'Unpinned'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<bool> _handleDeleteNote(Note note) async {
    await _notesService.deleteNote(note.id);
    if (!mounted) return true;
    _syncNotesFromService();
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            note.title.isEmpty ? 'Deleted note' : 'Deleted "${note.title}"',
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () {
              _notesService.addNote(note).then((_) {
                if (!mounted) return;
                _syncNotesFromService();
              });
            },
          ),
        ),
      );
    return true;
  }

  Future<void> _composeNewNote() async {
    final note = await _notesService.createEmptyNote();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NoteEditorScreen(noteId: note.id)),
    );
  }
}
