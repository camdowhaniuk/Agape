import 'package:agape/utils/scripture_reference.dart';
import 'package:agape/widgets/markdown_message.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders markdown with scripture capsules', (tester) async {
    final taps = <ScriptureReference>[];
    const markdown = '''
### Heading

This is **bold** and _italic_ with Matthew 5:22, 10:28.

- First bullet referencing John 3:16.
''';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownMessage(
            markdown: markdown,
            baseStyle: const TextStyle(fontSize: 16),
            isDark: false,
            linkColor: Colors.purple,
            onScriptureTap: taps.add,
          ),
        ),
      ),
    );

    final combinedText = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((widget) => widget.text.toPlainText())
        .join('\n');

    expect(combinedText, contains('Heading'));
    expect(combinedText, contains('bold'));

    final capsules = find.byIcon(Icons.menu_book_rounded);
    expect(capsules, findsNWidgets(3));

    await tester.tap(capsules.first);
    await tester.pump();

    expect(taps, isNotEmpty);
    expect(taps.first.book, isNotEmpty);
  });
}
