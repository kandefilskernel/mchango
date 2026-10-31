import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mchango/services.dart';
import 'package:mchango/sms/operator_sms.dart';
import 'package:mchango/ui/cycles/cycle_screen.dart';
import 'package:mchango/ui/cycles/declare_screen.dart';

import 'fake_backend.dart';
import 'sms_paste_test.dart' as paste show clipboard, group;

/// ID Airtel daté d'aujourd'hui (AAMMJJ), pour ne pas dépendre de la date du test.
String airtelIdToday(String suffix) {
  final n = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return 'XX${two(n.year % 100)}${two(n.month)}${two(n.day)}.0912.$suffix';
}

Map<String, dynamic> cycleJson(Map<String, dynamic> risk) => {
  'myMembershipId': 'm-1',
  'cycleNumber': 1,
  'dueDate': '2026-11-02',
  'status': 'open',
  'beneficiaryMembershipId': 'm-1',
  'payers': [
    {
      'membershipId': 'm-2',
      'fullName': 'Papa Jean',
      'status': 'declared',
      'decisions': <Object>[],
      'contribution': {
        'id': 'c-1',
        'payerMembershipId': 'm-2',
        'receiverMembershipId': 'm-1',
        'witnessMembershipId': null,
        'amountMinor': 2000,
        'method': 'airtel',
        'txReference': 'XX261024.0912.P10293',
        'status': 'declared',
        'isLate': false,
        'risk': risk,
      },
    },
  ],
};

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  group0();
  groupDeclare();
  groupConfirm();
}

void group0() {
  test('couche 1 : forme du SMS et date de l\'opération', () {
    final airtel = parseOperatorSms('Trans ID: XX261023.2305.R45862: Vous avez recu USD 6.0000 de 990000001.')!;
    expect(airtel.format, SmsFormat.airtel);
    expect(airtel.date, DateTime(2026, 10, 23));
    expect(airtel.isStale(DateTime(2026, 10, 25)), isFalse);
    expect(airtel.isStale(DateTime(2026, 10, 31)), isTrue);

    final reference = parseOperatorSms(
      'Le depot a reussi Montant:20,00 USD Reference de la transaction:DH2769HLCYN le 02-08-2026 a 14:40:34.',
    )!;
    expect(reference.format, SmsFormat.reference);
    expect(reference.date, DateTime(2026, 8, 2));

    final generic = parseOperatorSms('Paiement de 20 USD, Ref: AB12345678')!;
    expect(generic.format, SmsFormat.generic);
    expect(generic.date, isNull);
    expect(generic.isStale(DateTime(2030)), isFalse);
  });
}

void groupDeclare() {
  Future<FakeBackend> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final backend = FakeBackend()
      ..on('POST', '/groups/g-1/cycles/1/contributions', (_, body) => {
            'id': 'c-1',
            'payerMembershipId': 'm-2',
            'receiverMembershipId': 'm-1',
            'witnessMembershipId': null,
            'amountMinor': 2000,
            'method': 'airtel',
            'txReference': body['txReference'],
            'status': 'declared',
            'isLate': false,
          });
    await tester.pumpWidget(
      Services(
        services: backend.services(),
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => DeclareScreen(group: paste.group, cycleNumber: 1, beneficiary: paste.group.members.first),
                  ),
                ),
                child: const Text('ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('method_airtel')));
    await tester.pumpAndSettle();
    return backend;
  }

  testWidgets('SMS collé : ce que l\'app a constaté part avec la déclaration', (tester) async {
    final backend = await open(tester);
    final id = airtelIdToday('P10293');
    paste.clipboard('Trans ID: $id: Vous avez envoye USD 20.0000 a 990000001. Nouveau solde est: 3.10 USD.');
    await tester.tap(find.byKey(const Key('paste_sms')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Déclarer le paiement'));
    await tester.pumpAndSettle();
    expect(backend.bodiesOf('POST', '/groups/g-1/cycles/1/contributions').single['smsCheck'], {
      'pasted': true,
      'format': 'airtel',
      'amountMatches': true,
    });
  });

  testWidgets('vieux SMS : avertissement ; ID retouché à la main : compte comme tapé', (tester) async {
    final backend = await open(tester);
    paste.clipboard('Trans ID: XX200101.0912.P10293: Vous avez envoye USD 20.0000 a 990000001.');
    await tester.tap(find.byKey(const Key('paste_sms')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ce SMS date du 01/01/2020'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('tx_reference')), airtelIdToday('P99999'));
    await tester.tap(find.text('Déclarer le paiement'));
    await tester.pumpAndSettle();
    expect(backend.bodiesOf('POST', '/groups/g-1/cycles/1/contributions').single['smsCheck'], {'pasted': false});
  });
}

void groupConfirm() {
  Future<FakeBackend> open(WidgetTester tester, Map<String, dynamic> risk) async {
    tester.view.physicalSize = const Size(1080, 2600);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final backend = FakeBackend()
      ..on('GET', '/groups/g-1/cycles/1', (_, _) => cycleJson(risk))
      ..on('POST', '/contributions/c-1/decisions', (_, _) => {
            'id': 'c-1',
            'payerMembershipId': 'm-2',
            'receiverMembershipId': 'm-1',
            'witnessMembershipId': null,
            'amountMinor': 2000,
            'method': 'airtel',
            'txReference': 'XX261024.0912.P10293',
            'status': 'confirmed',
            'isLate': false,
            'cycleStatus': 'open',
          });
    await tester.pumpWidget(
      Services(services: backend.services(), child: MaterialApp(home: CycleScreen(group: paste.group, cycleNumber: 1))),
    );
    await tester.pumpAndSettle();
    return backend;
  }

  testWidgets('vert : « J\'ai reçu » confirme directement', (tester) async {
    final backend = await open(tester, {'level': 'green', 'reasons': ['first_payment']});
    expect(find.byKey(const Key('risk_green')), findsOneWidget);
    await tester.tap(find.text("J'ai reçu"));
    await tester.pumpAndSettle();
    expect(backend.bodiesOf('POST', '/contributions/c-1/decisions'), [
      {'decision': 'confirm'},
    ]);
  });

  testWidgets('orange : il faut cocher « j\'ai vérifié » avant de confirmer', (tester) async {
    final backend = await open(tester, {'level': 'orange', 'reasons': ['sms_amount_mismatch']});
    await tester.tap(find.text("J'ai reçu"));
    await tester.pumpAndSettle();
    expect(find.text('Vérifiez avant de confirmer'), findsOneWidget);
    expect(find.textContaining('ne montre pas le montant'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('risk_confirm'))).onPressed, isNull);
    await tester.tap(find.byKey(const Key('risk_checked')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('risk_confirm')));
    await tester.pumpAndSettle();
    expect(backend.bodiesOf('POST', '/contributions/c-1/decisions'), [
      {'decision': 'confirm', 'riskAcknowledged': true},
    ]);
  });

  testWidgets('rouge : seul le SMS reçu avec le même ID débloque la confirmation', (tester) async {
    final backend = await open(tester, {'level': 'red', 'reasons': ['tx_reused_after_rejection']});
    expect(find.byKey(const Key('risk_red')), findsOneWidget);
    await tester.tap(find.text("J'ai reçu"));
    await tester.pumpAndSettle();
    expect(find.text('Vérification obligatoire'), findsOneWidget);
    await tester.tap(find.byKey(const Key('risk_checked')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const Key('risk_confirm'))).onPressed, isNull);

    paste.clipboard('Trans ID: XX261024.0912.Z00000: Vous avez recu USD 20.0000 de 990000002.');
    await tester.tap(find.byKey(const Key('risk_paste_sms')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ne correspond pas'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('risk_confirm'))).onPressed, isNull);

    paste.clipboard('Trans ID: XX261024.0912.P10293: Vous avez recu USD 20.0000 de 990000002.');
    await tester.tap(find.byKey(const Key('risk_paste_sms')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('risk_confirm')));
    await tester.pumpAndSettle();
    expect(backend.bodiesOf('POST', '/contributions/c-1/decisions'), [
      {'decision': 'confirm', 'riskAcknowledged': true, 'receivedTxReference': 'XX261024.0912.P10293'},
    ]);
  });
}
