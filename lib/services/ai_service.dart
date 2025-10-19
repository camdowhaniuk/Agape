import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Very small AI service abstraction.
///
/// Replace the implementation in [reply] with your provider of choice
/// (OpenAI, Google, Anthropic, etc.) and pass along [systemPrompt]
/// plus the [history] to get grounded answers.
class AIService {
  AIService({
    required this.systemPrompt,
    http.Client? client,
    this.model = 'gpt-4o-mini',
    this.temperature = 0.7,
    this.maxHistoryEntries = 14,
    String? apiKey,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _apiKey = (apiKey ?? const String.fromEnvironment('OPENAI_API_KEY')).trim();

  final String systemPrompt;
  final String model;
  final double temperature;
  final int maxHistoryEntries;

  final http.Client _client;
  final bool _ownsClient;
  final String _apiKey;

  static final Uri _endpoint = Uri.parse('https://api.openai.com/v1/chat/completions');

  /// Returns a single assistant reply for the given [history].
  ///
  /// Throws [AIServiceAuthException] when the API key is missing and [AIServiceException]
  /// for network/response errors.
  Future<String> reply({required List<AIMessage> history, required String userMessage}) async {
    if (_apiKey.isEmpty) {
      throw const AIServiceAuthException(
        'Missing OpenAI API key. Pass --dart-define=OPENAI_API_KEY=your_key when launching the app.',
      );
    }

    final trimmedHistory = history.length > maxHistoryEntries
        ? history.sublist(history.length - maxHistoryEntries)
        : history;

    final messages = <Map<String, String>>[
      {'role': 'system', 'content': systemPrompt},
      for (final message in trimmedHistory)
        {
          'role': _mapRole(message.role),
          'content': message.content,
        },
    ];

    final bool lastMatchesUser = trimmedHistory.isNotEmpty &&
        trimmedHistory.last.role == AIRole.user &&
        trimmedHistory.last.content == userMessage;
    if (!lastMatchesUser) {
      messages.add({'role': 'user', 'content': userMessage});
    }

    final requestBody = json.encode({
      'model': model,
      'temperature': temperature,
      'messages': messages,
    });

    late http.Response response;
    try {
      response = await _client.post(
        _endpoint,
        headers: {
          HttpHeaders.authorizationHeader: 'Bearer $_apiKey',
          HttpHeaders.contentTypeHeader: 'application/json',
        },
        body: requestBody,
      );
    } on SocketException catch (error) {
      throw AIServiceException('Network error while contacting OpenAI: $error');
    }

    if (response.statusCode != 200) {
      final body = response.body;
      String message = 'OpenAI error (${response.statusCode})';
      try {
        final data = json.decode(body) as Map<String, dynamic>;
        final err = data['error'];
        if (err is Map<String, dynamic>) {
          final msg = err['message'] as String?;
          if (msg != null && msg.isNotEmpty) {
            message = msg;
          }
        }
      } catch (_) {
        // ignore parse failure
      }
      throw AIServiceException(message);
    }

    try {
      final data = json.decode(response.body) as Map<String, dynamic>;
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final choice = choices.first;
        final message = choice['message'] as Map?;
        final content = message?['content'] as String?;
        if (content != null && content.trim().isNotEmpty) {
          return content.trim();
        }
      }
      throw const AIServiceException('OpenAI returned an empty response.');
    } catch (error) {
      if (error is AIServiceException) rethrow;
      throw AIServiceException('Failed to parse OpenAI response: $error');
    }
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  String _mapRole(AIRole role) {
    switch (role) {
      case AIRole.user:
        return 'user';
      case AIRole.assistant:
        return 'assistant';
      case AIRole.system:
        return 'system';
    }
  }
}

class AIServiceException implements Exception {
  const AIServiceException(this.message);
  final String message;

  @override
  String toString() => 'AIServiceException: $message';
}

class AIServiceAuthException extends AIServiceException {
  const AIServiceAuthException(super.message);
}

class AIMessage {
  AIMessage({required this.role, required this.content, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();

  factory AIMessage.fromJson(Map<String, dynamic> json) {
    final roleName = json['role'] as String?;
    final role = AIRole.values.firstWhere(
      (r) => r.name == roleName,
      orElse: () => AIRole.assistant,
    );
    final ts = json['timestamp'] as String?;
    final parsedTimestamp = ts != null ? DateTime.tryParse(ts) : null;
    return AIMessage(
      role: role,
      content: (json['content'] as String?)?.trim() ?? '',
      timestamp: parsedTimestamp ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };

  final AIRole role;
  final String content;
  final DateTime timestamp;
}

enum AIRole { system, user, assistant }
