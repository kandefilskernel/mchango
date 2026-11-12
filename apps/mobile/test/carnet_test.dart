import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mchango/services.dart';
import 'package:mchango/ui/carnet/carnet_screen.dart';

import 'fake_backend.dart';

final carnetJson = {
  'totals': [
    {'currency': 'CDF', 'paidMinor': 40000, 'receivedMinor': 0},
    {'currency': 'USD', 'paidMinor': 0, 'receivedMinor': 10000},
  ],
  'upcoming': [
    {
      'kind': 'pay',
      'groupId': 'g-1',
      'groupName': 'Likelemba Kenya',
      'cycleNumber': 3,
      'dueDate': '2026-10-20',
      'amountMinor': 20000,
      'currency': 'CDF',
      'counterpart': 'Mama Neema',
      'late': true,
    },
    {
      'kind': 'receive',
      'groupId': 'g-1',
      'groupName': 'Likelemba Kenya',
      'cycleNumber': 4,
      'dueDate': '2026-10-27',
      'amountMinor': 60000,
      'currency': 'CDF',
      'counterpart': null,
      'late': false,
    },
  ],
  'groups': [
    {
      'groupId': 'g-1',
      'name': 'Likelemba Kenya',
      'status': 'active',
      'currency': 'CDF',
      'contributionAmountMinor': 20000,
      'frequency': 'weekly',
      'myTurn': {'cycleNumber': 4, 'dueDate': '2026-10-27', 'status': 'upcoming'},
      'paidCount': 2,
      'paidMinor': 40000,
      'receivedCount': 0,
      'receivedMinor': 0,
      'pendingCount': 1,
    },
  ],
};

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  testWidgets('carnet : versé et reçu par devise, prochaines étapes, détail par tontine', (tester) async {
    final backend = FakeBackend()..on('GET', '/me/carnet', (_, _) => carnetJson);
    await tester.pumpWidget(
      Services(services: backend.services(), child: const MaterialApp(home: CarnetScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('40 000 FC'), findsWidgets);
    expect(find.text('100,00 \$'), findsOneWidget, reason: 'les dollars restent à part des francs');
    expect(find.text('Payer 20 000 FC à Mama Neema'), findsOneWidget);
    expect(find.textContaining('en retard depuis le 20/10/2026'), findsOneWidget);
    expect(find.text('Mon tour : je reçois 60 000 FC'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('En attente de confirmation'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Mon tour : 4, le 27/10/2026'), findsOneWidget);
    expect(find.text('Versé (2 paiement(s))'), findsOneWidget);
  });
}
