import 'package:openapi/api.dart';

const serverNotReachableMessage = 'Server not reachable.';

/// The generated client wraps socket, TLS and HTTP-client failures (no
/// response at all) in `ApiException(400)` with an [ApiException.innerException].
/// A real 400 from the server has no inner exception.
bool isNetworkError(Object error) =>
    error is ApiException && error.code == 400 && error.innerException != null;

/// A 401 the server actually sent (missing, invalid or expired token).
bool isUnauthorized(Object error) =>
    error is ApiException && error.code == 401 && error.innerException == null;

/// User-facing text for a failed request. Network errors never show the raw
/// exception text (it contains the URL and a stack trace).
String describeApiError(Object error, String action) {
  if (isNetworkError(error)) return serverNotReachableMessage;
  if (error is ApiException) {
    final message = error.message;
    return (message == null || message.isEmpty)
        ? '$action (HTTP ${error.code}).'
        : '$action: $message';
  }
  return '$action: $error';
}
