import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

/// Vérification par empreinte (ou visage) du téléphone. Remplaçable dans les tests.
abstract class BiometricGate {
  /// Le téléphone a un capteur et au moins une empreinte enregistrée.
  Future<bool> isAvailable();

  /// Affiche la fenêtre du système ; true si la personne est reconnue.
  Future<bool> authenticate(String reason);
}

/// Implémentation réelle (Android). Sur le web ou sans capteur : indisponible, le PIN suffit.
class DeviceBiometricGate implements BiometricGate {
  final _auth = LocalAuthentication();

  @override
  Future<bool> isAvailable() async {
    if (kIsWeb) return false;
    try {
      return await _auth.isDeviceSupported() && (await _auth.getAvailableBiometrics()).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String reason) async {
    try {
      // biometricOnly : pas de repli sur le code du téléphone, le repli c'est le PIN Mchango
      return await _auth.authenticate(localizedReason: reason, biometricOnly: true);
    } catch (_) {
      return false;
    }
  }
}
