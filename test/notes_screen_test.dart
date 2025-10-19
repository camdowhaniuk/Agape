import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:agape/models/note.dart';
import 'package:agape/screens/notes_screen.dart';
import 'package:agape/services/notes_service.dart';

void main() {
  final NotesService service = NotesService.instance;

  Note _note({
    required String id,
    required String title,
    required DateTime createdAt,
    String preview = '',
    String? folder,
    bool pinned = false,
  }) {
    return Note(
      id: id,
      title: title,
      preview: preview,
      createdAt: createdAt,
      folder: folder,
      pinned: pinned,
    );
  }

  group('NotesScreen', () {
    late DateTime now;

    setUp(() {
      now = DateTime.now();
      final notes = <Note>[
        _note(
          id: 'today',
          title: 'Today Journal',
          preview: 'Reflection on John 15.',
          createdAt: now,
          folder: 'Devotions',
          pinned: true,
        ),
        _note(
          id: 'yesterday',
          title: 'Yesterday Checklist',
          preview: 'Follow up items.',
          createdAt: now.subtract(const Duration(days: 1)),
          folder: 'Tasks',
        ),
        _note(
          id: 'archive',
          title: 'Archive Summary',
          preview: 'Monthly review',
          createdAt: now.subtract(const Duration(days: 60)),
          folder: 'Archive',
        ),
      ];
      service.replaceAllNotes(notes);
    });

    testWidgets('renders grouped sections and note cards', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: NotesScreen()));

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.text('Notes'), findsWidgets);
      expect(find.text('Pinned'), findsOneWidget);
      expect(find.text('Today Journal'), findsOneWidget);
      expect(find.text('Yesterday Checklist'), findsOneWidget);
      expect(find.text('Archive Summary'), findsOneWidget);

      expect(find.text('Yesterday'), findsOneWidget);
      final archiveHeader =
          '${_monthName(now.subtract(const Duration(days: 60)).month)} '
          '${now.subtract(const Duration(days: 60)).year}';
      expect(find.text(archiveHeader), findsOneWidget);

      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      final composeButton = find.byIcon(Icons.edit_note_rounded);
      expect(composeButton, findsOneWidget);
    });

    testWidgets('filters notes with search query', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: NotesScreen()));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      await tester.enterText(searchField, 'Archive');
      await tester.pumpAndSettle();

      expect(find.text('Archive Summary'), findsOneWidget);
      expect(find.text('Today Journal'), findsNothing);
      expect(find.text('Yesterday Checklist'), findsNothing);
    });

    testWidgets('opens editor, saves edits, and search finds updated note', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: NotesScreen()));
      await tester.pumpAndSettle(const Duration(milliseconds: 250));

      await tester.tap(find.text('Today Journal'));
      await tester.pumpAndSettle();

      final bodyField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Start writing…',
      );
      expect(bodyField, findsOneWidget);

      await tester.enterText(bodyField, 'Study notes about missions');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new_rounded));
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'missions');
      await tester.pumpAndSettle();

      expect(find.text('Today Journal'), findsOneWidget);
      expect(find.text('Archive Summary'), findsNothing);
    });

    testWidgets('deleting note updates list immediately', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: NotesScreen()));
      await tester.pumpAndSettle(const Duration(milliseconds: 250));

      expect(find.text('3 Notes'), findsOneWidget);
      expect(find.text('Archive Summary'), findsOneWidget);

      await NotesService.instance.deleteNote('archive');
      await tester.pumpAndSettle();

      expect(find.text('Archive Summary'), findsNothing);
      expect(find.text('2 Notes'), findsOneWidget);
    });

    testWidgets('swiping to toggle pin updates pinned section and count', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: NotesScreen()));
      await tester.pumpAndSettle(const Duration(milliseconds: 300));

      expect(find.text('Pinned'), findsOneWidget);
      expect(find.text('3 Notes'), findsOneWidget);

      final pinnedTile = find.byKey(const ValueKey('note-today'));
      await tester.fling(pinnedTile, const Offset(520, 0), 1000);
      await tester.pumpAndSettle();

      expect(find.text('Pinned'), findsNothing);
      expect(find.text('3 Notes'), findsOneWidget);

      await tester.fling(pinnedTile, const Offset(520, 0), 1000);
      await tester.pumpAndSettle();

      expect(find.text('Pinned'), findsOneWidget);
    });

    testWidgets('shows empty state when search yields no results', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: NotesScreen()));
      await tester.pumpAndSettle(const Duration(milliseconds: 250));

      final searchField = find.byType(TextField);
      await tester.enterText(searchField, 'no matches expected');
      await tester.pumpAndSettle();

      expect(find.text('No results'), findsOneWidget);
      expect(find.text('0 Notes'), findsOneWidget);
      expect(find.text('Today Journal'), findsNothing);
      expect(find.text('Yesterday Checklist'), findsNothing);
      expect(find.text('Archive Summary'), findsNothing);
    });
  });
}

String _monthName(int month) {
  const names = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return names[month - 1];
}
