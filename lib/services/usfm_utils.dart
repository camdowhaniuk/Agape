String cleanUsfmWord(String text) {
  return text
      .replaceAll('\r', '')
      .replaceAll('\n', ' ')
      .replaceAll(RegExp(r'\\\+w\*'), '')
      .replaceAll(RegExp(r'\\\+w'), '')
      .replaceAll(RegExp(r'\\w\*'), '')
      .replaceAll(RegExp(r'\\w'), '')
      .replaceAll('+w', '')
      .replaceAll(r'\+w', '')
      .replaceAll(RegExp(r'\|[^\s]+'), '');
}
