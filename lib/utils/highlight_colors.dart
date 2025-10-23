import 'package:flutter/material.dart';

import '../models/highlight.dart';

const List<Color> kHighlightPaletteLight = [
  Color(0xB3FF0000), // Red
  Color(0xB3FF9F40), // Orange
  Color(0xB3FFD93D), // Yellow
  Color(0xB36BCF7E), // Green
  Color(0xB34D9DE0), // Blue
  Color(0xB39B6BCF), // Indigo/Purple
  Color(0xB3E17BFF), // Violet/Pink
];

const List<Color> kHighlightPaletteDark = [
  Color(0x80FF0000), // Red
  Color(0x80FF8A50), // Orange
  Color(0x80FFD740), // Yellow
  Color(0x8069F0AE), // Green
  Color(0x8040C4FF), // Blue
  Color(0x80B388FF), // Indigo/Purple
  Color(0x80EA80FC), // Violet/Pink
];

List<Color> highlightPalette(bool dark) =>
    dark ? kHighlightPaletteDark : kHighlightPaletteLight;

Color highlightColorForId(int id, {required bool dark}) {
  final palette = highlightPalette(dark);
  if (palette.isEmpty) {
    return dark ? const Color(0x80FFFF00) : const Color(0xB3FFFF00);
  }
  final safeIndex = id < 0 ? 0 : id % palette.length;
  return palette[safeIndex];
}

Color highlightColorForHighlight(
  VerseHighlight highlight, {
  required bool dark,
}) {
  return highlightColorForValues(
    colorId: highlight.colorId,
    colorValue: highlight.colorValue,
    dark: dark,
  );
}

Color highlightColorForPassageHighlight(
  PassageHighlight highlight, {
  required bool dark,
}) {
  return highlightColorForValues(
    colorId: highlight.colorId,
    colorValue: highlight.colorValue,
    dark: dark,
  );
}

Color highlightColorForValues({
  required int colorId,
  required int? colorValue,
  required bool dark,
}) {
  final value = colorValue;
  if (value != null) {
    return Color(value);
  }
  return highlightColorForId(colorId, dark: dark);
}
