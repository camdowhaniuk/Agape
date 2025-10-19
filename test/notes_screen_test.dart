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
      expect(find.text('Today Journal'), findsOneWidget);
      expect(find.text('Yesterday Checklist'), findsOneWidget);
      expect(find.text('Archive Summary'), findsOneWidget);

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      final archiveHeader = '${_monthName(now.subtract(const Duration(days: 60)).month)} '
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
