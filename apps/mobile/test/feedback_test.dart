import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mchango/api/models.dart';
import 'package:mchango/services.dart';
import 'package:mchango/ui/feedback/feedback_screen.dart';

import 'fake_backend.dart';

void main() {
  final group = Group.fromJson({
    'id': 'g-1',
    'name': 'Likelemba Kenya',
    'currency': 'CDF',
    'contributionAmountMinor': 20000,
    'frequency': 'weekly',
    'startDate': '2026-10-20',
    'status': 'active',
    'maxMembers': 10,
  });

  Future<FakeBackend> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.resetPhysicalSize);
    final backend = FakeBackend()
      ..on('POST', '/feedback', (_, _) => {'id': 'f-1'});
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
                    builder: (_) => FeedbackScreen(groups: [group]),
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
    return backend;
  }

  testWidgets('avis sur une tontine, avec une note : envoyé puis écran fermé', (
    tester,
  ) async {
    final backend = await open(tester);
    await tester.tap(find.byKey(const Key('feedback_group')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Likelemba Kenya').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('feedback_star_4')));
    await tester.enterText(
      find.byKey(const Key('feedback_body')),
      '  Le bénéficiaire ne confirme pas.  ',
    );
    await tester.tap(find.byKey(const Key('feedback_send')));
    await tester.pumpAndSettle();

    expect(backend.bodiesOf('POST', '/feedback'), [
      {
        'body': 'Le bénéficiaire ne confirme pas.',
        'groupId': 'g-1',
        'rating': 4,
      },
    ]);
    expect(find.byType(FeedbackScreen), findsNothing);
    expect(find.textContaining('Merci'), findsOneWidget);
  });

  testWidgets('avis général sans note ; un avis vide n\'est pas envoyé', (
    tester,
  ) async {
    final backend = await open(tester);
    await tester.tap(find.byKey(const Key('feedback_send')));
    await tester.pumpAndSettle();
    expect(backend.bodiesOf('POST', '/feedback'), isEmpty);
    expect(find.text('Écrivez votre avis.'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('feedback_body')),
      'Très pratique',
    );
    await tester.tap(find.byKey(const Key('feedback_send')));
    await tester.pumpAndSettle();
    expect(backend.bodiesOf('POST', '/feedback'), [
      {'body': 'Très pratique'},
    ]);
  });
}
