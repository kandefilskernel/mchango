import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mchango/app.dart';
import 'package:mchango/auth/auth_repository.dart';
import 'package:mchango/storage/key_value_store.dart';

import 'fake_backend.dart';

/// Laisse tourner les vrais calculs asynchrones (clé Ed25519, PBKDF2) jusqu'à [done].
Future<void> runUntil(WidgetTester tester, Future<void> Function() action, bool Function() done) async {
  await tester.runAsync(() async {
    await action();
    for (var i = 0; i < 100 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  });
  await tester.pumpAndSettle();
}

Future<void> startApp(WidgetTester tester, FakeBackend backend, MemoryKeyValueStore store) async {
  final services = backend.services(store);
  await services.auth.load();
  await tester.pumpWidget(MchangoApp(services: services));
  await tester.pump(MchangoApp.splashDuration);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  testWidgets('PIN oublié : demande, attente du garant, puis accès avec le nouveau PIN', (tester) async {
    var status = 'pending';
    final backend = FakeBackend()
      ..on('POST', '/auth/otp/request', (_, _) => {'message': 'ok'})
      ..on('POST', '/auth/otp/verify', (_, _) => {'otpToken': 'otp', 'accountExists': true})
      ..on(
        'POST',
        '/auth/pin-reset',
        (_, _) => {
          'requestId': 'r-1',
          'status': 'pending',
          'expiresAt': '2026-10-23T10:00:00.000Z',
          'guarantors': [
            {'fullName': 'Mama Furaha', 'groupName': 'Kwetu'},
          ],
        },
      )
      ..on(
        'GET',
        '/auth/pin-reset/r-1',
        (_, _) => {
          'status': status,
          'expiresAt': '2026-10-23T10:00:00.000Z',
          'deviceId': status == 'completed' ? 'd-2' : null,
          'guarantors': status == 'pending'
              ? [
                  {'fullName': 'Mama Furaha', 'groupName': 'Kwetu'},
                ]
              : <Object>[],
        },
      )
      ..on('POST', '/auth/challenge', (_, _) => {'nonce': 'n-1', 'expiresIn': 120})
      ..on(
        'POST',
        '/auth/session',
        (_, _) => {'userId': 'u-1', 'deviceId': 'd-2', 'accessToken': 'acces', 'expiresIn': 900},
      )
      ..on('GET', '/me', (_, _) => {'id': 'u-1', 'phone': '+243991234567', 'full_name': 'Papa Jean', 'language': 'fr'})
      ..on('GET', '/groups', (_, _) => <Object>[])
      ..on('GET', '/pin-resets/pending', (_, _) => <Object>[]);
    final store = MemoryKeyValueStore()..data['onboarding_done'] = '1';
    await startApp(tester, backend, store);

    await tester.enterText(find.byKey(const Key('phone')), '0991234567');
    await tester.tap(find.text('Recevoir un code par SMS'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('code')), '205412');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('forgot_pin')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new_pin')), '270418');
    await tester.enterText(find.byKey(const Key('new_pin2')), '270418');
    await runUntil(
      tester,
      () => tester.tap(find.text('Demander un nouveau PIN')),
      () => store.data['pin_reset_pin_hash'] != null,
    );

    final sent = backend.bodiesOf('POST', '/auth/pin-reset').single;
    expect(sent['newPin'], '270418');
    expect(store.data['pin_reset_id'], 'r-1');
    expect(store.data.values.contains('270418'), isFalse, reason: 'le PIN ne doit pas être stocké');
    expect(find.text('Votre garant doit confirmer'), findsOneWidget);
    expect(find.text('Mama Furaha'), findsOneWidget);

    // Pas encore confirmé
    final check = find.byKey(const Key('check_reset'));
    await tester.scrollUntilVisible(check, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(find.text('Votre garant doit confirmer'), findsOneWidget);

    // Le garant a confirmé : ce téléphone est lié avec le nouveau PIN
    status = 'completed';
    await tester.tap(check);
    await tester.pumpAndSettle();
    expect(store.data['device_id'], 'd-2');
    expect(store.data['pin_hash'], startsWith('pbkdf2-sha256'));
    expect(store.data.containsKey('pin_reset_id'), isFalse);
    expect(find.text('Bonjour Papa'), findsOneWidget);
  });

  testWidgets('le garant voit la demande sur l\'accueil et la confirme', (tester) async {
    final backend = FakeBackend()
      ..on('POST', '/auth/challenge', (_, _) => {'nonce': 'n-1', 'expiresIn': 120})
      ..on(
        'POST',
        '/auth/session',
        (_, _) => {'userId': 'u-9', 'deviceId': 'd-9', 'accessToken': 'acces', 'expiresIn': 900},
      )
      ..on('GET', '/groups', (_, _) => <Object>[])
      ..on(
        'GET',
        '/pin-resets/pending',
        (_, _) => [
          {
            'requestId': 'r-1',
            'fullName': 'Papa Jean',
            'phone': '+243991234567',
            'groupName': 'Kwetu',
            'createdAt': '2026-10-21T08:00:00.000Z',
            'expiresAt': '2026-10-23T08:00:00.000Z',
          },
        ],
      )
      ..on('POST', '/pin-resets/r-1/approve', (_, _) => {'status': 'completed'});

    // Un garant déjà connecté sur ce téléphone
    final store = MemoryKeyValueStore()
      ..data.addAll({
        'onboarding_done': '1',
        'device_id': 'd-9',
        'device_seed': 'BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc=',
        'user_id': 'u-9',
        'full_name': 'Mama Furaha',
      });
    final services = backend.services(store);
    await services.auth.load();
    services.auth.status = AuthStatus.signedIn;
    services.client.accessToken = 'acces';
    await tester.pumpWidget(MchangoApp(services: services));
    await tester.pump(MchangoApp.splashDuration);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('approvals_banner')), findsOneWidget);
    expect(find.text('Papa Jean demande un nouveau PIN'), findsOneWidget);
    await tester.tap(find.byKey(const Key('approvals_banner')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Confirmer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('de vive voix'), findsOneWidget, reason: 'avertissement avant de confirmer');
    await tester.tap(find.text('Je confirme'));
    await tester.pumpAndSettle();

    expect(backend.requests.where((r) => r.url.path == '/pin-resets/r-1/approve'), hasLength(1));
    expect(find.text('Papa Jean peut maintenant utiliser son nouveau PIN.'), findsOneWidget);
  });
}
