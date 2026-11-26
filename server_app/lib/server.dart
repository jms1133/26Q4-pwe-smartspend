import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:server_app/auth/auth_handlers.dart';
import 'package:server_app/auth/auth_middleware.dart';
import 'package:server_app/auth/auth_services.dart';
import 'package:server_app/handlers/category_handlers.dart';
import 'package:server_app/handlers/expense_handlers.dart';
import 'package:server_app/services/ai_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

/// The complete request pipeline: request logging, CORS, authentication,
/// then the router.
///
/// The order matters. CORS wraps auth, so preflights are answered without a
/// token and 401 responses still get the CORS headers. Auth wraps the
/// router, so no protected handler runs without a verified user id.
///
/// Lives in `lib/` (not `bin/`) so tests can import it and serve it inside
/// the test process; only code that runs in the test VM shows up in coverage.
Handler buildHandler(Pool db, AiService aiService, AuthServices auth) {
  return const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(handleCors())
      .addMiddleware(authMiddleware(auth.tokens))
      .addHandler(buildRouter(db, aiService, auth).call);
}

Middleware handleCors() {
  return (Handler handler) {
    return (Request request) async {
      if (request.method == 'OPTIONS') {
        return Response.ok('', headers: _corsHeaders);
      }
      final response = await handler(request);
      return response.change(headers: _corsHeaders);
    };
  };
}

const _corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Origin, Content-Type, Authorization',
};

Router buildRouter(Pool db, AiService aiService, AuthServices auth) {
  return Router()
    ..get('/', _rootHandler)
    ..post('/auth/register', (Request req) => registerHandler(req, db, auth))
    ..post('/auth/login', (Request req) => loginHandler(req, db, auth))
    ..post('/chat', (Request req) => _chatHandler(req, aiService))
    ..post('/classify', (Request req) => classifyHandler(req, aiService, db))
    ..get('/expenses', (Request req) => listExpensesHandler(req, db))
    ..post('/expenses', (Request req) => createExpenseHandler(req, db))
    ..put(
      '/expenses/<id>',
      (Request req, String id) => updateExpenseHandler(req, db, id),
    )
    ..delete(
      '/expenses/<id>',
      (Request req, String id) => deleteExpenseHandler(req, db, id),
    )
    ..get('/categories', (Request req) => listCategoriesHandler(req, db))
    ..post('/categories', (Request req) => createCategoryHandler(req, db));
}

Response _rootHandler(Request req) {
  return Response.ok('Hello, World!\n');
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
      "author": "ai",
    });

    return Response.ok(
      responseJson,
      headers: {'Content-Type': 'application/json'},
    );
  } catch (e) {
    print('Error in _chatHandler: $e');
    return Response.internalServerError(
      body: 'Failed to process chat request.',
    );
  }
}
