import 'package:flutter/material.dart';

import '../models/note.dart';
import 'note_card_tile.dart';

typedef NoteMetadataBuilder = String Function(Note note);
typedef NoteWidgetBuilder = Widget? Function(Note note);

class NotesSectionList extends StatelessWidget {
  const NotesSectionList({
    super.key,
    required this.notes,
    required this.metadataBuilder,
    this.leadingBuilder,
    this.trailingBuilder,
    this.onNoteTap,
    this.onDelete,
    this.onTogglePin,
    this.isCompact = false,
    this.tilePadding,
  });

  final List<Note> notes;
  final NoteMetadataBuilder metadataBuilder;
  final NoteWidgetBuilder? leadingBuilder;
  final NoteWidgetBuilder? trailingBuilder;
  final ValueChanged<Note>? onNoteTap;
  final Future<bool> Function(Note note)? onDelete;
  final Future<void> Function(Note note)? onTogglePin;
  final bool isCompact;
  final EdgeInsetsGeometry? tilePadding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final overlayPrimary = scheme.primary.withValues(
      alpha: isDark ? 0.10 : 0.06,
    );
    final overlayOutline = scheme.outline.withValues(
      alpha: isDark ? 0.08 : 0.04,
    );
    final baseHigh = scheme.surfaceContainerHighest;
    final baseLow = scheme.surfaceContainerHigh;
    final gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        Color.alphaBlend(
          overlayPrimary,
          isCompact ? scheme.surfaceContainerHigh : baseHigh,
        ),
        Color.alphaBlend(overlayOutline, isCompact ? scheme.surface : baseLow),
      ],
    );
    final borderRadius = BorderRadius.circular(isCompact ? 20 : 24);
    final resolvedTilePadding =
        tilePadding ??
        (isCompact
            ? const EdgeInsets.fromLTRB(18, 10, 18, 10)
            : const EdgeInsets.fromLTRB(20, 14, 20, 14));

    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: isDark ? 0.12 : 0.08),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(gradient: gradient),
            child: Column(
              children: [
                for (var i = 0; i < notes.length; i++) ...[
                  _SwipeWrapper(
                    key: ValueKey(notes[i].id),
                    note: notes[i],
                    onDelete: onDelete,
                    onTogglePin: onTogglePin,
                    child: NoteCardTile(
                      title: notes[i].title,
                      metadata: metadataBuilder(notes[i]),
                      leading: leadingBuilder?.call(notes[i]),
                      trailing: trailingBuilder?.call(notes[i]),
                      onTap: onNoteTap != null
                          ? () => onNoteTap!(notes[i])
                          : null,
                      padding: resolvedTilePadding,
                    ),
                  ),
                  if (i != notes.length - 1)
                    Divider(
                      height: 1,
                      indent: isCompact ? 16 : 20,
                      endIndent: isCompact ? 16 : 20,
                      color: scheme.outlineVariant.withValues(
                        alpha: isDark ? 0.2 : 0.14,
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SwipeWrapper extends StatelessWidget {
  const _SwipeWrapper({
    super.key,
    required this.note,
    required this.child,
    this.onDelete,
    this.onTogglePin,
  });

  final Note note;
  final Widget child;
  final Future<bool> Function(Note note)? onDelete;
  final Future<void> Function(Note note)? onTogglePin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Dismissible(
      key: ValueKey('note-${note.id}'),
      direction: DismissDirection.horizontal,
      background: _SwipeBackground(
        alignment: Alignment.centerLeft,
        color: scheme.tertiaryContainer,
        icon: note.pinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
        label: note.pinned ? 'Unpin' : 'Pin',
        foregroundColor: scheme.onTertiaryContainer,
      ),
      secondaryBackground: _SwipeBackground(
        alignment: Alignment.centerRight,
        color: scheme.errorContainer,
        icon: Icons.delete_outline_rounded,
        label: 'Delete',
        foregroundColor: scheme.onErrorContainer,
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          if (onTogglePin != null) {
            await onTogglePin!(note);
          }
          return false;
        }
        if (direction == DismissDirection.endToStart) {
          if (onDelete == null) return false;
          final shouldDelete = await onDelete!(note);
          return shouldDelete;
        }
        return false;
      },
      child: child,
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
    required this.foregroundColor,
  });

  final Alignment alignment;
  final Color color;
  final Color foregroundColor;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
      ),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: alignment == Alignment.centerLeft
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.end,
        children: [
          Icon(icon, color: foregroundColor),
          const SizedBox(height: 4),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: foregroundColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
