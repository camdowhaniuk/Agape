class Devotional {
  final String verseReference;
  final String title;
  final String content;
  final String reflection;
  final String prayer;
  final DateTime generatedAt;

  Devotional({
    required this.verseReference,
    required this.title,
    required this.content,
    required this.reflection,
    required this.prayer,
    required this.generatedAt,
  });

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'verseReference': verseReference,
      'title': title,
      'content': content,
      'reflection': reflection,
      'prayer': prayer,
      'generatedAt': generatedAt.toIso8601String(),
    };
  }

  // Create from JSON
  factory Devotional.fromJson(Map<String, dynamic> json) {
    return Devotional(
      verseReference: json['verseReference'] as String? ?? '',
      title: json['title'] as String,
      content: json['content'] as String,
      reflection: json['reflection'] as String,
      prayer: json['prayer'] as String,
      generatedAt: json['generatedAt'] != null
          ? DateTime.parse(json['generatedAt'] as String)
          : DateTime.now(),
    );
  }

  // Create a copy with optional field updates
  Devotional copyWith({
    String? verseReference,
    String? title,
    String? content,
    String? reflection,
    String? prayer,
    DateTime? generatedAt,
  }) {
    return Devotional(
      verseReference: verseReference ?? this.verseReference,
      title: title ?? this.title,
      content: content ?? this.content,
      reflection: reflection ?? this.reflection,
      prayer: prayer ?? this.prayer,
      generatedAt: generatedAt ?? this.generatedAt,
    );
  }

  @override
  String toString() {
    return 'Devotional(verseReference: $verseReference, title: $title, generatedAt: $generatedAt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Devotional &&
        other.verseReference == verseReference &&
        other.title == title &&
        other.content == content &&
        other.reflection == reflection &&
        other.prayer == prayer &&
        other.generatedAt == generatedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      verseReference,
      title,
      content,
      reflection,
      prayer,
      generatedAt,
    );
  }
}
