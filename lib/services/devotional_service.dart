import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/devotional.dart';

/// Service for generating and caching daily devotionals using Gemini API.
///
/// Devotionals are generated on-demand using Google Gemini (free tier) and cached
/// in SharedPreferences. This provides instant loading after first generation,
/// offline support for previously viewed devotionals, and zero ongoing API costs
/// within Gemini's free tier limits (1,000 requests/day).
class DevotionalService {
  DevotionalService._();

  static final DevotionalService instance = DevotionalService._();

  final http.Client _client = http.Client();
  final String _apiKey = const String.fromEnvironment('GEMINI_API_KEY').trim();

  // System prompt for devotional generation
  static const String _systemPrompt = '''You are a thoughtful Christian devotional writer. Generate theologically sound devotionals that:
- Ground reflection in Scripture and orthodox Christian theology
- Speak with warmth and pastoral care
- Provide practical application for daily living
- Include a meaningful prayer that connects to the verse and reflection

Format your response as JSON with these exact fields:
{
  "title": "A brief, compelling title (5-8 words)",
  "content": "Main devotional content (2-3 paragraphs exploring the verse's meaning and context)",
  "reflection": "Personal application questions or thoughts (1-2 paragraphs)",
  "prayer": "A prayer based on the verse and reflection (2-4 sentences)"
}

Keep the total length concise but meaningful - suitable for a 2-3 minute read.''';

  Uri get _endpoint => Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=$_apiKey');

  /// Initialize the service (no-op now, kept for compatibility).
  Future<void> initialize() async {
    // No longer need to load assets, but keeping method for API compatibility
    print('[Devotional] Service initialized - using Gemini API for on-demand generation');
  }

  /// Get or generate a devotional for the given verse.
  ///
  /// First checks SharedPreferences cache. If not found, generates using Gemini API
  /// and caches the result for future use.
  Future<Devotional?> getDevotionalForVerse({
    required String book,
    required int chapter,
    required int verse,
    required String verseText,
  }) async {
    final verseReference = '$book $chapter:$verse';

    // Try to get from cache first
    final cached = await _getCachedDevotional(verseReference);
    if (cached != null) {
      print('[Devotional] Loaded from cache: $verseReference');
      return cached;
    }

    // Generate new devotional with Gemini
    print('[Devotional] Generating devotional for: $verseReference');
    return await _generateDevotional(
      verseReference: verseReference,
      verseText: verseText,
    );
  }

  /// Get cached devotional from SharedPreferences.
  Future<Devotional?> _getCachedDevotional(String verseReference) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'devotional_$verseReference';
      final jsonString = prefs.getString(key);

      if (jsonString == null) {
        return null;
      }

      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return Devotional.fromJson(json);
    } catch (e) {
      print('[Devotional] Error loading cached devotional: $e');
      return null;
    }
  }

  /// Generate a devotional using Gemini API and cache it.
  Future<Devotional?> _generateDevotional({
    required String verseReference,
    required String verseText,
  }) async {
    if (_apiKey.isEmpty) {
      print('[Devotional] Missing Gemini API key');
      return null;
    }

    try {
      final userPrompt = '''Generate a devotional for this Bible verse:

Reference: $verseReference
Text: "$verseText"

Please provide your response as valid JSON following the format specified in the system instructions.''';

      final requestBody = json.encode({
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': userPrompt}
            ],
          }
        ],
        'systemInstruction': {
          'parts': [
            {'text': _systemPrompt}
          ],
        },
        'generationConfig': {
          'temperature': 0.7,
        },
      });

      final response = await _client.post(
        _endpoint,
        headers: {
          HttpHeaders.contentTypeHeader: 'application/json',
        },
        body: requestBody,
      );

      if (response.statusCode != 200) {
        print('[Devotional] Gemini API error (${response.statusCode}): ${response.body}');
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List?;
      if (candidates == null || candidates.isEmpty) {
        print('[Devotional] No candidates in Gemini response');
        return null;
      }

      final candidate = candidates.first;
      final content = candidate['content'] as Map?;
      final parts = content?['parts'] as List?;
      if (parts == null || parts.isEmpty) {
        print('[Devotional] No parts in Gemini response');
        return null;
      }

      final text = parts.first['text'] as String?;
      if (text == null || text.trim().isEmpty) {
        print('[Devotional] Empty text in Gemini response');
        return null;
      }

      // Remove markdown code fences if present (```json...```)
      var cleanedText = text.trim();
      if (cleanedText.startsWith('```')) {
        // Remove opening fence (```json or ```)
        cleanedText = cleanedText.replaceFirst(RegExp(r'^```(?:json)?\s*'), '');
        // Remove closing fence
        cleanedText = cleanedText.replaceFirst(RegExp(r'\s*```\s*$'), '');
        cleanedText = cleanedText.trim();
      }

      // Parse the JSON response from Gemini
      final devotionalJson = json.decode(cleanedText) as Map<String, dynamic>;

      final devotional = Devotional(
        verseReference: verseReference,
        title: devotionalJson['title'] as String,
        content: devotionalJson['content'] as String,
        reflection: devotionalJson['reflection'] as String,
        prayer: devotionalJson['prayer'] as String,
        generatedAt: DateTime.now(),
      );

      // Cache the devotional
      await _cacheDevotional(verseReference, devotional);

      print('[Devotional] Successfully generated and cached: $verseReference');
      return devotional;
    } catch (e, stackTrace) {
      print('[Devotional] Error generating devotional: $e');
      print('[Devotional] Stack trace: $stackTrace');
      return null;
    }
  }

  /// Cache a devotional to SharedPreferences.
  Future<void> _cacheDevotional(String verseReference, Devotional devotional) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'devotional_$verseReference';
      final jsonString = json.encode(devotional.toJson());
      await prefs.setString(key, jsonString);
    } catch (e) {
      print('[Devotional] Error caching devotional: $e');
    }
  }

  /// Check if the service has been initialized.
  bool get isInitialized => true; // Always ready with API-based approach

  void dispose() {
    _client.close();
  }
}
