class VerseHighlight {
  const VerseHighlight({
    required this.colorId,
    required this.start,
    required this.end,
    this.excerpt,
    this.createdAt,
  });

  final int colorId;
  final int start;
  final int end;
  final String? excerpt;
  final int? createdAt;

  VerseHighlight copyWith({
    int? colorId,
    int? start,
    int? end,
    String? excerpt,
    int? createdAt,
  }) {
    return VerseHighlight(
      colorId: colorId ?? this.colorId,
      start: start ?? this.start,
      end: end ?? this.end,
      excerpt: excerpt ?? this.excerpt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'colorId': colorId,
    'start': start,
    'end': end,
    if (excerpt != null) 'text': excerpt,
    if (createdAt != null) 'createdAt': createdAt,
  };

  factory VerseHighlight.fromJson(Map<String, dynamic> json) {
    final int colorId = (json['colorId'] as num).toInt();
    final int start = (json['start'] as num).toInt();
    final int end = (json['end'] as num).toInt();
    final String? excerpt = json['text'] as String?;
    final int? createdAt = (json['createdAt'] as num?)?.toInt();
    return VerseHighlight(
      colorId: colorId,
      start: start,
      end: end,
      excerpt: excerpt,
      createdAt: createdAt,
    );
  }
}
