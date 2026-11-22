import 'package:flutter_test/flutter_test.dart';
import 'package:mchango/auth/auth_repository.dart';
import 'package:mchango/storage/key_value_store.dart';

import 'fake_backend.dart';

/// Signer le règlement demande le PIN. Une pause (5 PIN faux) restée d'un ancien compte ne doit pas
/// bloquer un compte neuf, et une vraie pause doit être annoncée comme telle.
void main() {
  Future<(AuthRepository, MemoryKeyValueStore)> signedOutDevice() async {
    final backend = FakeBackend()
      ..on('POST', '/auth/register', (_, _) => {'userId': 'u-2', 'deviceId': 'd-2', 'accessToken': 'acces', 'expiresIn': 900});
    final store = MemoryKeyValueStore();
    final services = backend.services(store);
    await services.auth.load();
    return (services.auth, store);
  }

  test('un nouveau compte repart sans la pause d\'un ancien compte', () async {
    final (auth, store) = await signedOutDevice();
    // Restes d'essais ratés sur ce téléphone, avant de créer le compte
    store.data['pin_failures'] = '4';
    store.data['pin_locked_until'] = '${DateTime.now().add(const Duration(minutes: 4)).millisecondsSinceEpoch}';
    expect(await auth.lockRemaining(), isNotNull);

    await auth.register(otpToken: 'jeton', fullName: 'Maman Neema', pin: '482915');

    expect(await auth.lockRemaining(), isNull);
    expect(store.data['pin_failures'], '0');
    expect(await auth.confirmWithPin('482915'), isTrue, reason: 'le PIN choisi à l\'inscription signe');
    expect(await auth.confirmWithPin('111222'), isFalse);
  });

  test('cinq PIN faux : pause annoncée, même avec le bon PIN', () async {
    final (auth, _) = await signedOutDevice();
    await auth.register(otpToken: 'jeton', fullName: 'Maman Neema', pin: '482915');
    for (var i = 0; i < AuthRepository.maxPinFailures; i++) {
      expect(await auth.confirmWithPin('000999'), isFalse);
    }
    expect(await auth.lockRemaining(), isNotNull);
    expect(await auth.confirmWithPin('482915'), isFalse, reason: 'en pause, le bon PIN non plus ne passe pas');
  });
}
