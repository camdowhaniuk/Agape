import 'package:flutter/material.dart';
import 'package:markdown/markdown.dart' as md;

import '../utils/scripture_reference.dart';

typedef ScriptureTapCallback = void Function(ScriptureReference reference);

class MarkdownMessage extends StatelessWidget {
  const MarkdownMessage({
    super.key,
    required this.markdown,
    required this.baseStyle,
    required this.isDark,
    required this.linkColor,
    required this.onScriptureTap,
  });

  final String markdown;
  final TextStyle baseStyle;
  final bool isDark;
  final Color linkColor;
  final ScriptureTapCallback onScriptureTap;

  @override
  Widget build(BuildContext context) {
    final document = md.Document(
      encodeHtml: false,
      extensionSet: md.ExtensionSet.gitHubFlavored,
    );
    final nodes = document.parseLines(_sanitize(markdown).split('\n'));
    final blocks = <Widget>[];
    final renderContext = _RenderContext(
      baseStyle: baseStyle,
      isDark: isDark,
      linkColor: linkColor,
      onScriptureTap: onScriptureTap,
    );

    for (final node in nodes) {
      final block = _buildBlock(node, renderContext);
      if (block == null) continue;
      if (blocks.isNotEmpty) blocks.add(const SizedBox(height: 12));
      blocks.add(block);
    }

    if (blocks.isEmpty) {
      return SelectionArea(
        child: RichText(
          text: TextSpan(style: baseStyle, text: markdown),
        ),
      );
    }

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: blocks,
      ),
    );
  }

  String _sanitize(String value) {
    return value.replaceAll('\r\n', '\n');
  }
}

class _RenderContext {
  _RenderContext({
    required this.baseStyle,
    required this.isDark,
    required this.linkColor,
    required this.onScriptureTap,
  });

  final TextStyle baseStyle;
  final bool isDark;
  final Color linkColor;
  final ScriptureTapCallback onScriptureTap;
}

Widget? _buildBlock(md.Node node, _RenderContext context) {
  if (node is md.Element) {
    switch (node.tag) {
      case 'p':
        return _buildParagraph(node.children ?? const <md.Node>[], context);
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        final level = int.tryParse(node.tag.substring(1)) ?? 3;
        final double scale = switch (level) {
          1 => 1.5,
          2 => 1.35,
          3 => 1.2,
          4 => 1.1,
          _ => 1.0,
        };
        final headingStyle = context.baseStyle.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: context.baseStyle.fontSize != null
              ? context.baseStyle.fontSize! * scale
              : null,
        );
        return _buildParagraph(
          node.children ?? const <md.Node>[],
          context,
          style: headingStyle,
        );
      case 'ul':
        return _buildList(node, false, context);
      case 'ol':
        return _buildList(node, true, context);
      case 'blockquote':
        return _buildBlockQuote(node, context);
      default:
        return _buildParagraph(node.children ?? const <md.Node>[], context);
    }
  } else if (node is md.Text) {
    if (node.text.trim().isEmpty) return null;
    return _buildParagraph(<md.Node>[node], context);
  }
  return null;
}

Widget _buildParagraph(List<md.Node> nodes, _RenderContext context, {TextStyle? style}) {
  final span = TextSpan(
    style: style ?? context.baseStyle,
    children: _buildInline(nodes, style ?? context.baseStyle, context),
  );

  return RichText(text: span, textAlign: TextAlign.start);
}

Widget _buildBlockQuote(md.Element element, _RenderContext context) {
  final childBlocks = <Widget>[];
  for (final child in element.children ?? const <md.Node>[]) {
    final block = _buildBlock(child, context);
    if (block == null) continue;
    if (childBlocks.isNotEmpty) childBlocks.add(const SizedBox(height: 8));
    childBlocks.add(block);
  }

  return Container(
    decoration: BoxDecoration(
      border: Border(left: BorderSide(color: context.linkColor.withOpacity(0.4), width: 3)),
    ),
    padding: const EdgeInsets.only(left: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: childBlocks,
    ),
  );
}

Widget _buildList(md.Element element, bool ordered, _RenderContext context) {
  final items = <Widget>[];
  final children = element.children?.whereType<md.Element>()
          .where((e) => e.tag == 'li')
          .toList() ??
      const <md.Element>[];
  final startIndex = ordered
      ? int.tryParse(element.attributes['start'] ?? '') ?? 1
      : 1;
  for (var i = 0; i < children.length; i++) {
    final item = children[i];
    final marker = ordered ? '${startIndex + i}.' : '•';
    items.add(_buildListItem(marker, item, context));
    if (i != children.length - 1) {
      items.add(const SizedBox(height: 6));
    }
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: items,
  );
}

Widget _buildListItem(String marker, md.Element item, _RenderContext context) {
  final blocks = <Widget>[];
  for (final child in item.children ?? const <md.Node>[]) {
    final block = _buildBlock(child, context);
    if (block != null) {
      blocks.add(block);
    }
  }
  if (blocks.isEmpty) {
    blocks.add(_buildParagraph(const <md.Node>[], context));
  }

  final first = blocks.first;
  final remainder = blocks.skip(1).toList();

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Text(
              marker,
              style: context.baseStyle.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(child: first),
        ],
      ),
      for (final block in remainder)
        Padding(
          padding: const EdgeInsets.only(left: 30, top: 8),
          child: block,
        ),
    ],
  );
}

List<InlineSpan> _buildInline(List<md.Node> nodes, TextStyle currentStyle, _RenderContext context) {
  final spans = <InlineSpan>[];
  for (final node in nodes) {
    if (node is md.Text) {
      spans.addAll(_buildScriptureSpans(node.text, currentStyle, context));
    } else if (node is md.Element) {
      switch (node.tag) {
        case 'strong':
        case 'b':
          final boldStyle = currentStyle.copyWith(fontWeight: FontWeight.w700);
          spans.add(TextSpan(
            style: boldStyle,
            children: _buildInline(node.children ?? const <md.Node>[], boldStyle, context),
          ));
          break;
        case 'em':
        case 'i':
          final italicStyle = currentStyle.copyWith(fontStyle: FontStyle.italic);
          spans.add(TextSpan(
            style: italicStyle,
            children: _buildInline(node.children ?? const <md.Node>[], italicStyle, context),
          ));
          break;
        case 'code':
          spans.add(TextSpan(
            style: currentStyle.copyWith(
              fontFamily: 'monospace',
              backgroundColor: context.linkColor.withOpacity(0.12),
            ),
            text: node.textContent,
          ));
          break;
        case 'br':
          spans.add(const TextSpan(text: '\n'));
          break;
        case 'a':
          final linkStyle = currentStyle.copyWith(color: context.linkColor);
          spans.addAll(_buildScriptureSpans(node.textContent, linkStyle, context));
          break;
        default:
          spans.addAll(_buildInline(node.children ?? const <md.Node>[], currentStyle, context));
          break;
      }
    }
  }
  return spans;
}

List<InlineSpan> _buildScriptureSpans(String text, TextStyle style, _RenderContext context) {
  if (text.isEmpty) return const <InlineSpan>[];
  final matches = ScriptureReferenceParser.extractMatches(text);
  if (matches.isEmpty) {
    return <InlineSpan>[TextSpan(text: text, style: style)];
  }

  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final match in matches) {
    if (match.start > cursor) {
      spans.add(TextSpan(text: text.substring(cursor, match.start), style: style));
    }

    spans.add(WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: _ScriptureCapsule(
        label: match.matchedText.trim(),
        style: style,
        isDark: context.isDark,
        linkColor: context.linkColor,
        onTap: () => context.onScriptureTap(match.reference),
      ),
    ));

    cursor = match.end;
  }

  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: style));
  }

  return spans;
}

class _ScriptureCapsule extends StatelessWidget {
  const _ScriptureCapsule({
    required this.label,
    required this.style,
    required this.isDark,
    required this.linkColor,
    required this.onTap,
  });

  final String label;
  final TextStyle style;
  final bool isDark;
  final Color linkColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color textColor = isDark ? Colors.white : linkColor;
    final BorderRadius radius = BorderRadius.circular(999);
    return Semantics(
      button: true,
      label: 'Open $label',
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          splashColor: linkColor.withOpacity(isDark ? 0.24 : 0.18),
          highlightColor: linkColor.withOpacity(isDark ? 0.18 : 0.1),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: linkColor.withOpacity(isDark ? 0.28 : 0.16),
              borderRadius: radius,
              border: Border.all(color: linkColor.withOpacity(isDark ? 0.55 : 0.28), width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.menu_book_rounded, size: 14, color: textColor),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: style.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
