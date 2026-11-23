import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mchango/api/models.dart';
import 'package:mchango/services.dart';
import 'package:mchango/ui/groups/edit_group_screen.dart';

import 'fake_backend.dart';

Group draftGroup() => Group.fromJson({
  'id': 'g-1',
  'name': 'Likelemba ya Bamama',
  'category': 'community',
  'currency': 'CDF',
  'contributionAmountMinor': 20000,
  'frequency': 'weekly',
  'startDate': '2030-01-10',
  'status': 'draft',
  'maxMembers': 10,
  'turnOrderMode': null,
  'drawSeed': null,
  'myRole': 'president',
  'memberCount': 2,
  'members': [
    {'membershipId': 'm-1', 'userId': 'u-1', 'fullName': 'Maman Neema', 'phone': '+243990000001', 'role': 'president', 'turnOrder': null},
    {'membershipId': 'm-2', 'userId': 'u-2', 'fullName': 'Maman Furaha', 'phone': '+243990000002', 'role': 'member', 'turnOrder': null},
  ],
});

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  testWidgets('le président passe la tontine à « chaque mois » et change le montant', (tester) async {
    final backend = FakeBackend()..on('PATCH', '/groups/g-1', (_, body) => {...draftGroup().toJsonForTest(), ...body});
    await tester.pumpWidget(
      Services(
        services: backend.services(),
        child: MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => EditGroupScreen(group: draftGroup()))),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();

    // Les trois choix sont visibles d'un coup d'œil
    expect(find.text('Chaque jour'), findsOneWidget);
    expect(find.text('Chaque semaine'), findsOneWidget);
    expect(find.text('Chaque mois'), findsOneWidget);

    await tester.tap(find.byKey(const Key('frequency_monthly')));
    await tester.enterText(find.byKey(const Key('edit_amount')), '30000');
    await tester.scrollUntilVisible(find.text('Enregistrer'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    final sent = backend.bodiesOf('PATCH', '/groups/g-1').single;
    expect(sent['frequency'], 'monthly');
    expect(sent['contributionAmountMinor'], 30000);
    expect(sent['name'], 'Likelemba ya Bamama');
    expect(find.byType(EditGroupScreen), findsNothing, reason: "l'écran se ferme une fois enregistré");
  });

  testWidgets('moins de personnes que de membres déjà là : refusé avant d\'envoyer', (tester) async {
    final backend = FakeBackend();
    await tester.pumpWidget(
      Services(services: backend.services(), child: MaterialApp(home: EditGroupScreen(group: draftGroup()))),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.byKey(const Key('edit_max')), 200, scrollable: find.byType(Scrollable).first);
    await tester.enterText(find.byKey(const Key('edit_max')), '1');
    await tester.scrollUntilVisible(find.text('Enregistrer'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Enregistrer'));
    await tester.pumpAndSettle();

    expect(find.text('Entre 2 et 100 personnes.'), findsOneWidget);
    expect(backend.bodiesOf('PATCH', '/groups/g-1'), isEmpty);
  });
}

extension on Group {
  /// Réponse minimale de l'API, pour le faux serveur du test.
  Map<String, dynamic> toJsonForTest() => {
    'id': id,
    'name': name,
    'category': category,
    'currency': currency,
    'contributionAmountMinor': contributionAmountMinor,
    'frequency': frequency,
    'startDate': startDate,
    'status': status,
    'maxMembers': maxMembers,
    'turnOrderMode': null,
    'drawSeed': null,
    'myRole': myRole,
    'memberCount': memberCount,
    'members': <Object>[],
  };
}
