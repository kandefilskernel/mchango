import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mchango/api/api_client.dart';
import 'package:mchango/services.dart';
import 'package:mchango/storage/key_value_store.dart';

typedef Handler = Object? Function(http.Request request, Map<String, dynamic> body);

/// API factice : chaque route renvoie une réponse préparée ; les requêtes sont gardées.
class FakeBackend {
  final Map<String, Handler> routes = {};
  final List<http.Request> requests = [];

  void on(String method, String path, Handler handler) => routes['$method $path'] = handler;

  List<Map<String, dynamic>> bodiesOf(String method, String path) => [
    for (final r in requests)
      if (r.method == method && r.url.path == path) jsonDecode(r.body) as Map<String, dynamic>,
  ];

  late final client = MockClient((request) async {
    requests.add(request);
    final handler = routes['${request.method} ${request.url.path}'];
    if (handler == null) return http.Response('{"message":"Route inconnue du test."}', 404);
    final body = request.body.isEmpty ? <String, dynamic>{} : jsonDecode(request.body) as Map<String, dynamic>;
    final result = handler(request, body);
    if (result is http.Response) return result;
    return http.Response.bytes(
      utf8.encode(jsonEncode(result)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });

  AppServices services([MemoryKeyValueStore? store]) => AppServices(
    client: ApiClient('http://api', client: client),
    store: store ?? MemoryKeyValueStore(),
  );
}

http.Response error(int status, String message) => http.Response.bytes(
  utf8.encode(jsonEncode({'message': message, 'statusCode': status})),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);
