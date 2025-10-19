import 'package:flutter/material.dart';

class NoteCardTile extends StatelessWidget {
  const NoteCardTile({
    super.key,
    required this.title,
    required this.metadata,
    this.leading,
    this.trailing,
    this.onTap,
    this.padding = const EdgeInsets.fromLTRB(20, 14, 20, 14),
  });

  final String title;
  final String metadata;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: scheme.onSurface.withValues(alpha: 0.92),
    );
    final metadataStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant.withValues(alpha: 0.86),
    );

    final rowChildren = <Widget>[
      if (leading != null) ...[
        Padding(
          padding: const EdgeInsets.only(right: 12, top: 2),
          child: IconTheme.merge(
            data: IconThemeData(
              size: 18,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
            child: leading!,
          ),
        ),
      ],
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: titleStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              metadata,
              style: metadataStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      if (trailing != null) ...[
        const SizedBox(width: 12),
        DefaultTextStyle.merge(
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
          child: trailing!,
        ),
      ],
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: padding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: rowChildren,
          ),
        ),
      ),
    );
  }
}
