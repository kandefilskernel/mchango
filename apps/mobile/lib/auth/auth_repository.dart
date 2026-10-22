import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../storage/key_value_store.dart';
import 'biometric.dart';
import 'device_identity.dart';
import 'local_pin.dart';
import '../l10n/l10n.dart';

/// recoveryPending : « PIN oublié » demandé, en attente de la confirmation d'un garant.
enum AuthStatus { loading, signedOut, locked, signedIn, recoveryPending }

/// Garant qui doit confirmer une demande de nouveau PIN.
class Guarantor {
  Guarantor(this.fullName, this.groupName);
  final String fullName;
  final String groupName;
}

/// Où en est une demande de nouveau PIN.
class PinResetState {
  PinResetState(this.status, this.guarantors);

  /// pending, completed, rejected, cancelled, expired
  final String status;
  final List<Guarantor> guarantors;
}

/// Résultat de la vérification du code SMS.
class OtpVerification {
  OtpVerification(this.otpToken, this.accountExists);
  final String otpToken;
  final bool accountExists;
}

/// Inscription, liaison d'un nouveau téléphone, déverrouillage par PIN, session signée.
///
/// Ce qui reste sur le téléphone (stockage sécurisé) : identifiant de l'appareil, graine de
/// la clé privée, empreinte du PIN, nom. Le PIN lui-même n'est jamais stocké.
class AuthRepository extends ChangeNotifier {
  AuthRepository(this._api, this._store, this._biometric) {
    _api.onUnauthorized = _refreshSession;
  }

  final ApiClient _api;
  final KeyValueStore _store;
  final BiometricGate _biometric;

  static const _kDeviceId = 'device_id';
  static const _kSeed = 'device_seed';
  static const _kPinHash = 'pin_hash';
  static const _kUserId = 'user_id';
  static const _kFullName = 'full_name';
  static const _kPinFailures = 'pin_failures';
  static const _kLockedUntil = 'pin_locked_until';
  // Déverrouillage par empreinte, activé par la personne depuis l'app (le PIN reste valable)
  static const _kBiometric = 'biometric_unlock';
  // Demande « PIN oublié » en attente : identifiant, clé du téléphone, empreinte du nouveau PIN
  static const _kResetId = 'pin_reset_id';
  static const _kResetSeed = 'pin_reset_seed';
  static const _kResetPinHash = 'pin_reset_pin_hash';

  /// Échecs de PIN avant une pause forcée, et durée de la pause.
  static const maxPinFailures = 5;
  static const lockDuration = Duration(minutes: 5);

  AuthStatus status = AuthStatus.loading;
  String? userId;
  String? fullName;

  Future<void> load() async {
    final deviceId = await _store.read(_kDeviceId);
    userId = await _store.read(_kUserId);
    fullName = await _store.read(_kFullName);
    status = deviceId != null
        ? AuthStatus.locked
        : await _store.read(_kResetId) != null
        ? AuthStatus.recoveryPending
        : AuthStatus.signedOut;
    notifyListeners();
  }

  /// « PIN oublié » : code SMS vérifié + nouveau PIN. Sans tontine en cours, c'est immédiat ;
  /// sinon un garant doit confirmer (le code SMS seul ne suffit pas : vol de carte SIM).
  Future<PinResetState> requestPinReset({required String otpToken, required String newPin}) async {
    final identity = await DeviceIdentity.generate();
    final res = await _api.post('/auth/pin-reset', {
      'otpToken': otpToken,
      'newPin': newPin,
      'devicePublicKey': identity.publicKeyBase64,
    }) as Map;
    if (res['status'] == 'completed') {
      _api.accessToken = res['accessToken'] as String;
      final me = await _api.get('/me') as Map;
      await _saveDevice(res, identity, newPin, me['full_name'] as String);
      return PinResetState('completed', const []);
    }
    await _store.write(_kResetId, res['requestId'] as String);
    await _store.write(_kResetSeed, await identity.seedBase64());
    await _store.write(_kResetPinHash, await LocalPin.hash(newPin));
    status = AuthStatus.recoveryPending;
    notifyListeners();
    return PinResetState('pending', _guarantors(res));
  }

  /// Interroge le serveur. Si un garant a confirmé, ce téléphone est lié avec le nouveau PIN.
  Future<PinResetState> checkPinReset() async {
    final requestId = await _store.read(_kResetId);
    if (requestId == null) return PinResetState('cancelled', const []);
    final res = await _api.get('/auth/pin-reset/$requestId') as Map;
    final state = res['status'] as String;
    if (state == 'completed') {
      await _store.write(_kDeviceId, res['deviceId'] as String);
      await _store.write(_kSeed, (await _store.read(_kResetSeed))!);
      await _store.write(_kPinHash, (await _store.read(_kResetPinHash))!);
      await _clearReset();
      await _openSession();
      final me = await _api.get('/me') as Map;
      await _store.write(_kUserId, me['id'] as String);
      await _store.write(_kFullName, me['full_name'] as String);
      userId = me['id'] as String;
      fullName = me['full_name'] as String;
      status = AuthStatus.signedIn;
      notifyListeners();
    } else if (state != 'pending') {
      await cancelPinReset();
    }
    return PinResetState(state, _guarantors(res));
  }

  /// Abandonne la demande sur ce téléphone (elle expirera côté serveur).
  Future<void> cancelPinReset() async {
    await _clearReset();
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  Future<void> _clearReset() async {
    for (final k in [_kResetId, _kResetSeed, _kResetPinHash]) {
      await _store.delete(k);
    }
  }

  static List<Guarantor> _guarantors(Map res) => [
    for (final g in (res['guarantors'] as List? ?? const []))
      Guarantor((g as Map)['fullName'] as String, g['groupName'] as String),
  ];

  Future<void> requestOtp(String phone) => _api.post('/auth/otp/request', {'phone': phone});

  Future<OtpVerification> verifyOtp(String phone, String code) async {
    final res = await _api.post('/auth/otp/verify', {'phone': phone, 'code': code}) as Map;
    return OtpVerification(res['otpToken'] as String, res['accountExists'] as bool);
  }

  Future<void> register({required String otpToken, required String fullName, required String pin}) async {
    final identity = await DeviceIdentity.generate();
    final session = await _api.post('/auth/register', {
      'otpToken': otpToken,
      'fullName': fullName,
      'pin': pin,
      'devicePublicKey': identity.publicKeyBase64,
      'language': Lang.instance.current.code,
    }) as Map;
    await _saveDevice(session, identity, pin, fullName);
  }

  /// Compte existant sur ce téléphone : code SMS + PIN. L'ancien téléphone est révoqué.
  Future<void> linkDevice({required String otpToken, required String pin}) async {
    final identity = await DeviceIdentity.generate();
    final session = await _api.post('/auth/devices', {
      'otpToken': otpToken,
      'pin': pin,
      'devicePublicKey': identity.publicKeyBase64,
    }) as Map;
    _api.accessToken = session['accessToken'] as String;
    final me = await _api.get('/me') as Map;
    // La langue choisie sur l'écran d'accueil vaut aussi pour les SMS de ce compte
    if (me['language'] != Lang.instance.current.code) {
      await _api.put('/me/language', {'language': Lang.instance.current.code}).catchError((_) => null);
    }
    await _saveDevice(session, identity, pin, me['full_name'] as String);
  }

  /// Temps restant avant de pouvoir réessayer le PIN, ou null.
  Future<Duration?> lockRemaining() async {
    final until = int.tryParse(await _store.read(_kLockedUntil) ?? '');
    if (until == null) return null;
    final left = DateTime.fromMillisecondsSinceEpoch(until).difference(DateTime.now());
    return left.isNegative ? null : left;
  }

  /// Vérifie le PIN sur le téléphone puis ouvre une session. Renvoie false si le PIN est faux.
  Future<bool> unlock(String pin) async {
    if (await lockRemaining() != null) return false;
    final stored = await _store.read(_kPinHash);
    if (stored == null || !await LocalPin.verify(stored, pin)) {
      final failures = int.parse(await _store.read(_kPinFailures) ?? '0') + 1;
      if (failures >= maxPinFailures) {
        await _store.write(_kPinFailures, '0');
        await _store.write(_kLockedUntil, '${DateTime.now().add(lockDuration).millisecondsSinceEpoch}');
      } else {
        await _store.write(_kPinFailures, '$failures');
      }
      return false;
    }
    await _store.write(_kPinFailures, '0');
    await _store.delete(_kLockedUntil);
    await _openSession();
    status = AuthStatus.signedIn;
    notifyListeners();
    return true;
  }

  /// Empreinte possible sur ce téléphone (capteur présent, empreinte enregistrée).
  Future<bool> biometricAvailable() => _biometric.isAvailable();

  Future<bool> biometricEnabled() async => await _store.read(_kBiometric) == '1';

  /// Active l'empreinte après une reconnaissance réussie (la personne prouve que c'est bien la sienne).
  /// Renvoie false si l'empreinte n'a pas été reconnue.
  Future<bool> enableBiometric() async {
    if (!await _biometric.authenticate('Activer l\'ouverture de Mchango par empreinte')) return false;
    await _store.write(_kBiometric, '1');
    return true;
  }

  Future<void> disableBiometric() => _store.delete(_kBiometric);

  /// Ouverture par empreinte, à la place du PIN. Même pause que le PIN après trop d'essais ratés.
  Future<bool> unlockWithBiometric() async {
    if (!await biometricEnabled() || await lockRemaining() != null) return false;
    if (!await _biometric.authenticate('Ouvrir Mchango')) return false;
    await _store.write(_kPinFailures, '0');
    await _openSession();
    status = AuthStatus.signedIn;
    notifyListeners();
    return true;
  }

  void lock() {
    _api.accessToken = null;
    status = AuthStatus.locked;
    notifyListeners();
  }

  /// Oublie ce téléphone (il faudra le code SMS et le PIN pour revenir).
  Future<void> forgetDevice() async {
    for (final k in [_kDeviceId, _kSeed, _kPinHash, _kUserId, _kFullName, _kPinFailures, _kLockedUntil, _kBiometric]) {
      await _store.delete(k);
    }
    _api.accessToken = null;
    userId = null;
    fullName = null;
    status = AuthStatus.signedOut;
    notifyListeners();
  }

  Future<void> _saveDevice(Map session, DeviceIdentity identity, String pin, String name) async {
    await _store.write(_kDeviceId, session['deviceId'] as String);
    await _store.write(_kSeed, await identity.seedBase64());
    await _store.write(_kPinHash, await LocalPin.hash(pin));
    await _store.write(_kUserId, session['userId'] as String);
    await _store.write(_kFullName, name);
    userId = session['userId'] as String;
    fullName = name;
    _api.accessToken = session['accessToken'] as String;
    status = AuthStatus.signedIn;
    notifyListeners();
  }

  Future<void> _openSession() async {
    final deviceId = await _store.read(_kDeviceId);
    final seed = await _store.read(_kSeed);
    if (deviceId == null || seed == null) throw ApiException(401, 'Appareil non enregistré.');
    final identity = await DeviceIdentity.fromSeed(base64.decode(seed));
    _api.accessToken = null;
    final challenge = await _api.post('/auth/challenge', {'deviceId': deviceId}) as Map;
    final nonce = challenge['nonce'] as String;
    final session = await _api.post('/auth/session', {
      'deviceId': deviceId,
      'nonce': nonce,
      'signature': await identity.sign(challengeMessage(deviceId, nonce)),
    }) as Map;
    _api.accessToken = session['accessToken'] as String;
  }

  /// Jeton expiré : on re-signe un défi. Si l'appareil a été révoqué (connexion sur un autre
  /// téléphone), on l'oublie et l'utilisateur doit se reconnecter.
  Future<bool> _refreshSession() async {
    try {
      await _openSession();
      return true;
    } on ApiException catch (e) {
      if (e.status == 401) await forgetDevice();
      return false;
    }
  }
}
