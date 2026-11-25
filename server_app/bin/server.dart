import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'dart:convert';
import 'package:postgres/postgres.dart';
import 'package:server_app/db/database.dart';
import 'package:server_app/db/db_config.dart';
import 'package:server_app/handlers/expense_handlers.dart';
import 'package:server_app/handlers/category_handlers.dart';
import 'package:server_app/services/ai_service.dart';

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

Router buildRouter(Session db, AiService aiService) {
  return Router()
    ..get('/', _rootHandler)
    ..get('/echo/<message>', _echoHandler)
    ..post('/chat', (Request req) => _chatHandler(req, aiService))
    ..post('/classify', (Request req) => classifyHandler(req, aiService, db))
    ..get('/expenses', (Request req) => listExpensesHandler(req, db))
    ..post('/expenses', (Request req) => createExpenseHandler(req, db))
    ..put('/expenses/<id>', (Request req, String id) => updateExpenseHandler(req, db, id))
    ..delete('/expenses/<id>', (Request req, String id) => deleteExpenseHandler(req, db, id))
    ..get('/categories', (Request req) => listCategoriesHandler(req, db))
    ..post('/categories', (Request req) => createCategoryHandler(req, db));
}

Response _rootHandler(Request req) {
  return Response.ok('Hello, World!\n');
}

Response _echoHandler(Request request) {
  final message = request.params['message'];
  return Response.ok('$message\n');
}

Future<Response> _chatHandler(Request request, AiService aiService) async {
  try {
    final payload = await request.readAsString();
    final jsonPayload = jsonDecode(payload);
    final userText = (jsonPayload['message'] as String?) ?? 'Hello';

    final aiMessage = await aiService.callLuna(userText);

    final responseJson = jsonEncode({
      "message": aiMessage,
      "timestamp": DateTime.now().toUtc().toIso8601String(),
      "author": "ai"
    });

    return Response.ok(responseJson, headers: {'Content-Type': 'application/json'});
  } on AiServiceException catch (e) {
    print('Error in _chatHandler: $e');
    return Response.internalServerError(body: 'Failed to process chat request.');
  } catch (e) {
    print('Error in _chatHandler: $e');
    return Response.internalServerError(body: 'Failed to process chat request.');
  }
}

void main(List<String> args) async {
  // Use any available host or container IP (usually `0.0.0.0`).
  final ip = InternetAddress.anyIPv4;

  // Open one connection pool at startup and share it across all requests.
  // Connection settings come from the env / repo-root .env (see DbConfig),
  // the same values Docker Compose uses for the `db` container.
  final db = await openExpenseDatabase(DbConfig.fromEnvironment());
  final aiService = AiService();
  final router = buildRouter(db, aiService);

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
