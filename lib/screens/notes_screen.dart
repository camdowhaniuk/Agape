import 'package:flutter/material.dart';

import '../models/note.dart';
import '../services/notes_service.dart';
import 'note_editor_screen.dart';
import '../widgets/notes_section_list.dart';

class NotesScreen extends StatefulWidget {
  const NotesScreen({super.key});

  @override
  State<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends State<NotesScreen> {
  final NotesService _notesService = NotesService.instance;
  late final ValueNotifier<List<Note>> _notesNotifier;
  late final ValueNotifier<Map<String, List<Note>>> _groupedNotes;
  late final TextEditingController _searchController;
  String _searchQuery = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _notesNotifier = ValueNotifier<List<Note>>(_notesService.notes);
    _groupedNotes = ValueNotifier<Map<String, List<Note>>>(
      _notesService.groupNotesByDisplayDate(_notesNotifier.value),
    );
    _searchController = TextEditingController();
    _searchController.addListener(_handleSearchChanged);
    _notesService.notesListenable.addListener(_handleNotesChanged);
    _preload();
  }

  Future<void> _preload() async {
    final loaded = await _notesService.loadNotes();
    _notesNotifier.value = loaded;
    _groupedNotes.value = _notesService.groupNotesByDisplayDate(loaded);
    if (mounted) {
      setState(() => _isLoading = false);
    }
    _applyFilter();
  }

  void _handleNotesChanged() {
    final latest = _notesService.notes;
    _notesNotifier.value = latest;
    _applyFilter();
  }

  @override
  void dispose() {
    _notesService.notesListenable.removeListener(_handleNotesChanged);
    _notesNotifier.dispose();
    _groupedNotes.dispose();
    _searchController
      ..removeListener(_handleSearchChanged)
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

    return ValueListenableBuilder<Map<String, List<Note>>>(
      valueListenable: _groupedNotes,
      builder: (context, grouped, _) {
        final entries = grouped.entries.toList();
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        final backgroundGradient = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colorScheme.surfaceBright,
            Color.alphaBlend(
              colorScheme.primary.withValues(alpha: isDark ? 0.08 : 0.04),
              colorScheme.surface,
            ),
            colorScheme.surfaceDim,
          ],
        );
        final totalNotes = grouped.values.fold<int>(
          0,
          (sum, notes) => sum + notes.length,
        );
        const double navBarHeight = 58;
        final media = MediaQuery.of(context);
        final bottomInset = media.padding.bottom + navBarHeight + 32;
        final sectionWidgets = <Widget>[
          const SizedBox(height: 8),
          for (final entry in entries) ...[
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
                leadingBuilder: (note) =>
                    note.pinned ? const Icon(Icons.push_pin_outlined) : null,
                onNoteTap: _openNote,
              ),
            ),
          ],
          SizedBox(height: bottomInset + 72),
        ];

        return Scaffold(
          backgroundColor: colorScheme.surfaceDim,
          body: Stack(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(gradient: backgroundGradient),
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  slivers: [
                    SliverAppBar.large(
                      backgroundColor: Colors.transparent,
                      surfaceTintColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      leading: IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded),
                        onPressed: () => Navigator.of(context).maybePop(),
                        tooltip: 'Folders',
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
                              ?.copyWith(color: colorScheme.onSurfaceVariant);
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
                                Text('$totalNotes Notes', style: subtitleStyle),
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
                left: 0,
                right: 0,
                bottom: navBarHeight + media.padding.bottom + 16,
                child: _buildBottomBar(context),
              ),
            ],
          ),
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
        return SafeArea(
          child: ListTileTheme(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.create_new_folder_outlined),
                  title: const Text('New Folder'),
                  onTap: () => Navigator.of(context).pop(),
                ),
                ListTile(
                  leading: const Icon(Icons.select_all_outlined),
                  title: const Text('Select Notes'),
                  onTap: () => Navigator.of(context).pop(),
                ),
                ListTile(
                  leading: const Icon(Icons.view_list_rounded),
                  title: const Text('View Options'),
                  onTap: () => Navigator.of(context).pop(),
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
      MaterialPageRoute(builder: (context) {
        return NoteEditorScreen(noteId: note.id);
      }),
    );
  }

  void _handleSearchChanged() {
    final text = _searchController.text;
    if (text == _searchQuery) return;
    setState(() => _searchQuery = text);
    _applyFilter();
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
    _groupedNotes.value = _notesService.groupNotesByDisplayDate(
      filtered.toList(),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final searchBackground = Color.alphaBlend(
      scheme.primary.withValues(alpha: isDark ? 0.14 : 0.08),
      scheme.surfaceContainerHigh,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: searchBackground,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.18),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Search',
                          hintStyle: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                        textInputAction: TextInputAction.search,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Voice search',
                      splashRadius: 22,
                      onPressed: _handleMicPressed,
                      icon: Icon(
                        Icons.mic_none_rounded,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          FloatingActionButton(
            heroTag: 'notes-compose',
            onPressed: _composeNewNote,
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: const Icon(Icons.edit_note_rounded),
          ),
        ],
      ),
    );
  }

  void _handleMicPressed() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('TODO: Implement voice search & dictation.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _composeNewNote() async {
    final note = await _notesService.createEmptyNote();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NoteEditorScreen(noteId: note.id),
      ),
    );
  }
}
