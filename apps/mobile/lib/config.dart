import 'package:flutter/foundation.dart';

/// Adresse de l'API. À fixer au build : `--dart-define=API_URL=https://api.exemple.cd`.
/// Par défaut : la machine de développement, vue depuis l'émulateur Android (10.0.2.2)
/// ou depuis Chrome (localhost).
const _apiUrlOverride = String.fromEnvironment('API_URL');

String get apiBaseUrl {
  if (_apiUrlOverride.isNotEmpty) return _apiUrlOverride;
  return kIsWeb ? 'http://localhost:3000' : 'http://10.0.2.2:3000';
}
