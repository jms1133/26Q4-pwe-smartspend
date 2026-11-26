import 'package:server_app/auth/token_service.dart';
import 'package:shelf/shelf.dart';

/// Key under which [authMiddleware] stores the authenticated user's id in
/// the request context.
const _userIdKey = 'userId';

/// The id of the user who sent [request]. Only valid behind
/// [authMiddleware]; handlers take the owner from here, never from the body
/// or the URL.
int userIdOf(Request request) => request.context[_userIdKey] as int;

/// Rejects every request without a valid `Authorization: Bearer <jwt>`
/// header with 401, except the public routes: `OPTIONS` preflights, `/` and
/// `/auth/*`.
///
/// It sits inside the CORS middleware, so preflights are answered before
/// they get here and 401 responses still carry the CORS headers; without
/// them the browser would hide the 401 from the Flutter app and report a
/// generic network error instead.
Middleware authMiddleware(TokenService tokens) {
  return (Handler inner) {
    return (Request request) {
      if (_isPublic(request)) return inner(request);

      final token = _bearerToken(request);
      final userId = token == null ? null : tokens.verify(token);
      if (userId == null) {
        return Response.unauthorized(
          'Missing or invalid token.',
          headers: {'WWW-Authenticate': 'Bearer'},
        );
      }
      // request.change returns a copy; the context map is how shelf passes
      // per-request values from middleware to handlers.
      return inner(request.change(context: {_userIdKey: userId}));
    };
  };
}

bool _isPublic(Request request) {
  // request.url is relative to the handler's mount point, without the
  // leading slash: GET / has the path ''.
  final path = request.url.path;
  return request.method == 'OPTIONS' ||
      path.isEmpty ||
      path == 'auth' ||
      path.startsWith('auth/');
}

String? _bearerToken(Request request) {
  final header = request.headers['authorization'];
  if (header == null) return null;
  const prefix = 'bearer ';
  if (!header.toLowerCase().startsWith(prefix)) return null;
  final token = header.substring(prefix.length).trim();
  return token.isEmpty ? null : token;
}
