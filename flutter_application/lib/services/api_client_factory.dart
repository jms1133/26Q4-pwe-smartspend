import 'package:openapi/api.dart';

/// Builds the one [ApiClient] the app shares. [token] is called on every
/// request, so the header always carries the current token without the
/// client being rebuilt after login or logout. An empty string makes the
/// generated [HttpBearerAuth] skip the `Authorization` header.
ApiClient createApiClient({
  required String basePath,
  required String? Function() token,
}) {
  final bearer = HttpBearerAuth()..accessToken = () => token() ?? '';
  return ApiClient(basePath: basePath, authentication: bearer);
}
