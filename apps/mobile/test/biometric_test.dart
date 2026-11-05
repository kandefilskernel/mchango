import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mchango/app.dart';
import 'package:mchango/auth/auth_repository.dart';
import 'package:mchango/storage/key_value_store.dart';

import 'fake_backend.dart';

FakeBackend sessionBackend() => FakeBackend()
  ..on('POST', '/auth/challenge', (_, _) => {'nonce': 'n-1', 'expiresIn': 120})
  ..on('POST', '/auth/session', (_, _) => {'userId': 'u-9', 'deviceId': 'd-9', 'accessToken': 'acces', 'expiresIn': 900})
  ..on('GET', '/groups', (_, _) => <Object>[])
  ..on('GET', '/pin-resets/pending', (_, _) => <Object>[]);

/// Téléphone déjà lié, application verrouillée.
MemoryKeyValueStore lockedPhone({bool biometric = true}) => MemoryKeyValueStore()
  ..data.addAll({
    'onboarding_done': '1',
    'device_id': 'd-9',
    'device_seed': 'BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc=',
    'pin_hash': 'pbkdf2-sha256\$1\$AAAA\$AAAA',
    'user_id': 'u-9',
    'full_name': 'Mama Furaha',
    if (biometric) 'biometric_unlock': '1',
  });

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  testWidgets("empreinte activée : la fenêtre s'ouvre seule et donne accès à l'accueil", (tester) async {
    final backend = sessionBackend();
    final finger = FakeBiometric();
    final services = backend.services(lockedPhone(), finger);
    await services.auth.load();
    await tester.runAsync(() async {
      await tester.pumpWidget(MchangoApp(services: services));
      await tester.pump(MchangoApp.splashDuration);
      for (var i = 0; i < 100 && services.auth.status != AuthStatus.signedIn; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpAndSettle();

    expect(finger.prompts, ['Ouvrir Mchango']);
    expect(services.auth.status, AuthStatus.signedIn);
    expect(backend.requests.where((r) => r.url.path == '/auth/session'), hasLength(1), reason: 'session signée par la clé du téléphone');
    expect(find.text('Mes tontines'), findsOneWidget);
  });

  testWidgets("empreinte non reconnue : on reste sur l'écran du PIN", (tester) async {
    final finger = FakeBiometric(recognized: false);
    final services = sessionBackend().services(lockedPhone(), finger);
    await services.auth.load();
    await tester.pumpWidget(MchangoApp(services: services));
    await tester.pump(MchangoApp.splashDuration);
    await tester.pumpAndSettle();

    expect(finger.prompts, hasLength(1));
    expect(find.text('Empreinte non reconnue. Utilisez votre PIN.'), findsOneWidget);
    expect(find.byKey(const Key('unlock_pin')), findsOneWidget);
    expect(find.byKey(const Key('unlock_biometric')), findsOneWidget, reason: 'on peut réessayer');
    expect(services.auth.status, AuthStatus.locked);
  });

  testWidgets("empreinte pas activée : aucune fenêtre, PIN seulement", (tester) async {
    final finger = FakeBiometric();
    final services = sessionBackend().services(lockedPhone(biometric: false), finger);
    await services.auth.load();
    await tester.pumpWidget(MchangoApp(services: services));
    await tester.pump(MchangoApp.splashDuration);
    await tester.pumpAndSettle();

    expect(finger.prompts, isEmpty);
    expect(find.byKey(const Key('unlock_biometric')), findsNothing);
  });

  test("activation : seulement si l'empreinte est reconnue ; oubliée avec le téléphone ; bloquée pendant la pause", () async {
    final store = lockedPhone(biometric: false);
    final finger = FakeBiometric(recognized: false);
    final auth = sessionBackend().services(store, finger).auth;
    await auth.load();

    expect(await auth.enableBiometric(), isFalse);
    expect(await auth.biometricEnabled(), isFalse);
    finger.recognized = true;
    expect(await auth.enableBiometric(), isTrue);
    expect(await auth.biometricEnabled(), isTrue);

    // Pause après trop de PIN faux : l'empreinte ne la contourne pas
    store.data['pin_locked_until'] = '${DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch}';
    expect(await auth.unlockWithBiometric(), isFalse);

    await auth.forgetDevice();
    expect(store.data.containsKey('biometric_unlock'), isFalse);
  });
}
