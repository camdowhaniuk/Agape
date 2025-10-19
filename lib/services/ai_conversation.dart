import 'ai_service.dart';

/// Represents a single persisted chat session with Agape.
class AIConversation {
  AIConversation({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required List<AIMessage> messages,
  }) : messages = List<AIMessage>.unmodifiable(messages);

  factory AIConversation.create({
    required String id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<AIMessage>? messages,
  }) {
    final now = DateTime.now();
    final history = List<AIMessage>.from(messages ?? const <AIMessage>[]);
    final creationTime =
        createdAt ?? (history.isNotEmpty ? history.first.timestamp : now);
    final lastUpdated =
        updatedAt ?? (history.isNotEmpty ? history.last.timestamp : now);
    return AIConversation(
      id: id,
      title: _normalizeTitle(title),
      createdAt: creationTime,
      updatedAt: lastUpdated,
      messages: history,
    );
  }

  factory AIConversation.fromJson(Map<String, dynamic> json) {
    final String id = (json['id'] as String?)?.trim() ?? '';
    final String title = (json['title'] as String?)?.trim() ?? defaultTitle;
    final String? createdIso = json['createdAt'] as String?;
    final String? updatedIso = json['updatedAt'] as String?;
    final List<dynamic>? payload = json['messages'] as List<dynamic>?;

    final createdAt =
        createdIso != null ? DateTime.tryParse(createdIso) : null;
    final updatedAt =
        updatedIso != null ? DateTime.tryParse(updatedIso) : null;
    final history = payload == null
        ? const <AIMessage>[]
        : payload
            .whereType<Map<String, dynamic>>()
            .map(AIMessage.fromJson)
            .toList();

    if (id.isEmpty) {
      throw const FormatException('Missing conversation id');
    }

    return AIConversation.create(
      id: id,
      title: title,
      createdAt: createdAt,
      updatedAt: updatedAt,
      messages: history,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(growable: false),
      };

  AIConversation copyWith({
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<AIMessage>? messages,
  }) {
    return AIConversation(
      id: id,
      title: title == null ? this.title : _normalizeTitle(title),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      messages: messages ?? this.messages,
    );
  }

  AIConversation trimmed({int maxMessages = 48}) {
    if (messages.length <= maxMessages) return this;
    final history = messages.sublist(messages.length - maxMessages);
    return copyWith(
      createdAt: history.first.timestamp,
      updatedAt: history.last.timestamp,
      messages: history,
    );
  }

  static String _normalizeTitle(String? value) {
    final trimmed = value?.trim() ?? '';
    return trimmed.isEmpty ? defaultTitle : trimmed;
  }

  static const String defaultTitle = 'New chat';

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<AIMessage> messages;
}
