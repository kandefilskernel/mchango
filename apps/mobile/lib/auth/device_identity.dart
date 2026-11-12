import 'dart:convert';

import 'package:cryptography/cryptography.dart';

/// Message signé pour ouvrir une session (spec/auth.md).
String challengeMessage(String deviceId, String nonce) => 'mchango-auth-v1\n$deviceId\n$nonce';

/// Clé Ed25519 de l'appareil. La graine privée reste dans le stockage sécurisé ;
/// seule la clé publique est envoyée au serveur.
class DeviceIdentity {
  DeviceIdentity._(this._keyPair, this.publicKeyBase64);

  static final _algorithm = Ed25519();

  final SimpleKeyPair _keyPair;

  /// 32 octets bruts, base64 standard : le format attendu par l'API.
  final String publicKeyBase64;

  static Future<DeviceIdentity> generate() async => _wrap(await _algorithm.newKeyPair());

  static Future<DeviceIdentity> fromSeed(List<int> seed) async => _wrap(await _algorithm.newKeyPairFromSeed(seed));

  static Future<DeviceIdentity> _wrap(SimpleKeyPair keyPair) async {
    final publicKey = await keyPair.extractPublicKey();
    return DeviceIdentity._(keyPair, base64.encode(publicKey.bytes));
  }

  Future<String> seedBase64() async => base64.encode(await _keyPair.extractPrivateKeyBytes());

  Future<String> sign(String message) async {
    final signature = await _algorithm.sign(utf8.encode(message), keyPair: _keyPair);
    return base64.encode(signature.bytes);
  }
}
