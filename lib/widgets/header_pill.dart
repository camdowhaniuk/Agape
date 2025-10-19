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
  bool _isPressed = false;

  void _handleHighlight(bool value) {
    if (!mounted) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isDark = widget.isDark ?? theme.brightness == Brightness.dark;

    final Color background = isDark
        ? const Color(0xFF242429).withOpacity(0.9)
        : theme.colorScheme.surface.withOpacity(0.96);
    final Color borderColor = isDark ? Colors.white10 : Colors.black12.withOpacity(0.12);
    final Color foreground = isDark
        ? Colors.white.withOpacity(0.92)
        : theme.colorScheme.onSurface.withOpacity(0.9);
    final Color iconColor = isDark
        ? Colors.white.withOpacity(0.9)
        : theme.colorScheme.onSurface.withOpacity(0.85);
    final Color splashColor = theme.colorScheme.primary.withOpacity(isDark ? 0.22 : 0.16);

    final double blur = _isPressed ? 16 : 10;
    final double spread = _isPressed ? 0.6 : 0.2;
    final double shadowOpacity = isDark
        ? (_isPressed ? 0.5 : 0.35)
        : (_isPressed ? 0.2 : 0.14);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        splashColor: splashColor,
        highlightColor: Colors.transparent,
        onHighlightChanged: _handleHighlight,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: Color.fromRGBO(0, 0, 0, shadowOpacity),
                blurRadius: blur,
                spreadRadius: spread,
                offset: const Offset(0, 6),
              ),
            ],
          ),
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
    );
  }
}
