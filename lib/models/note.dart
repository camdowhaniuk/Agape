import 'package:flutter/foundation.dart';

@immutable
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.preview,
    required this.createdAt,
    this.updatedAt,
    this.folder,
    this.tags = const <String>[],
    this.pinned = false,
  });

  final String id;
  final String title;
  final String preview;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final String? folder;
  final List<String> tags;
  final bool pinned;

  DateTime get sortDate => updatedAt ?? createdAt;

  Note copyWith({
    String? id,
    String? title,
    String? preview,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? folder,
    List<String>? tags,
    bool? pinned,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      preview: preview ?? this.preview,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      folder: folder ?? this.folder,
      tags: tags ?? List<String>.from(this.tags),
      pinned: pinned ?? this.pinned,
    );
  }

  /// Convert Note to JSON for Firestore storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'preview': preview,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'folder': folder,
      'tags': tags,
      'pinned': pinned,
    };
  }

  /// Create Note from JSON retrieved from Firestore
  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      preview: json['preview'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      folder: json['folder'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? const <String>[],
      pinned: json['pinned'] as bool? ?? false,
    );
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    preview,
    createdAt,
    updatedAt,
    folder,
    Object.hashAll(tags),
    pinned,
  );

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Note &&
        other.id == id &&
        other.title == title &&
        other.preview == preview &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.folder == folder &&
        listEquals(other.tags, tags) &&
        other.pinned == pinned;
  }
}
