import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/note.dart';

/// Repository for managing notes in Cloud Firestore
class NotesFirestoreRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get the notes collection for a specific user
  CollectionReference _userNotesCollection(String userId) {
    return _firestore.collection('users').doc(userId).collection('notes');
  }

  /// Load all notes for a user
  Future<List<Note>> loadNotes(String userId) async {
    try {
      final snapshot = await _userNotesCollection(userId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return Note.fromJson(data);
      }).toList();
    } catch (e) {
      // Log error and rethrow
      print('Error loading notes from Firestore: $e');
      rethrow;
    }
  }

  /// Save a note (create or update)
  Future<void> saveNote(String userId, Note note) async {
    try {
      await _userNotesCollection(userId).doc(note.id).set(
            note.toJson(),
            SetOptions(merge: true),
          );
    } catch (e) {
      print('Error saving note to Firestore: $e');
      rethrow;
    }
  }

  /// Delete a note
  Future<void> deleteNote(String userId, String noteId) async {
    try {
      await _userNotesCollection(userId).doc(noteId).delete();
    } catch (e) {
      print('Error deleting note from Firestore: $e');
      rethrow;
    }
  }

  /// Stream notes in real-time (optional - for future use)
  Stream<List<Note>> streamNotes(String userId) {
    return _userNotesCollection(userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return Note.fromJson(data);
      }).toList();
    });
  }

  /// Batch delete multiple notes (useful for cleanup)
  Future<void> deleteAllNotes(String userId) async {
    try {
      final snapshot = await _userNotesCollection(userId).get();
      final batch = _firestore.batch();

      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
    } catch (e) {
      print('Error deleting all notes from Firestore: $e');
      rethrow;
    }
  }
}
