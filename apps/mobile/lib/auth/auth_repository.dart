import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../storage/key_value_store.dart';
import 'device_identity.dart';
import 'local_pin.dart';

enum AuthStatus { loading, signedOut, locked, signedIn }

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
  AuthRepository(this._api, this._store) {
    _api.onUnauthorized = _refreshSession;
  }

  final ApiClient _api;
  final KeyValueStore _store;

  static const _kDeviceId = 'device_id';
  static const _kSeed = 'device_seed';
  static const _kPinHash = 'pin_hash';
  static const _kUserId = 'user_id';
  static const _kFullName = 'full_name';
  static const _kPinFailures = 'pin_failures';
  static const _kLockedUntil = 'pin_locked_until';

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
    status = deviceId == null ? AuthStatus.signedOut : AuthStatus.locked;
    notifyListeners();
  }

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
      'language': 'fr',
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
        await _store.write(
            _kLockedUntil, '${DateTime.now().add(lockDuration).millisecondsSinceEpoch}');
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

  void lock() {
    _api.accessToken = null;
    status = AuthStatus.locked;
    notifyListeners();
  }

  /// Oublie ce téléphone (il faudra le code SMS et le PIN pour revenir).
  Future<void> forgetDevice() async {
    for (final k in [_kDeviceId, _kSeed, _kPinHash, _kUserId, _kFullName, _kPinFailures, _kLockedUntil]) {
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
