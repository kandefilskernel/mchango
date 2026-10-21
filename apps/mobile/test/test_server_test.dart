import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mchango/app.dart';
import 'package:mchango/config.dart';
import 'package:mchango/storage/key_value_store.dart';

import 'fake_backend.dart';

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  test('lecture de l\'adresse du serveur de test', () {
    expect(normalizeServerUrl('10.163.102.131:3000'), 'http://10.163.102.131:3000');
    expect(normalizeServerUrl(' http://10.163.102.131:3000/ '), 'http://10.163.102.131:3000');
    expect(normalizeServerUrl('https://api.mchango.test'), 'https://api.mchango.test');
    expect(normalizeServerUrl(''), isNull);
    expect(normalizeServerUrl('10.0.0.1:3000/auth'), isNull);
    expect(normalizeServerUrl('http://'), isNull);
  });

  test("l'adresse enregistrée est reprise au démarrage (version de test)", () async {
    final store = MemoryKeyValueStore()..data[testServerKey] = 'http://10.163.102.131:3000';
    expect(await resolveApiUrl(store), 'http://10.163.102.131:3000');
    expect(await resolveApiUrl(MemoryKeyValueStore()), defaultApiUrl);
  });

  testWidgets("le réglage « Serveur de test » change l'API appelée et est gardé", (tester) async {
    final backend = FakeBackend()..on('POST', '/auth/otp/request', (_, _) => {'message': 'ok'});
    final store = MemoryKeyValueStore()..data['onboarding_done'] = '1';
    final services = backend.services(store);
    await services.auth.load();
    await tester.pumpWidget(MchangoApp(services: services));
    await tester.pump(MchangoApp.splashDuration);
    await tester.pumpAndSettle();

    final setting = find.byKey(const Key('test_server'));
    await tester.ensureVisible(setting);
    await tester.pumpAndSettle();
    await tester.tap(setting);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('test_server_field')), '10.163.102.131:3000');
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(store.data[testServerKey], 'http://10.163.102.131:3000');
    expect(
      find.descendant(of: setting, matching: find.text('Serveur de test : http://10.163.102.131:3000')),
      findsOneWidget,
    );

    await tester.enterText(find.byKey(const Key('phone')), '0991234567');
    await tester.tap(find.text('Recevoir un code par SMS'));
    await tester.pumpAndSettle();
    expect(backend.requests.last.url.toString(), 'http://10.163.102.131:3000/auth/otp/request');
  });
}
