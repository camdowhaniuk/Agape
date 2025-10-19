import 'package:flutter/material.dart';

import '../models/note.dart';
import '../services/notes_service.dart';

class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({super.key, required this.noteId});

  final String noteId;

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final NotesService _notesService = NotesService.instance;

  late Note _note;
  late TextEditingController _titleController;
  late TextEditingController _bodyController;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  void _loadNote() {
    final note = _notesService.notes.firstWhere(
      (note) => note.id == widget.noteId,
      orElse: () => throw ArgumentError('Note not found'),
    );
    _note = note;
    _titleController = TextEditingController(text: note.title);
    _bodyController = TextEditingController(text: note.preview);
    _loading = false;
    _titleController.addListener(_handleTitleChanged);
    _bodyController.addListener(_handleBodyChanged);
  }

  @override
  void dispose() {
    _titleController.removeListener(_handleTitleChanged);
    _bodyController.removeListener(_handleBodyChanged);
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _handleTitleChanged() async {
    final text = _titleController.text;
    if (text == _note.title) return;
    _note = _note.copyWith(title: text, updatedAt: DateTime.now());
    await _notesService.updateNote(_note.id, transform: (_) => _note);
    setState(() {});
  }

  Future<void> _handleBodyChanged() async {
    final text = _bodyController.text;
    if (text == _note.preview) return;
    _note = _note.copyWith(preview: text, updatedAt: DateTime.now());
    await _notesService.updateNote(_note.id, transform: (_) => _note);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final dateText = _formatDate(_note.updatedAt ?? _note.createdAt);

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz_rounded),
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (context) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.push_pin_outlined),
                        title: Text(_note.pinned ? 'Unpin' : 'Pin'),
                        onTap: () {
                          Navigator.of(context).pop();
                          _togglePinned();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.delete_outline_rounded),
                        title: const Text('Delete'),
                        onTap: () {
                          Navigator.of(context).pop();
                          _deleteNote();
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Chip(icon: Icons.calendar_today_rounded, label: dateText),
                if (_note.folder != null && _note.folder!.isNotEmpty)
                  _Chip(icon: Icons.folder_outlined, label: _note.folder!),
                if (_note.tags.isNotEmpty)
                  _Chip(icon: Icons.tag_outlined, label: _note.tags.join(', ')),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                hintText: 'Title',
                border: InputBorder.none,
              ),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _bodyController,
                decoration: const InputDecoration(
                  hintText: 'Start writing…',
                  border: InputBorder.none,
                ),
                keyboardType: TextInputType.multiline,
                maxLines: null,
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          12 + MediaQuery.of(context).padding.bottom,
        ),
        child: _EditorToolbar(isDark: isDark),
      ),
    );
  }

  Future<void> _togglePinned() async {
    _note = _note.copyWith(pinned: !_note.pinned, updatedAt: DateTime.now());
    await _notesService.updateNote(_note.id, transform: (_) => _note);
    if (mounted) setState(() {});
  }

  Future<void> _deleteNote() async {
    await _notesService.deleteNote(_note.id);
    if (mounted) Navigator.of(context).pop();
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final difference = today.difference(target).inDays;
    if (difference == 0) {
      return 'Edited Today';
    }
    if (difference == 1) {
      return 'Edited Yesterday';
    }
    return 'Edited ${date.month}/${date.day}/${date.year}';
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.onSecondaryContainer),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  const _EditorToolbar({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = isDark
        ? const Color(0xFF242429).withOpacity(0.92)
        : scheme.surfaceContainerHigh;

    return Material(
      elevation: isDark ? 6 : 3,
      borderRadius: BorderRadius.circular(22),
      color: background,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.check_box_outlined),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('TODO: Insert checklist item')),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.brush_outlined),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('TODO: Pen annotations')),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.image_outlined),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('TODO: Insert image')),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.mic_none_rounded),
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('TODO: Start recording')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
