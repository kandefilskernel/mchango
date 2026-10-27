import 'package:flutter/foundation.dart';

import 'storage/key_value_store.dart';

/// Adresse de l'API. À fixer au build : `--dart-define=API_URL=https://api.exemple.cd`.
/// Par défaut : la machine de développement, vue depuis l'émulateur Android (10.0.2.2)
/// ou depuis Chrome (localhost).
const _apiUrlOverride = String.fromEnvironment('API_URL');

String get defaultApiUrl {
  if (_apiUrlOverride.isNotEmpty) return _apiUrlOverride;
  return kIsWeb ? 'http://localhost:3000' : 'http://10.0.2.2:3000';
}

/// Serveur de test choisi dans l'app (APK de test seulement, jamais en version finale) :
/// permet de viser le PC de développement sur le Wi-Fi sans recompiler quand son adresse change.
const testServerKey = 'test_server_url';

/// Le réglage « Serveur de test » n'existe que dans les versions de test.
const testServerSettingEnabled = kDebugMode;

Future<String> resolveApiUrl(KeyValueStore store) async {
  if (!testServerSettingEnabled) return defaultApiUrl;
  return await store.read(testServerKey) ?? defaultApiUrl;
}

/// « 10.163.102.131:3000 » ou « http://10.163.102.131:3000/ » → « http://10.163.102.131:3000 ».
/// Renvoie null si ce n'est pas une adresse de serveur plausible.
String? normalizeServerUrl(String input) {
  var s = input.trim();
  if (s.isEmpty) return null;
  if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'http://$s';
  final uri = Uri.tryParse(s);
  if (uri == null || uri.host.isEmpty || (uri.path.isNotEmpty && uri.path != '/') || uri.hasQuery) return null;
  return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
}
