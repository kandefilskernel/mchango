import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stockage des secrets de l'appareil (clé privée, empreinte du PIN, identifiants).
abstract class KeyValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Android : Keystore (chiffrement matériel quand le téléphone le permet).
class SecureKeyValueStore implements KeyValueStore {
  const SecureKeyValueStore();

  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Pour les tests.
class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);
}
