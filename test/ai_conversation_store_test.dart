import 'dart:convert';

import 'package:agape/services/ai_conversation_store.dart';
import 'package:agape/services/ai_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('migrates legacy history into conversations list', () async {
    final legacyMessages = [
      {
        'role': 'user',
        'content': 'Hello there',
        'timestamp': DateTime(2023, 1, 1, 12).toIso8601String(),
      },
      {
        'role': 'assistant',
        'content': 'Grace and peace to you!',
        'timestamp': DateTime(2023, 1, 1, 12, 5).toIso8601String(),
      },
    ];

    SharedPreferences.setMockInitialValues({
      'emmaus_conversation_history': json.encode(legacyMessages),
    });

    final store = AIConversationStore();
    final conversations = await store.loadAll();

    expect(conversations.length, 1);
    final conversation = conversations.first;
    expect(conversation.messages.length, 2);
    expect(conversation.messages.first.content, 'Hello there');
    expect(conversation.messages.last.content, 'Grace and peace to you!');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('emmaus_conversation_history'), isNull);
    expect(prefs.getString('agape_conversations_v1'), isNotNull);
  });

  test('save trims history to 48 messages', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AIConversationStore();
    final base = DateTime(2024, 1, 1, 8);
    final messages = List<AIMessage>.generate(
      60,
      (i) => AIMessage(
        role: i.isEven ? AIRole.user : AIRole.assistant,
        content: 'Message #$i',
        timestamp: base.add(Duration(minutes: i)),
      ),
    );

    await store.save(messages);
    final conversations = await store.loadAll();
    expect(conversations, isNotEmpty);
    expect(conversations.first.messages.length, 48);
    expect(conversations.first.messages.first.content, 'Message #12');
    expect(conversations.first.messages.last.content, 'Message #59');
  });
}
