import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';

class HeaderPill extends StatefulWidget {
  const HeaderPill({super.key, required this.title, this.isDark, this.onTap});

  final String title;
  final bool? isDark;
  final VoidCallback? onTap;

  @override
  State<HeaderPill> createState() => _HeaderPillState();
}

class _HeaderPillState extends State<HeaderPill> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isDark = widget.isDark ?? theme.brightness == Brightness.dark;

    final Color foreground = isDark
        ? Colors.white.withValues(alpha: 0.92)
        : theme.colorScheme.onSurface.withValues(alpha: 0.9);
    final Color iconColor = isDark
        ? Colors.white.withValues(alpha: 0.9)
        : theme.colorScheme.onSurface.withValues(alpha: 0.85);
    final Color splashColor = theme.colorScheme.primary.withValues(alpha: isDark ? 0.22 : 0.16);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            offset: const Offset(0, 8),
            blurRadius: 24,
            spreadRadius: -4,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            offset: const Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              splashColor: splashColor,
              highlightColor: Colors.transparent,
              onTap: widget.onTap,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: const Color(0xFF1C1C1E).withValues(alpha: 0.2),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 0.5,
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                        style: TextStyle(
                          color: foreground,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.expand_more_rounded, size: 20, color: iconColor),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
