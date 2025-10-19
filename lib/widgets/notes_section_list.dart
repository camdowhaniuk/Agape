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
  });

  final List<Note> notes;
  final NoteMetadataBuilder metadataBuilder;
  final NoteWidgetBuilder? leadingBuilder;
  final NoteWidgetBuilder? trailingBuilder;
  final ValueChanged<Note>? onNoteTap;

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
        Color.alphaBlend(overlayPrimary, baseHigh),
        Color.alphaBlend(overlayOutline, baseLow),
      ],
    );

    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
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
                  NoteCardTile(
                    title: notes[i].title,
                    metadata: metadataBuilder(notes[i]),
                    leading: leadingBuilder?.call(notes[i]),
                    trailing: trailingBuilder?.call(notes[i]),
                    onTap: onNoteTap != null
                        ? () => onNoteTap!(notes[i])
                        : null,
                  ),
                  if (i != notes.length - 1)
                    Divider(
                      height: 1,
                      indent: 20,
                      endIndent: 20,
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
