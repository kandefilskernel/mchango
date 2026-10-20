import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Mêmes règles que le serveur (apps/api/src/auth/pin.ts) : refus immédiat, sans réseau.
String? pinWeakness(String pin) {
  if (!RegExp(r'^\d{6}$').hasMatch(pin)) return 'Le PIN doit contenir exactement 6 chiffres.';
  if (RegExp(r'^(\d)\1{5}$').hasMatch(pin)) return 'Le PIN ne doit pas répéter un seul chiffre.';
  final d = pin.split('').map(int.parse).toList();
  var ascending = true;
  var descending = true;
  for (var i = 1; i < d.length; i++) {
    ascending &= d[i] == (d[i - 1] + 1) % 10;
    descending &= d[i] == (d[i - 1] + 9) % 10;
  }
  if (ascending || descending) return 'Le PIN ne doit pas être une suite (123456, 987654…).';
  return null;
}

/// Empreinte du PIN gardée sur le téléphone, pour déverrouiller l'app sans réseau.
/// PBKDF2-HMAC-SHA256 avec sel aléatoire ; format : pbkdf2-sha256$itérations$sel$empreinte.
class LocalPin {
  LocalPin._();

  /// Compromis : assez lent pour freiner un essai de toutes les combinaisons, assez rapide
  /// pour un téléphone d'entrée de gamme (calcul en Dart pur).
  static const iterations = 60000;

  static Future<String> hash(String pin, {List<int>? salt}) async {
    final s = salt ?? List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final digest = await _derive(pin, s, iterations);
    return 'pbkdf2-sha256\$$iterations\$${base64.encode(s)}\$${base64.encode(digest)}';
  }

  static Future<bool> verify(String stored, String pin) async {
    final parts = stored.split(r'$');
    if (parts.length != 4 || parts[0] != 'pbkdf2-sha256') return false;
    final digest = await _derive(pin, base64.decode(parts[2]), int.parse(parts[1]));
    return _constantTimeEquals(digest, base64.decode(parts[3]));
  }

  static Future<List<int>> _derive(String pin, List<int> salt, int rounds) async {
    final key = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: rounds, bits: 256)
        .deriveKeyFromPassword(password: pin, nonce: salt);
    return key.extractBytes();
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }
}
