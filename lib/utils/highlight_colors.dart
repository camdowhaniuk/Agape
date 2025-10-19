import 'package:flutter/material.dart';

const List<Color> kHighlightPaletteLight = [
  Color(0xB3FFF176),
  Color(0xB3FFAB91),
  Color(0xB3A5D6A7),
  Color(0xB381D4FA),
  Color(0xB3CE93D8),
];

const List<Color> kHighlightPaletteDark = [
  Color(0x80B39D24),
  Color(0x80B26A56),
  Color(0x806BA173),
  Color(0x804E8AA8),
  Color(0x808A6BA5),
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
