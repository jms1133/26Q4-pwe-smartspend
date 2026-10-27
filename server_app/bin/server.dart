import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
import 'package:server_app/db/database.dart';
import 'package:server_app/handlers/expense_handlers.dart';

Middleware handleCors() {
  return (Handler handler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
          'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization',
        });
      }
      final response = await handler(request);
      return response.change(headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization',
      });
    };
  };
}

Router buildRouter(Database db) {
  return Router()
    ..get('/', _rootHandler)
    ..get('/echo/<message>', _echoHandler)
    ..post('/chat', _chatHandler)
    ..get('/expenses', (Request req) => listExpensesHandler(req, db))
    ..post('/expenses', (Request req) => createExpenseHandler(req, db))
    ..put('/expenses/<id>', (Request req, String id) => updateExpenseHandler(req, db, id))
    ..delete('/expenses/<id>', (Request req, String id) => deleteExpenseHandler(req, db, id));
}

Response _rootHandler(Request req) {
  return Response.ok('Hello, World!\n');
}

Response _echoHandler(Request request) {
  final message = request.params['message'];
  return Response.ok('$message\n');
}

Future<Response> _chatHandler(Request request) async {
  try {
    final payload = await request.readAsString();
    print('Received payload: $payload');
    
    final jsonPayload = jsonDecode(payload);
    final userText = jsonPayload['message'] ?? 'Hello'; 

    final apiKey = Platform.environment['OPENAI_API_KEY'];
    if (apiKey == null || apiKey.isEmpty) {
      return Response.internalServerError(body: 'Server configuration error.');
    }

    // 1. Create a direct HTTP request matching the professor's curl command
    final client = HttpClient();
    final openAiRequest = await client.postUrl(Uri.parse('https://api.openai.com/v1/responses'));
    
    // 2. Set the exact headers
    openAiRequest.headers.set('Content-Type', 'application/json');
    openAiRequest.headers.set('Authorization', 'Bearer $apiKey');
    
    // 3. Send the exact payload structure required for gpt-6-luna
    openAiRequest.write(jsonEncode({
      "model": "gpt-6-luna",
      "input": userText,
      "store": true
    }));

    // 4. Await the response
    final openAiResponse = await openAiRequest.close();
    final responseBody = await openAiResponse.transform(utf8.decoder).join();
    
    if (openAiResponse.statusCode != 200) {
      print('OpenAI Error: ${openAiResponse.statusCode} - $responseBody');
      return Response.internalServerError(body: 'AI returned an error.');
    }

    // 5. Parse the custom response
    final aiData = jsonDecode(responseBody);
    String aiMessage = 'No text found in response.';

    // KORREKTUR: Extract the array from the 'output' key
    final List items = aiData is List ? aiData : (aiData['output'] as List? ?? []);

    for (var item in items) {
      if (item['content'] is List) {
        for (var contentItem in item['content']) {
          if (contentItem['type'] == 'output_text' && contentItem['text'] != null) {
            aiMessage = contentItem['text'];
            break;
          }
        }
      }
    }

    print('Extracted Haiku: $aiMessage');

    // 6. Return strictly formatted OpenAPI response to Flutter
    final responseJson = jsonEncode({
      "message": aiMessage,
      "timestamp": DateTime.now().toUtc().toIso8601String(),
      "author": "ai"
    });

    return Response.ok(responseJson, headers: {'Content-Type': 'application/json'});
    
  } catch (e) {
    print('Error in _chatHandler: $e');
    return Response.internalServerError(body: 'Failed to process chat request.');
  }
}

void main(List<String> args) async {
  // Use any available host or container IP (usually `0.0.0.0`).
  final ip = InternetAddress.anyIPv4;

  // Open the SQLite file once at startup. The same Database instance is
  // reused across all requests — sqlite3 handles concurrent access safely
  // for a single-process server like this.
  final dbPath = Platform.environment['DB_PATH'] ?? 'smart_spend.db';
  final db = openExpenseDatabase(path: dbPath);
  final router = buildRouter(db);

  // Configure a pipeline that logs requests.
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(handleCors())
      .addHandler(router.call);

  // For running in containers, we respect the PORT environment variable.
  final port = int.parse(Platform.environment['PORT'] ?? '8082');
  
  // KORREKTUR: 'handler' statt 'pipeline' übergeben und 'ip' / 'port' nutzen
  final server = await shelf_io.serve(handler, ip, port);
  print('Server running on http://${server.address.host}:${server.port}');  
}
