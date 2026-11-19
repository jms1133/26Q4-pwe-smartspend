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
    request.headers.set('Content-Type', 'application/json; charset=utf-8');
    request.headers.set('Authorization', 'Bearer ${credentials.apiKey}');
    final organizationId = credentials.organizationId;
    if (organizationId != null) {
      request.headers.set('OpenAI-Organization', organizationId);
    }
    final projectId = credentials.projectId;
    if (projectId != null) {
      request.headers.set('OpenAI-Project', projectId);
    }
    // Encode the body as UTF-8 bytes explicitly. HttpClientRequest.write
    // defaults to Latin-1, which corrupts non-Latin-1 characters (umlauts,
    // €, etc.) and makes the API reject the request with a 400.
    request.add(utf8.encode(jsonEncode({
      'model': 'gpt-6-luna',
      'input': input,
      'store': true,
    })));

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
  ///
  /// [knownCategories] is the current list of categories from the database.
  /// The prompt instructs the model to prefer one of these (so synonyms like
  /// "groceries" resolve to the existing "food") and only propose a new
  /// category when none is appropriate. This is the "A" half of the
  /// synonym-sprawl mitigation; the "C" half (confirm-on-save) lives in the
  /// client and the find-or-create step on expense creation.
  /// [onRaw] is an optional logging seam: when provided, it receives the raw
  /// model response before parsing. Used by the research classification log
  /// (documentation only — see docs/classification_log.jsonl). It never
  /// affects the return value or control flow.
  Future<ExpenseInput> classifyExpense(
    String text, {
    List<String> knownCategories = const [],
    void Function(String raw)? onRaw,
  }) async {
    final prompt = _buildClassifyPrompt(text, knownCategories);
    final raw = await callLuna(prompt);
    onRaw?.call(raw);
    return parseExpenseJson(raw);
  }

  String _buildClassifyPrompt(String text, List<String> knownCategories) {
    final categories = knownCategories.isEmpty
        ? '(no categories defined yet)'
        : knownCategories.join(', ');
    return '''
You are an expense parser. Extract a single expense from the user's text and
respond with ONLY a JSON object (no markdown, no prose) of the form:
{"title": string, "category": string, "amount": number}

Rules:
- Existing categories are: $categories
- PREFER an existing category. If the expense clearly fits one (including
  synonyms, e.g. "groceries" -> "food"), use that exact existing name.
- If none of the existing categories fits, INVENT a new short, specific,
  lowercase category that describes the expense (e.g. a loan -> "loan", a
  donation -> "donation", gambling -> "gambling"). Do not create
  near-duplicates of existing categories.
- NEVER use a generic catch-all category such as "other", "misc",
  "miscellaneous" or "sonstiges". Always choose a meaningful, specific name.
- "amount" is a positive number in euros (no currency symbol).
- "title" is a short human-readable label for the expense.

User text: "$text"
''';
  }

  /// Converts the model's JSON string into an [ExpenseInput]. Tolerates the
  /// model wrapping the JSON in prose or code fences by extracting the first
  /// `{...}` block. `category` is now free text (the server find-or-creates
  /// it). The prompt forbids generic catch-alls and tells the model to invent
  /// a specific category when nothing fits; `other` survives here only as a
  /// last-resort fallback for a genuinely empty/missing category, and is no
  /// longer seeded or offered to the model.
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

    final rawCategory = (map['category'] as String?)?.trim();
    // Last-resort fallback only: the prompt instructs the model to always
    // provide a specific category, so this should rarely trigger.
    final category =
        (rawCategory == null || rawCategory.isEmpty) ? 'other' : rawCategory;

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
