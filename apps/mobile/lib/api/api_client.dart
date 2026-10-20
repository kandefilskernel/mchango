import 'dart:convert';

import 'package:http/http.dart' as http;

/// Erreur renvoyée par l'API ; [message] est en français et s'affiche tel quel.
class ApiException implements Exception {
  ApiException(this.status, this.message, {this.body});

  /// 0 : pas de réseau.
  final int status;
  final String message;
  final Map<String, dynamic>? body;

  @override
  String toString() => 'ApiException($status, $message)';
}

/// Client HTTP JSON. Sur 401, tente une fois de rouvrir la session (nouveau défi signé).
class ApiClient {
  ApiClient(this.baseUrl, {http.Client? client}) : _http = client ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  String? accessToken;

  /// Rouvre la session ; renvoie false si impossible (l'utilisateur doit se reconnecter).
  Future<bool> Function()? onUnauthorized;

  Future<dynamic> get(String path, {Map<String, String>? query}) => _send('GET', path, query: query);

  Future<dynamic> post(String path, [Object? body]) => _send('POST', path, body: body ?? {});

  Future<dynamic> put(String path, Object body) => _send('PUT', path, body: body);

  Future<dynamic> patch(String path, Object body) => _send('PATCH', path, body: body);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    bool retried = false,
  }) async {
    final uri = Uri.parse('$baseUrl$path').replace(queryParameters: query);
    final request = http.Request(method, uri)..headers['Accept'] = 'application/json';
    if (accessToken != null) request.headers['Authorization'] = 'Bearer $accessToken';
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request).timeout(const Duration(seconds: 20)));
    } catch (_) {
      throw ApiException(0, 'Pas de connexion. Vérifiez le réseau et réessayez.');
    }

    if (response.statusCode == 401 && accessToken != null && !retried && onUnauthorized != null) {
      if (await onUnauthorized!()) {
        return _send(method, path, body: body, query: query, retried: true);
      }
    }

    final text = utf8.decode(response.bodyBytes);
    final decoded = text.isEmpty ? null : jsonDecode(text);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _messageOf(decoded),
        body: decoded is Map<String, dynamic> ? decoded : null,
      );
    }
    return decoded;
  }

  static String _messageOf(dynamic body) {
    if (body is Map<String, dynamic>) {
      // Erreur de validation : le premier champ fautif est le plus utile
      final errors = body['errors'];
      if (errors is List && errors.isNotEmpty && errors.first is Map) {
        return (errors.first as Map)['message']?.toString() ?? 'Requête invalide.';
      }
      final message = body['message'];
      if (message is String) return message;
      if (message is List && message.isNotEmpty) return message.first.toString();
    }
    return 'Une erreur est survenue. Réessayez.';
  }
}
