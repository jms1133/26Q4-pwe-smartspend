import 'dart:convert';
import 'dart:io';

import 'package:openapi/api.dart';

/// Thrown when the AI call or its response parsing fails in a way the
/// caller should surface to the client (bad config, unparseable output).
class AiServiceException implements Exception {
  AiServiceException(this.message);
  final String message;

  @override
  String toString() => 'AiServiceException: $message';
}

/// Centralized access to the custom `gpt-6-luna` model.
///
/// Key loading precedence (first match wins):
///   1. `secrets.json` next to the server (git-ignored local dev secret).
///   2. `OPENAI_API_KEY` environment variable (Docker/CI injection).
/// If neither is present, [apiKey] throws so the failure is explicit at
/// call time rather than silently sending an unauthenticated request.
class AiService {
  AiService({this.secretsPath = 'secrets.json', HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient();

  final String secretsPath;
  final HttpClient _httpClient;
  _AiCredentials? _cachedCredentials;

  _AiCredentials get _credentials {
    final cached = _cachedCredentials;
    if (cached != null) return cached;

    String? key;
    String? organizationId;
    String? projectId;

    final file = File(secretsPath);
    if (file.existsSync()) {
      try {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is Map) {
          key = _nonEmptyString(decoded['api_token']) ??
              _nonEmptyString(decoded['OPENAI_API_KEY']);
          organizationId = _nonEmptyString(decoded['organization_id']);
          projectId = _nonEmptyString(decoded['project_id']);
        }
      } catch (_) {
        // Fall through to env vars if secrets.json is malformed.
      }
    }

    key ??= Platform.environment['OPENAI_API_KEY'];
    organizationId ??= Platform.environment['OPENAI_ORG_ID'];
    projectId ??= Platform.environment['OPENAI_PROJECT_ID'];

    if (key == null || key.isEmpty) {
      throw AiServiceException(
        'No API key found. Add "api_token" to $secretsPath or set '
        'OPENAI_API_KEY in the environment.',
      );
    }

    final credentials = _AiCredentials(
      apiKey: key,
      organizationId: organizationId,
      projectId: projectId,
    );
    _cachedCredentials = credentials;
    return credentials;
  }

  String get apiKey => _credentials.apiKey;

  static String? _nonEmptyString(dynamic value) {
    if (value is String && value.isNotEmpty) return value;
    return null;
  }

  /// Sends [input] to the `gpt-6-luna` model via the `/v1/responses` endpoint
  /// and returns the extracted text output.
  Future<String> callLuna(String input) async {
    final credentials = _credentials;
    final request = await _httpClient
        .postUrl(Uri.parse('https://api.openai.com/v1/responses'));
    request.headers.set('Content-Type', 'application/json');
    request.headers.set('Authorization', 'Bearer ${credentials.apiKey}');
    final organizationId = credentials.organizationId;
    if (organizationId != null) {
      request.headers.set('OpenAI-Organization', organizationId);
    }
    final projectId = credentials.projectId;
    if (projectId != null) {
      request.headers.set('OpenAI-Project', projectId);
    }
    request.write(jsonEncode({
      'model': 'gpt-6-luna',
      'input': input,
      'store': true,
    }));

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode != 200) {
      throw AiServiceException('AI returned status ${response.statusCode}.');
    }

    final data = jsonDecode(body);
    final items = data is List ? data : (data['output'] as List? ?? []);
    for (final item in items) {
      if (item['content'] is List) {
        for (final contentItem in item['content']) {
          if (contentItem['type'] == 'output_text' &&
              contentItem['text'] != null) {
            return contentItem['text'] as String;
          }
        }
      }
    }
    throw AiServiceException('No text found in AI response.');
  }

  /// Parses raw expense [text] into a structured [ExpenseInput] by prompting
  /// the model for strict JSON and defensively validating the result.
  Future<ExpenseInput> classifyExpense(String text) async {
    final prompt = _buildClassifyPrompt(text);
    final raw = await callLuna(prompt);
    return parseExpenseJson(raw);
  }

  String _buildClassifyPrompt(String text) {
    final categories =
        ExpenseInputCategoryEnum.values.map((c) => c.value).join(', ');
    return '''
You are an expense parser. Extract a single expense from the user's text and
respond with ONLY a JSON object (no markdown, no prose) of the form:
{"title": string, "category": string, "amount": number}

Rules:
- "category" MUST be exactly one of: $categories
- "amount" is a positive number in euros (no currency symbol).
- "title" is a short human-readable label for the expense.
- If you cannot determine a field, use a sensible default ("other" for
  category).

User text: "$text"
''';
  }

  /// Converts the model's JSON string into an [ExpenseInput]. Tolerates the
  /// model wrapping the JSON in prose or code fences by extracting the first
  /// `{...}` block. Unknown categories fall back to `other`.
  static ExpenseInput parseExpenseJson(String raw) {
    final jsonSlice = _extractJsonObject(raw);
    if (jsonSlice == null) {
      throw AiServiceException('AI response was not valid JSON: $raw');
    }

    final Map<String, dynamic> map;
    try {
      final decoded = jsonDecode(jsonSlice);
      if (decoded is! Map) {
        throw AiServiceException('AI JSON was not an object: $raw');
      }
      map = decoded.cast<String, dynamic>();
    } catch (e) {
      throw AiServiceException('Failed to decode AI JSON: $raw');
    }

    final title = (map['title'] as String?)?.trim();
    if (title == null || title.isEmpty) {
      throw AiServiceException('AI JSON missing "title": $raw');
    }

    final amount = _parseAmount(map['amount']);
    if (amount == null || amount <= 0) {
      throw AiServiceException('AI JSON missing valid "amount": $raw');
    }

    final category = ExpenseInputCategoryEnum.fromJson(map['category']) ??
        ExpenseInputCategoryEnum.other;

    return ExpenseInput(
      title: title,
      category: category,
      amount: amount,
    );
  }

  static double? _parseAmount(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value.trim().replaceAll(',', '.'));
    }
    return null;
  }

  static String? _extractJsonObject(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start == -1 || end == -1 || end < start) return null;
    return raw.substring(start, end + 1);
  }
}

/// Resolved OpenAI credentials. [apiKey] is required; the organization and
/// project identifiers are optional and only sent as headers when present.
class _AiCredentials {
  _AiCredentials({
    required this.apiKey,
    this.organizationId,
    this.projectId,
  });

  final String apiKey;
  final String? organizationId;
  final String? projectId;
}
