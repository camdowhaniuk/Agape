import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/note.dart';

class NotesService {
  NotesService._internal() {
    final now = DateTime.now();
    final today = now.subtract(
      Duration(
        hours: now.hour,
        minutes: now.minute,
        seconds: now.second,
        milliseconds: now.millisecond,
        microseconds: now.microsecond,
      ),
    );

    final seedNotes = <Note>[
      Note(
        id: _nextId(),
        title: 'Agape Bible Study App',
        preview: 'OpenAI Key',
        createdAt: today.add(const Duration(hours: 7, minutes: 58)),
        folder: 'Agape',
        tags: const ['dev', 'todo'],
        pinned: true,
      ),
      Note(
        id: _nextId(),
        title: 'Day 1: Upper (chest and back)',
        preview: 'Warm-up set + scripture meditation outline',
        createdAt: today.subtract(const Duration(days: 8, hours: -2)),
        updatedAt: today.subtract(const Duration(days: 8, hours: -1)),
        folder: 'Workout',
      ),
      Note(
        id: _nextId(),
        title: 'Flee from lust',
        preview: 'August 19 – Proverbs 7 journal and prayer points.',
        createdAt: today.subtract(const Duration(days: 13, hours: 12)),
        folder: 'Devotionals',
        tags: const ['proverbs', 'accountability'],
      ),
      Note(
        id: _nextId(),
        title: 'Leviticus Bible Study',
        preview: 'Chapter 1 – The Burnt Offering outline and insights.',
        createdAt: today.subtract(const Duration(days: 40)),
        folder: 'Old Testament',
      ),
      Note(
        id: _nextId(),
        title: 'End-times Study',
        preview: 'Old Testament prophecies cross-reference.',
        createdAt: today.subtract(const Duration(days: 60)),
        folder: 'Prophecy',
      ),
      Note(
        id: _nextId(),
        title: 'New Note',
        preview: 'No additional text',
        createdAt: today.subtract(const Duration(days: 45)),
      ),
    ];

    _notesNotifier.value = List<Note>.unmodifiable(seedNotes);
  }

  static final NotesService instance = NotesService._internal();

  final ValueNotifier<List<Note>> _notesNotifier = ValueNotifier<List<Note>>(
    const <Note>[],
  );

  ValueListenable<List<Note>> get notesListenable => _notesNotifier;

  List<Note> get notes => List<Note>.unmodifiable(_notesNotifier.value);

  Future<List<Note>> loadNotes() async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    return notes;
  }

  Future<Note> createEmptyNote() async {
    final note = Note(
      id: _nextId(),
      title: '',
      preview: '',
      createdAt: DateTime.now(),
    );
    await addNote(note);
    return note;
  }

  Future<void> addNote(Note note) async {
    final updated = [..._notesNotifier.value, note];
    _notesNotifier.value = List<Note>.unmodifiable(updated);
  }

  Future<void> updateNote(
    String id, {
    required Note Function(Note) transform,
  }) async {
    final current = _notesNotifier.value;
    final index = current.indexWhere((note) => note.id == id);
    if (index == -1) return;
    final mutable = List<Note>.from(current);
    mutable[index] = transform(mutable[index]);
    _notesNotifier.value = List<Note>.unmodifiable(mutable);
  }

  Future<void> deleteNote(String id) async {
    _notesNotifier.value = List<Note>.unmodifiable(
      _notesNotifier.value.where((note) => note.id != id),
    );
  }

  @visibleForTesting
  void replaceAllNotes(List<Note> notes) {
    _notesNotifier.value = List<Note>.unmodifiable(notes);
  }

  Map<String, List<Note>> groupNotesByDisplayDate(Iterable<Note> source) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final startOfWeek = todayStart.subtract(Duration(days: now.weekday % 7));

    String labelFor(DateTime date) {
      final dayStart = DateTime(date.year, date.month, date.day);
      if (dayStart.isAfter(todayStart) ||
          dayStart.isAtSameMomentAs(todayStart)) {
        return 'Today';
      }
      if (dayStart.isAfter(yesterdayStart) ||
          dayStart.isAtSameMomentAs(yesterdayStart)) {
        return 'Yesterday';
      }
      if (dayStart.isAfter(startOfWeek)) {
        return 'This Week';
      }
      return '${_monthNames[date.month - 1]} ${date.year}';
    }

    final Map<String, List<Note>> grouped = <String, List<Note>>{};
    for (final note
        in source.toList()..sort((a, b) => b.sortDate.compareTo(a.sortDate))) {
      final label = labelFor(note.sortDate);
      grouped.putIfAbsent(label, () => <Note>[]).add(note);
    }
    return grouped;
  }

  static final List<String> _monthNames = <String>[
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

  static String _nextId() {
    final random = Random.secure();
    final bytes = List<int>.generate(12, (_) => random.nextInt(255));
    return base64UrlEncode(bytes);
  }
}
