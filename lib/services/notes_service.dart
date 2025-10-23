import 'dart:convert';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/note.dart';
import 'notes_firestore_repository.dart';

class NotesService {
  NotesService._internal() {
    // Listen to auth state changes and reload notes accordingly
    _auth.authStateChanges().listen((user) {
      if (user == null) {
        // User logged out - clear notes
        _notesNotifier.value = const <Note>[];
      } else {
        // User logged in - load their notes
        loadNotes();
      }
    });
  }

  static final NotesService instance = NotesService._internal();

  final NotesFirestoreRepository _repository = NotesFirestoreRepository();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Get current user ID, or null if not logged in
  String? get _userId => _auth.currentUser?.uid;

  final ValueNotifier<List<Note>> _notesNotifier = ValueNotifier<List<Note>>(
    const <Note>[],
  );

  ValueListenable<List<Note>> get notesListenable => _notesNotifier;

  List<Note> get notes => List<Note>.unmodifiable(_notesNotifier.value);

  /// Load notes from Firestore for the current user
  Future<List<Note>> loadNotes() async {
    final userId = _userId;

    // If user is not logged in, return empty list
    if (userId == null) {
      _notesNotifier.value = const <Note>[];
      return const <Note>[];
    }

    try {
      // Fetch notes from Firestore
      final notes = await _repository.loadNotes(userId);

      // Update in-memory cache
      _notesNotifier.value = List<Note>.unmodifiable(notes);

      return notes;
    } catch (e) {
      // If error, return current cached notes
      print('Error loading notes: $e');
      return notes;
    }
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

  /// Add a new note and save to Firestore
  Future<void> addNote(Note note) async {
    // Update in-memory cache immediately (optimistic update)
    final updated = [..._notesNotifier.value, note];
    _notesNotifier.value = List<Note>.unmodifiable(updated);

    // Persist to Firestore
    final userId = _userId;
    if (userId != null) {
      try {
        await _repository.saveNote(userId, note);
      } catch (e) {
        print('Error adding note to Firestore: $e');
        // Note: We keep the optimistic update even if Firestore fails
        // The note will be saved when connectivity is restored (offline persistence)
      }
    }
  }

  /// Update an existing note and save to Firestore
  Future<void> updateNote(
    String id, {
    required Note Function(Note) transform,
  }) async {
    final current = _notesNotifier.value;
    final index = current.indexWhere((note) => note.id == id);
    if (index == -1) return;

    // Update in-memory cache immediately (optimistic update)
    final mutable = List<Note>.from(current);
    final updatedNote = transform(mutable[index]);
    mutable[index] = updatedNote;
    _notesNotifier.value = List<Note>.unmodifiable(mutable);

    // Persist to Firestore
    final userId = _userId;
    if (userId != null) {
      try {
        await _repository.saveNote(userId, updatedNote);
      } catch (e) {
        print('Error updating note in Firestore: $e');
        // Note: We keep the optimistic update even if Firestore fails
      }
    }
  }

  /// Delete a note and remove from Firestore
  Future<void> deleteNote(String id) async {
    // Update in-memory cache immediately (optimistic update)
    _notesNotifier.value = List<Note>.unmodifiable(
      _notesNotifier.value.where((note) => note.id != id),
    );

    // Remove from Firestore
    final userId = _userId;
    if (userId != null) {
      try {
        await _repository.deleteNote(userId, id);
      } catch (e) {
        print('Error deleting note from Firestore: $e');
        // Note: We keep the optimistic update even if Firestore fails
      }
    }
  }

  Future<void> togglePinned(String id) async {
    await updateNote(
      id,
      transform: (note) =>
          note.copyWith(pinned: !note.pinned, updatedAt: DateTime.now()),
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
