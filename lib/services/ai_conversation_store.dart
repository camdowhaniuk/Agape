import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'ai_conversation.dart';
import 'ai_service.dart';

class AIConversationStore {
  static const String _storageKey = 'agape_conversations_v1';
  static const String _legacyStorageKey = 'emmaus_conversation_history';

  Future<List<AIConversation>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final conversations = await _readConversations(prefs);
    if (conversations != null) {
      return _sortByUpdated(conversations);
    }
    final migrated = await _migrateLegacy(prefs);
    return migrated != null ? _sortByUpdated(migrated) : const <AIConversation>[];
  }

  Future<AIConversation?> loadById(String id) async {
    final conversations = await loadAll();
    for (final conversation in conversations) {
      if (conversation.id == id) return conversation;
    }
    return null;
  }

  Future<AIConversation> upsert(AIConversation conversation) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await _readConversations(prefs) ?? const <AIConversation>[];
    final updated = List<AIConversation>.from(current);
    final index = updated.indexWhere((c) => c.id == conversation.id);
    final next = conversation.trimmed();
    if (index >= 0) {
      updated[index] = next;
    } else {
      updated.add(next);
    }
    await _writeConversations(prefs, _sortByUpdated(updated));
    return next;
  }

  Future<AIConversation> create({
    String? title,
    List<AIMessage>? messages,
  }) async {
    final conversation = AIConversation.create(
      id: _generateId(),
      title: title,
      messages: messages ?? const <AIMessage>[],
    ).trimmed();
    return upsert(conversation);
  }

  Future<void> delete(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await _readConversations(prefs);
    if (current == null || current.isEmpty) return;
    final next = current.where((c) => c.id != id).toList(growable: false);
    await _writeConversations(prefs, _sortByUpdated(next));
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
    await prefs.remove(_legacyStorageKey);
  }

  /// Legacy compatibility for the existing single-chat screen.
  Future<List<AIMessage>> load() async {
    final conversations = await loadAll();
    if (conversations.isEmpty) return const <AIMessage>[];
    return conversations.first.messages;
  }

  /// Legacy compatibility for the existing single-chat screen.
  Future<void> save(List<AIMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = _trimMessages(messages);
    final now = DateTime.now();
    final existing = await _readConversations(prefs);
    if (existing == null || existing.isEmpty) {
      final conversation = AIConversation.create(
        id: _generateId(),
        messages: trimmed,
      ).copyWith(
        createdAt: trimmed.isNotEmpty ? trimmed.first.timestamp : now,
        updatedAt: trimmed.isNotEmpty ? trimmed.last.timestamp : now,
        title: _deriveTitle(trimmed),
      );
      await _writeConversations(prefs, <AIConversation>[conversation.trimmed()]);
      return;
    }

    final sorted = _sortByUpdated(existing);
    final latest = sorted.first;
    final updatedConversation = latest.copyWith(
      messages: trimmed,
      updatedAt: trimmed.isNotEmpty ? trimmed.last.timestamp : now,
      createdAt: latest.createdAt,
      title: latest.title.isNotEmpty ? latest.title : _deriveTitle(trimmed),
    ).trimmed();

    final next = existing
        .map((c) => c.id == updatedConversation.id ? updatedConversation : c)
        .toList(growable: false);
    await _writeConversations(prefs, _sortByUpdated(next));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_legacyStorageKey);
    final current = await _readConversations(prefs);
    if (current == null || current.isEmpty) {
      await prefs.remove(_storageKey);
      return;
    }
    final sorted = _sortByUpdated(current);
    final latestId = sorted.first.id;
    final remaining = current.where((c) => c.id != latestId).toList(growable: false);
    await _writeConversations(prefs, _sortByUpdated(remaining));
  }

  Future<List<AIConversation>?> _readConversations(SharedPreferences prefs) async {
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final data = json.decode(raw);
      if (data is! List) return const <AIConversation>[];
      return data
          .whereType<Map<String, dynamic>>()
          .map(AIConversation.fromJson)
          .toList(growable: false);
    } catch (_) {
      return const <AIConversation>[];
    }
  }

  Future<List<AIConversation>?> _migrateLegacy(SharedPreferences prefs) async {
    final raw = prefs.getString(_legacyStorageKey);
    if (raw == null || raw.isEmpty) return null;
    List<AIMessage> legacyMessages;
    try {
      final List<dynamic> payload = json.decode(raw) as List<dynamic>;
      legacyMessages = payload
          .whereType<Map<String, dynamic>>()
          .map(AIMessage.fromJson)
          .toList();
    } catch (_) {
      legacyMessages = const <AIMessage>[];
    }
    await prefs.remove(_legacyStorageKey);
    if (legacyMessages.isEmpty) {
      return const <AIConversation>[];
    }
    final conversation = AIConversation.create(
      id: _generateId(),
      title: _deriveTitle(legacyMessages),
      messages: legacyMessages,
    ).trimmed();
    await _writeConversations(prefs, <AIConversation>[conversation]);
    return <AIConversation>[conversation];
  }

  Future<void> _writeConversations(
    SharedPreferences prefs,
    List<AIConversation> conversations,
  ) async {
    if (conversations.isEmpty) {
      await prefs.remove(_storageKey);
      return;
    }
    final payload = conversations
        .map((c) => c.toJson())
        .toList(growable: false);
    await prefs.setString(_storageKey, json.encode(payload));
  }

  List<AIConversation> _sortByUpdated(List<AIConversation> items) {
    final copy = List<AIConversation>.from(items);
    copy.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return copy;
  }

  List<AIMessage> _trimMessages(List<AIMessage> messages) {
    if (messages.length <= 48) return messages;
    return messages.sublist(messages.length - 48);
  }

  String _generateId() => DateTime.now().microsecondsSinceEpoch.toString();

  String _deriveTitle(List<AIMessage> messages) {
    if (messages.isEmpty) return AIConversation.defaultTitle;
    final userMessage = messages.firstWhere(
      (m) => m.role == AIRole.user && m.content.trim().isNotEmpty,
      orElse: () => messages.first,
    );
    final text = userMessage.content.trim();
    if (text.isEmpty) return AIConversation.defaultTitle;
    final singleLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return singleLine.length > 42 ? '${singleLine.substring(0, 42)}…' : singleLine;
  }
}
