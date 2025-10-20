import 'package:flutter/material.dart';

import '../models/highlight.dart';

const List<Color> kHighlightPaletteLight = [
  Color(0xB3FFCDD2), // Light red/pink
  Color(0xB3FF8A80), // Coral red
  Color(0xB3EF5350), // Red
  Color(0xB3FFE0E0), // Very light pink
  Color(0xB3FFC1C1), // Light pink
  Color(0xB3FF6B6B), // Medium red
  Color(0xB3D32F2F), // Dark red
  Color(0xB3B71C1C), // Deep red
  Color(0xB3FFB3BA), // Soft pink
];

const List<Color> kHighlightPaletteDark = [
  Color(0x80FF6B6B), // Bright red
  Color(0x80EF5350), // Red
  Color(0x80E57373), // Light red
  Color(0x80F44336), // Vibrant red
  Color(0x80FF5252), // Accent red
  Color(0x80D32F2F), // Dark red
  Color(0x80C62828), // Deeper red
  Color(0x80FFCDD2), // Light pink
  Color(0x80FF8A80), // Coral
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
