import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/highlight.dart';

/// Repository for managing highlights in Cloud Firestore
class HighlightFirestoreRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get the highlights collection for a specific user
  CollectionReference _userHighlightsCollection(String userId) {
    return _firestore.collection('users').doc(userId).collection('highlights');
  }

  /// Load all highlights for a user
  /// Returns a map of chapter keys to lists of PassageHighlights
  Future<Map<String, List<PassageHighlight>>> loadHighlights(String userId) async {
    try {
      final snapshot = await _userHighlightsCollection(userId).get();

      final Map<String, List<PassageHighlight>> highlights = {};

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final chapterKey = doc.id; // Document ID is the chapter key (e.g., "John|3")
        final highlightsData = data['highlights'] as List<dynamic>?;

        if (highlightsData != null) {
          final spans = <PassageHighlight>[];
          for (final item in highlightsData) {
            if (item is Map<String, dynamic>) {
              try {
                spans.add(PassageHighlight.fromJson(item));
              } catch (_) {
                continue;
              }
            }
          }
          if (spans.isNotEmpty) {
            highlights[chapterKey] = spans;
          }
        }
      }

      return highlights;
    } catch (e) {
      print('Error loading highlights from Firestore: $e');
      rethrow;
    }
  }

  /// Save highlights for a specific chapter
  Future<void> saveChapterHighlights(
    String userId,
    String chapterKey,
    List<PassageHighlight> highlights,
  ) async {
    try {
      if (highlights.isEmpty) {
        // If no highlights, delete the document
        await _userHighlightsCollection(userId).doc(chapterKey).delete();
      } else {
        await _userHighlightsCollection(userId).doc(chapterKey).set({
          'highlights': highlights.map((h) => h.toJson()).toList(),
        });
      }
    } catch (e) {
      print('Error saving chapter highlights to Firestore: $e');
      rethrow;
    }
  }

  /// Delete all highlights for a chapter
  Future<void> deleteChapterHighlights(String userId, String chapterKey) async {
    try {
      await _userHighlightsCollection(userId).doc(chapterKey).delete();
    } catch (e) {
      print('Error deleting chapter highlights from Firestore: $e');
      rethrow;
    }
  }

  /// Save custom colors array
  Future<void> saveCustomColors(String userId, List<int> customColors) async {
    try {
      await _firestore.collection('users').doc(userId).set({
        'customColors': customColors,
      }, SetOptions(merge: true));
    } catch (e) {
      print('Error saving custom colors to Firestore: $e');
      rethrow;
    }
  }

  /// Load custom colors array
  Future<List<int>> loadCustomColors(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      final data = doc.data();
      if (data != null && data['customColors'] is List) {
        return (data['customColors'] as List)
            .whereType<num>()
            .map((value) => value.toInt())
            .where((value) => value > 0)
            .toList();
      }
      return [];
    } catch (e) {
      print('Error loading custom colors from Firestore: $e');
      return [];
    }
  }

  /// Delete all highlights for a user
  Future<void> deleteAllHighlights(String userId) async {
    try {
      final snapshot = await _userHighlightsCollection(userId).get();
      final batch = _firestore.batch();

      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();
    } catch (e) {
      print('Error deleting all highlights from Firestore: $e');
      rethrow;
    }
  }
}
