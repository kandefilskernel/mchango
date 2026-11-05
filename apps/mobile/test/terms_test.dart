import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mchango/auth/local_pin.dart';
import 'package:mchango/services.dart';
import 'package:mchango/storage/key_value_store.dart';
import 'package:mchango/ui/groups/group_screen.dart';

import 'fake_backend.dart';

const _hash = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, Object?> groupJson({required List<String> signedBy}) => {
  'id': 'g-1',
  'name': 'Kwetu',
  'currency': 'CDF',
  'contributionAmountMinor': 20000,
  'frequency': 'weekly',
  'startDate': '2026-11-02',
  'status': 'draft',
  'maxMembers': 10,
  'turnOrderMode': 'chosen',
  'drawSeed': null,
  'myRole': 'member',
  'memberCount': 3,
  'members': [
    {'membershipId': 'm-1', 'userId': 'u-1', 'fullName': 'Mama Furaha', 'phone': '+243990000001', 'role': 'president', 'turnOrder': 1},
    {'membershipId': 'm-2', 'userId': 'u-2', 'fullName': 'Papa Jean', 'phone': '+243990000002', 'role': 'member', 'turnOrder': 2},
    {'membershipId': 'm-3', 'userId': 'u-3', 'fullName': 'Mama Neema', 'phone': '+243990000003', 'role': 'member', 'turnOrder': 3},
  ],
  'terms': {
    'hash': _hash,
    'ready': true,
    'signedBy': signedBy,
    'missing': [
      for (final (id, name) in [('m-1', 'Mama Furaha'), ('m-2', 'Papa Jean'), ('m-3', 'Mama Neema')])
        if (!signedBy.contains(id)) {'membershipId': id, 'fullName': name},
    ],
    'allSigned': signedBy.length == 3,
  },
};

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  testWidgets('un membre lit le règlement et le signe avec son PIN ; on voit qui manque', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    var signed = <String>['m-1'];
    final backend = FakeBackend()
      ..on('GET', '/groups/g-1', (_, _) => groupJson(signedBy: signed))
      ..on('POST', '/groups/g-1/sign', (_, body) {
        signed = [...signed, 'm-2'];
        return groupJson(signedBy: signed)['terms'];
      });
    final store = MemoryKeyValueStore();
    await tester.runAsync(() async => store.data['pin_hash'] = await LocalPin.hash('482915'));
    final services = backend.services(store)..auth.userId = 'u-2';

    await tester.pumpWidget(Services(services: services, child: const MaterialApp(home: GroupScreen(groupId: 'g-1'))));
    await tester.pumpAndSettle();

    expect(find.text('Règlement à signer'), findsOneWidget);
    expect(find.text('1/3'), findsOneWidget);
    expect(find.text('Tour 1 : Mama Furaha'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sign_terms')));
    await tester.pumpAndSettle();
    expect(find.text('Règlement de « Kwetu »'), findsOneWidget);
    expect(find.text('40 000 FC'), findsOneWidget, reason: 'ce que je recevrai à mon tour');

    await tester.enterText(find.byKey(const Key('sign_pin')), '482915');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('confirm_sign')));
      for (var i = 0; i < 100 && backend.bodiesOf('POST', '/groups/g-1/sign').isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpAndSettle();

    expect(backend.bodiesOf('POST', '/groups/g-1/sign').single, {'termsHash': _hash});
    expect(find.text('Vous avez signé ce règlement.'), findsOneWidget);
    expect(find.text('2/3'), findsOneWidget);
  });

  testWidgets('PIN faux : rien n\'est signé', (tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final backend = FakeBackend()..on('GET', '/groups/g-1', (_, _) => groupJson(signedBy: ['m-1']));
    final store = MemoryKeyValueStore();
    await tester.runAsync(() async => store.data['pin_hash'] = await LocalPin.hash('482915'));
    final services = backend.services(store)..auth.userId = 'u-2';
    await tester.pumpWidget(Services(services: services, child: const MaterialApp(home: GroupScreen(groupId: 'g-1'))));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sign_terms')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sign_pin')), '111222');
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('confirm_sign')));
      await Future<void>.delayed(const Duration(seconds: 2));
    });
    await tester.pumpAndSettle();

    expect(find.text('PIN incorrect.'), findsOneWidget);
    expect(backend.bodiesOf('POST', '/groups/g-1/sign'), isEmpty);
  });
}
