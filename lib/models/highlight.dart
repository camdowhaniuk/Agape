class HighlightPortion {
  const HighlightPortion({
    required this.verse,
    required this.start,
    required this.end,
  });

  final int verse;
  final int start;
  final int end;

  HighlightPortion copyWith({int? verse, int? start, int? end}) {
    return HighlightPortion(
      verse: verse ?? this.verse,
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }

  Map<String, dynamic> toJson() {
    return {'verse': verse, 'start': start, 'end': end};
  }

  factory HighlightPortion.fromJson(Map<String, dynamic> json) {
    return HighlightPortion(
      verse: (json['verse'] as num).toInt(),
      start: (json['start'] as num).toInt(),
      end: (json['end'] as num).toInt(),
    );
  }
}

class PassageHighlight {
  const PassageHighlight({
    required this.id,
    required this.colorId,
    required this.portions,
    this.colorValue,
    this.createdAt,
    this.excerpt,
  });

  final String id;
  final int colorId;
  final List<HighlightPortion> portions;
  final int? colorValue;
  final int? createdAt;
  final String? excerpt;

  PassageHighlight copyWith({
    String? id,
    int? colorId,
    List<HighlightPortion>? portions,
    int? colorValue,
    int? createdAt,
    String? excerpt,
  }) {
    return PassageHighlight(
      id: id ?? this.id,
      colorId: colorId ?? this.colorId,
      portions: portions ?? List<HighlightPortion>.from(this.portions),
      colorValue: colorValue ?? this.colorValue,
      createdAt: createdAt ?? this.createdAt,
      excerpt: excerpt ?? this.excerpt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'colorId': colorId,
      'portions': portions.map((portion) => portion.toJson()).toList(),
      if (colorValue != null) 'colorValue': colorValue,
      if (createdAt != null) 'createdAt': createdAt,
      if (excerpt != null && excerpt!.isNotEmpty) 'excerpt': excerpt,
    };
  }

  factory PassageHighlight.fromJson(Map<String, dynamic> json) {
    final portionsNode = json['portions'];
    final portions = <HighlightPortion>[];
    if (portionsNode is List) {
      for (final portion in portionsNode) {
        if (portion is Map<String, dynamic>) {
          portions.add(HighlightPortion.fromJson(portion));
        } else if (portion is Map) {
          portions.add(
            HighlightPortion.fromJson(portion.cast<String, dynamic>()),
          );
        }
      }
    }
    return PassageHighlight(
      id: json['id'] as String,
      colorId: (json['colorId'] as num).toInt(),
      colorValue: (json['colorValue'] as num?)?.toInt(),
      createdAt: (json['createdAt'] as num?)?.toInt(),
      excerpt: json['excerpt'] as String?,
      portions: portions,
    );
  }
}

class VerseHighlight {
  const VerseHighlight({
    required this.spanId,
    required this.colorId,
    required this.start,
    required this.end,
    this.createdAt,
    this.colorValue,
  });

  final String spanId;
  final int colorId;
  final int start;
  final int end;
  final int? createdAt;
  final int? colorValue;

  VerseHighlight copyWith({
    String? spanId,
    int? colorId,
    int? start,
    int? end,
    int? createdAt,
    int? colorValue,
  }) {
    return VerseHighlight(
      spanId: spanId ?? this.spanId,
      colorId: colorId ?? this.colorId,
      start: start ?? this.start,
      end: end ?? this.end,
      createdAt: createdAt ?? this.createdAt,
      colorValue: colorValue ?? this.colorValue,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'spanId': spanId,
      'colorId': colorId,
      'start': start,
      'end': end,
      if (createdAt != null) 'createdAt': createdAt,
      if (colorValue != null) 'colorValue': colorValue,
    };
  }

  factory VerseHighlight.fromJson(Map<String, dynamic> json) {
    final String? spanId = json['spanId'] as String?;
    return VerseHighlight(
      spanId:
          spanId ??
          'legacy_${(json['start'] as num).toInt()}_${(json['end'] as num).toInt()}_${(json['createdAt'] as num?)?.toInt() ?? 0}',
      colorId: (json['colorId'] as num).toInt(),
      start: (json['start'] as num).toInt(),
      end: (json['end'] as num).toInt(),
      createdAt: (json['createdAt'] as num?)?.toInt(),
      colorValue: (json['colorValue'] as num?)?.toInt(),
    );
  }
}
