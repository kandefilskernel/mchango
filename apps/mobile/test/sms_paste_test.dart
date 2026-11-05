import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mchango/api/models.dart';
import 'package:mchango/services.dart';
import 'package:mchango/ui/cycles/declare_screen.dart';

import 'fake_backend.dart';

final group = Group.fromJson({
  'id': 'g-1',
  'name': 'Kwetu',
  'currency': 'USD',
  'contributionAmountMinor': 2000,
  'frequency': 'weekly',
  'startDate': '2026-11-02',
  'status': 'active',
  'maxMembers': 10,
  'turnOrderMode': 'chosen',
  'drawSeed': null,
  'myRole': 'member',
  'memberCount': 2,
  'members': [
    {'membershipId': 'm-1', 'userId': 'u-1', 'fullName': 'Mama Furaha', 'phone': '+243990000001', 'role': 'president', 'turnOrder': 1},
    {'membershipId': 'm-2', 'userId': 'u-2', 'fullName': 'Papa Jean', 'phone': '+243990000002', 'role': 'member', 'turnOrder': 2},
  ],
});

/// Le presse-papiers du test contient [text].
void clipboard(String text) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
    call,
  ) async {
    if (call.method == 'Clipboard.getData') return {'text': text};
    return null;
  });
}

Future<void> openDeclare(WidgetTester tester) async {
  // Écran de téléphone en hauteur : tout le formulaire est visible
  tester.view.physicalSize = const Size(1080, 2600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    Services(
      services: FakeBackend().services(),
      child: MaterialApp(home: DeclareScreen(group: group, cycleNumber: 1, beneficiary: group.members.first)),
    ),
  );
  await tester.tap(find.byKey(const Key('method_airtel')));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  testWidgets('coller le SMS : l\'ID se remplit et le montant est comparé à la cotisation', (tester) async {
    await openDeclare(tester);
    clipboard('Trans ID: XX261024.0912.P10293: Vous avez envoye USD 20.0000 a 990000001. Nouveau solde est: 3.10 USD.');
    await tester.tap(find.byKey(const Key('paste_sms')));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(find.byKey(const Key('tx_reference'))).controller!.text, 'XX261024.0912.P10293');
    expect(find.text('ID trouvé : XX261024.0912.P10293'), findsOneWidget);
    expect(find.textContaining('comme la cotisation'), findsOneWidget);
  });

  testWidgets('un SMS de retrait est refusé : ce n\'est pas un envoi au bénéficiaire', (tester) async {
    await openDeclare(tester);
    clipboard('TID:CO261019.1034.T00551. Vous avez retire 5.0000 USD chez AGENT 990000002. Votre nouveau solde: 31.00 USD.');
    await tester.tap(find.byKey(const Key('paste_sms')));
    await tester.pumpAndSettle();

    expect(find.textContaining('retrait chez un agent'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('tx_reference'))).controller!.text, isEmpty);
  });

  testWidgets('montant différent : avertissement, l\'ID reste rempli', (tester) async {
    await openDeclare(tester);
    clipboard('Trans ID: XX261024.0912.P10294: Vous avez envoye USD 15.0000 a 990000001.');
    await tester.tap(find.byKey(const Key('paste_sms')));
    await tester.pumpAndSettle();

    expect(find.textContaining('vérifiez'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('tx_reference'))).controller!.text, 'XX261024.0912.P10294');
  });
}
