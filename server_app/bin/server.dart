import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'dart:convert';

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

// Configure routes.
final _router = Router()
  ..get('/', _rootHandler)
  ..get('/echo/<message>', _echoHandler)
  ..post('/chat', _chatHandler);

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

  // Configure a pipeline that logs requests.
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(handleCors())
      .addHandler(_router.call);

  // For running in containers, we respect the PORT environment variable.
  final port = int.parse(Platform.environment['PORT'] ?? '8081');
  
  // KORREKTUR: 'handler' statt 'pipeline' übergeben und 'ip' / 'port' nutzen
  final server = await shelf_io.serve(handler, ip, port);
  print('Server running on http://${server.address.host}:${server.port}');  
}
