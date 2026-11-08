import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mchango/api/models.dart';
import 'package:mchango/services.dart';
import 'package:mchango/ui/groups/create_group_screen.dart';

import 'fake_backend.dart';
import 'terms_test.dart' show groupJson;

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  test('une réponse sans catégorie (ancienne API) donne « communautaire »', () {
    expect(Group.fromJson(groupJson(signedBy: const [])).category, 'community');
    expect(Group.fromJson({...groupJson(signedBy: const []), 'category': 'religion'}).category, 'religion');
  });

  Future<FakeBackend> openCreateScreen(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final backend = FakeBackend()
      ..on('POST', '/groups', (_, body) => {...groupJson(signedBy: const []), 'category': body['category']})
      ..on('GET', '/groups/g-1', (_, _) => {...groupJson(signedBy: const []), 'category': 'religion'});
    await tester.pumpWidget(
      Services(services: backend.services(), child: const MaterialApp(home: CreateGroupScreen())),
    );
    await tester.pumpAndSettle();
    return backend;
  }

  testWidgets('les quatre catégories sont proposées, « communautaire » est choisie d\'office', (tester) async {
    await openCreateScreen(tester);
    for (final c in ['community', 'organization', 'workers', 'religion']) {
      expect(find.byKey(Key('category_$c')), findsOneWidget);
    }
    expect(find.text('Communautaire'), findsOneWidget);
    expect(find.text('Religion'), findsOneWidget);
  });

  testWidgets('sans toucher à la catégorie, le groupe est créé « communautaire »', (tester) async {
    final backend = await openCreateScreen(tester);
    await tester.enterText(find.byKey(const Key('group_name')), 'Kwetu');
    await tester.enterText(find.byKey(const Key('group_amount')), '20000');
    await tester.tap(find.text('Créer la tontine'));
    await tester.pumpAndSettle();
    expect(backend.bodiesOf('POST', '/groups').single['category'], 'community');
  });

  testWidgets('la catégorie choisie part avec la création du groupe', (tester) async {
    final backend = await openCreateScreen(tester);
    await tester.enterText(find.byKey(const Key('group_name')), 'Chorale Saint-Paul');
    await tester.enterText(find.byKey(const Key('group_amount')), '20000');
    await tester.tap(find.byKey(const Key('category_religion')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Créer la tontine'));
    await tester.pumpAndSettle();
    expect(backend.bodiesOf('POST', '/groups').single['category'], 'religion');
  });
}
