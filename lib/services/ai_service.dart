import 'dart:async';
import 'dart:convert';
import 'dart:io';


import 'package:http/http.dart' as http;

/// Very small AI service abstraction.
///
/// Uses Google Gemini API (free forever) for AI-powered spiritual mentoring.
class AIService {
  AIService({
    required this.systemPrompt,
    http.Client? client,
    this.model = 'gemini-2.5-flash-lite',
    this.temperature = 0.7,
    this.maxHistoryEntries = 14,
    String? apiKey,
  })  : _client = client ?? http.Client(),
        _ownsClient = client == null,
        _apiKey = (apiKey ?? const String.fromEnvironment('GEMINI_API_KEY')).trim();

  final String systemPrompt;
  final String model;
  final double temperature;
  final int maxHistoryEntries;

  final http.Client _client;
  final bool _ownsClient;
  final String _apiKey;

  // Gemini API endpoint - model is specified in URL
  Uri get _endpoint => Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$_apiKey');
  Uri get _streamEndpoint => Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/$model:streamGenerateContent?key=$_apiKey');

  /// Returns a single assistant reply for the given [history].
  ///
  /// Throws [AIServiceAuthException] when the API key is missing and [AIServiceException]
  /// for network/response errors.
  Future<String> reply({required List<AIMessage> history, required String userMessage}) async {
    if (_apiKey.isEmpty) {
      throw const AIServiceAuthException(
        'Missing Gemini API key. Get your free key at https://aistudio.google.com/apikey '
        'and pass it via --dart-define=GEMINI_API_KEY=your_key when launching the app.',
      );
    }

    final trimmedHistory = history.length > maxHistoryEntries
        ? history.sublist(history.length - maxHistoryEntries)
        : history;

    // Build contents array for Gemini (alternating user/model messages)
    final contents = <Map<String, dynamic>>[];

    for (final message in trimmedHistory) {
      contents.add({
        'role': _mapRoleForGemini(message.role),
        'parts': [
          {'text': message.content}
        ],
      });
    }

    // Add current user message if not already in history
    final bool lastMatchesUser = trimmedHistory.isNotEmpty &&
        trimmedHistory.last.role == AIRole.user &&
        trimmedHistory.last.content == userMessage;
    if (!lastMatchesUser) {
      contents.add({
        'role': 'user',
        'parts': [
          {'text': userMessage}
        ],
      });
    }

    // Gemini API request format
    final requestBody = json.encode({
      'contents': contents,
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt}
        ],
      },
      'generationConfig': {
        'temperature': temperature,
      },
    });

    late http.Response response;
    try {
      response = await _client.post(
        _endpoint,
        headers: {
          HttpHeaders.contentTypeHeader: 'application/json',
        },
        body: requestBody,
      );
    } on SocketException catch (error) {
      throw AIServiceException('Network error while contacting Gemini API: $error');
    }

    if (response.statusCode != 200) {
      final body = response.body;
      String message = 'Gemini API error (${response.statusCode})';
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
      final candidates = data['candidates'];
      if (candidates is List && candidates.isNotEmpty) {
        final candidate = candidates.first;
        final content = candidate['content'] as Map?;
        final parts = content?['parts'] as List?;
        if (parts != null && parts.isNotEmpty) {
          final text = parts.first['text'] as String?;
          if (text != null && text.trim().isNotEmpty) {
            return text.trim();
          }
        }
      }
      throw const AIServiceException('Gemini API returned an empty response.');
    } catch (error) {
      if (error is AIServiceException) rethrow;
      throw AIServiceException('Failed to parse Gemini API response: $error');
    }
  }

  /// Streams an assistant reply as Gemini produces tokens.
  Stream<String> replyStream({
    required List<AIMessage> history,
    required String userMessage,
  }) async* {
    if (_apiKey.isEmpty) {
      throw const AIServiceAuthException(
        'Missing Gemini API key. Get your free key at https://aistudio.google.com/apikey '
        'and pass it via --dart-define=GEMINI_API_KEY=your_key when launching the app.',
      );
    }

    final trimmedHistory = history.length > maxHistoryEntries
        ? history.sublist(history.length - maxHistoryEntries)
        : history;

    final contents = <Map<String, dynamic>>[];

    for (final message in trimmedHistory) {
      contents.add({
        'role': _mapRoleForGemini(message.role),
        'parts': [
          {'text': message.content}
        ],
      });
    }

    final bool lastMatchesUser = trimmedHistory.isNotEmpty &&
        trimmedHistory.last.role == AIRole.user &&
        trimmedHistory.last.content == userMessage;
    if (!lastMatchesUser) {
      contents.add({
        'role': 'user',
        'parts': [
          {'text': userMessage}
        ],
      });
    }

    final requestBody = json.encode({
      'contents': contents,
      'systemInstruction': {
        'parts': [
          {'text': systemPrompt}
        ],
      },
      'generationConfig': {
        'temperature': temperature,
      },
    });

    final request = http.Request('POST', _streamEndpoint)
      ..headers[HttpHeaders.contentTypeHeader] = 'application/json'
      ..body = requestBody;

    http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } on SocketException catch (error) {
      throw AIServiceException('Network error while contacting Gemini API: $error');
    }

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      String message = 'Gemini API error (${response.statusCode})';
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

    final stream = response.stream.transform(utf8.decoder);
    var objectBuffer = StringBuffer();
    var capturingObject = false;
    var objectDepth = 0;
    var inString = false;
    var escapeNext = false;

    List<String> parsePayload(String payload) {
      final tokens = <String>[];
      final trimmed = payload.trim();
      if (trimmed.isEmpty) return tokens;
      if (trimmed == '[DONE]') return tokens;

      Map<String, dynamic> data;
      try {
        data = json.decode(trimmed) as Map<String, dynamic>;
      } catch (_) {
        return tokens;
      }

      final err = data['error'];
      if (err is Map<String, dynamic>) {
        final msg = err['message'] as String?;
        throw AIServiceException(
          msg != null && msg.isNotEmpty ? msg : 'Gemini API returned an error chunk.',
        );
      }

      final candidates = data['candidates'];
      if (candidates is! List || candidates.isEmpty) return tokens;
      for (final candidate in candidates) {
        if (candidate is! Map<String, dynamic>) continue;
        final content = candidate['content'];
        if (content is! Map<String, dynamic>) continue;
        final parts = content['parts'];
        if (parts is! List) continue;
        for (final part in parts) {
          if (part is! Map<String, dynamic>) continue;
          final text = part['text'];
          if (text is String && text.isNotEmpty) {
            tokens.add(text);
          }
        }
      }
      return tokens;
    }

    await for (final chunk in stream) {
      for (var i = 0; i < chunk.length; i++) {
        final char = chunk[i];
        if (!capturingObject) {
          if (char == '{') {
            capturingObject = true;
            objectDepth = 1;
            objectBuffer.write(char);
          }
          continue;
        }

        objectBuffer.write(char);

        if (inString) {
          if (escapeNext) {
            escapeNext = false;
            continue;
          }
          if (char == '\\') {
            escapeNext = true;
            continue;
          }
          if (char == '"') {
            inString = false;
          }
          continue;
        }

        if (char == '"') {
          inString = true;
          continue;
        }

        if (char == '{') {
          objectDepth++;
          continue;
        }

        if (char == '}') {
          objectDepth--;
          if (objectDepth == 0) {
            final payload = objectBuffer.toString();
            objectBuffer = StringBuffer();
            capturingObject = false;
            for (final token in parsePayload(payload)) {
              yield token;
            }
          }
        }
      }
    }

    // Flush any remaining buffered object (in case stream ended cleanly with depth 0)
    if (!capturingObject && objectBuffer.isNotEmpty) {
      final payload = objectBuffer.toString();
      if (payload.isNotEmpty) {
        for (final token in parsePayload(payload)) {
          yield token;
        }
      }
    }
  }

  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
  }

  String _mapRoleForGemini(AIRole role) {
    switch (role) {
      case AIRole.user:
        return 'user';
      case AIRole.assistant:
        return 'model'; // Gemini uses 'model' instead of 'assistant'
      case AIRole.system:
        return 'user'; // Gemini doesn't have system role in contents, handled separately
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

class _StreamCompleted implements Exception {
  const _StreamCompleted();
}
