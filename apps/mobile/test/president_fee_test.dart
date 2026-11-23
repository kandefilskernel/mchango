import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mchango/api/models.dart';
import 'package:mchango/services.dart';
import 'package:mchango/ui/cycles/cycle_screen.dart';
import 'package:mchango/ui/groups/president_fee_picker.dart';
import 'package:mchango/util/format.dart';

import 'fake_backend.dart';

const groupId = '11111111-1111-4111-8111-111111111111';
const president = 'aaaaaaaa-0000-4000-8000-000000000001';
const jean = 'aaaaaaaa-0000-4000-8000-000000000002';
const neema = 'aaaaaaaa-0000-4000-8000-000000000003';

Map<String, dynamic> member(String id, String name, int turn, {String role = 'member'}) => {
  'membershipId': id,
  'userId': 'user-$id',
  'fullName': name,
  'phone': '+24399000000$turn',
  'role': role,
  'turnOrder': turn,
};

Group group({String myRole = 'member'}) => Group.fromJson({
  'id': groupId,
  'name': 'Likelemba ya Bamama',
  'currency': 'CDF',
  'contributionAmountMinor': 20000,
  'frequency': 'weekly',
  'startDate': '2026-12-01',
  'status': 'active',
  'maxMembers': 10,
  'turnOrderMode': 'chosen',
  'drawSeed': null,
  'myRole': myRole,
  'memberCount': 3,
  'presidentFeeBps': 500,
  'members': [member(president, 'Maman Neema', 1, role: 'president'), member(jean, 'Papa Jean', 2), member(neema, 'Mama Zawadi', 3)],
});

/// Tour 2 : Papa Jean reçoit 40 000 FC et doit 5 % (2 000 FC) à la présidente.
Map<String, dynamic> cycle2({required String me, Map<String, dynamic>? payment}) => {
  'myMembershipId': me,
  'cycleNumber': 2,
  'dueDate': '2026-12-08',
  'status': 'open',
  'beneficiaryMembershipId': jean,
  'presidentFee': {
    'bps': 500,
    'amountMinor': 2000,
    'payerMembershipId': jean,
    'presidentMembershipId': president,
    'payment': payment,
  },
  'payers': [
    {'membershipId': president, 'fullName': 'Maman Neema', 'status': 'expected', 'contribution': null, 'decisions': <Object>[]},
    {'membershipId': neema, 'fullName': 'Mama Zawadi', 'status': 'expected', 'contribution': null, 'decisions': <Object>[]},
  ],
};

Widget host(FakeBackend backend, Widget screen) =>
    Services(services: backend.services(), child: MaterialApp(home: screen));

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  test('la part se calcule sur la mise, arrondie vers le bas, comme le serveur', () {
    expect(presidentFeeAmount(40000, 500), 2000);
    expect(presidentFeeAmount(40001, 500), 2000);
    expect(presidentFeeAmount(40000, 0), 0);
    expect(presidentFeeAmount(40000, 1000), 4000);
  });

  testWidgets('choix de 0 à 10 %, avec ce que cela fait en francs', (tester) async {
    var bps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => PresidentFeePicker(
              bps: bps,
              potMinor: 40000,
              onChanged: (v) => setState(() => bps = v),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Aucune'), findsOneWidget);
    expect(find.text('10 %'), findsOneWidget);
    expect(find.text('11 %'), findsNothing, reason: 'jamais plus de 10 %');
    await tester.tap(find.byKey(const Key('fee_5')));
    await tester.pump();
    expect(bps, 500);
    expect(find.text('Celui qui reçoit son tour donne 2 000 FC au président.'), findsOneWidget);
  });

  testWidgets('le bénéficiaire déclare avoir payé la présidente', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/groups/$groupId/cycles/2', (_, _) => cycle2(me: jean))
      ..on('POST', '/groups/$groupId/cycles/2/president-fee', (_, body) => {'id': 'fee-1', 'status': 'declared', ...body});
    await tester.pumpWidget(host(backend, CycleScreen(group: group(), cycleNumber: 2)));
    await tester.pumpAndSettle();

    expect(find.text('Part du président : 2 000 FC'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const Key('declare_president_fee')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('declare_president_fee')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fee_method_cash')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('send_president_fee')));
    await tester.pumpAndSettle();

    final sent = backend.bodiesOf('POST', '/groups/$groupId/cycles/2/president-fee').single;
    expect(sent['method'], 'cash');
    expect(sent['offlineId'], isNotEmpty);
  });

  testWidgets('la présidente confirme avoir reçu sa part', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/groups/$groupId/cycles/2', (_, _) => cycle2(
            me: president,
            payment: {'id': 'fee-1', 'status': 'declared', 'method': 'mpesa', 'txReference': 'MP123456'},
          ))
      ..on('POST', '/president-fees/fee-1/decisions', (_, body) => {'id': 'fee-1', 'status': 'confirmed'});
    await tester.pumpWidget(host(backend, CycleScreen(group: group(myRole: 'president'), cycleNumber: 2)));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('declare_president_fee')), findsNothing, reason: 'elle ne se paie pas elle-même');
    await tester.scrollUntilVisible(find.byKey(const Key('confirm_president_fee')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('confirm_president_fee')));
    await tester.pumpAndSettle();
    expect(backend.bodiesOf('POST', '/president-fees/fee-1/decisions').single['decision'], 'confirm');
  });
}
