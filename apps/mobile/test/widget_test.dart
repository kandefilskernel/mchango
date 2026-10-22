import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mchango/api/models.dart';
import 'package:mchango/app.dart';
import 'package:mchango/services.dart';
import 'package:mchango/storage/key_value_store.dart';
import 'package:mchango/ui/cycles/cycle_screen.dart';
import 'package:mchango/ui/cycles/declare_screen.dart';
import 'package:mchango/ui/history/event_label.dart';
import 'package:mchango/ui/history/history_screen.dart';

import 'fake_backend.dart';

const groupId = '11111111-1111-4111-8111-111111111111';
const furaha = 'aaaaaaaa-0000-4000-8000-000000000001'; // bénéficiaire du tour 1
const jean = 'aaaaaaaa-0000-4000-8000-000000000002';
const neema = 'aaaaaaaa-0000-4000-8000-000000000003';

Map<String, dynamic> member(String id, String name, int turn, {String role = 'member'}) => {
  'membershipId': id,
  'userId': 'user-$id',
  'fullName': name,
  'phone': '+24399000000$turn',
  'role': role,
  'turnOrder': turn,
  'joinedAt': '2026-10-21T08:00:00.000Z',
};

final groupJson = {
  'id': groupId,
  'name': 'Likelemba Kenya',
  'type': 'informel',
  'currency': 'CDF',
  'contributionAmountMinor': 20000,
  'frequency': 'weekly',
  'payoutMode': 'direct_to_beneficiary',
  'startDate': '2026-11-02',
  'status': 'active',
  'maxMembers': 30,
  'turnOrderMode': 'chosen',
  'drawSeed': null,
  'myRole': 'president',
  'memberCount': 3,
  'members': [
    member(furaha, 'Mama Furaha', 1, role: 'president'),
    member(jean, 'Papa Jean', 2),
    member(neema, 'Mama Neema', 3),
  ],
};

Map<String, dynamic> cycleJson({required String me, String jeanStatus = 'declared'}) => {
  'myMembershipId': me,
  'cycleNumber': 1,
  'dueDate': '2026-11-02',
  'status': 'open',
  'beneficiaryMembershipId': furaha,
  'payers': [
    {
      'membershipId': jean,
      'fullName': 'Papa Jean',
      'status': jeanStatus,
      'contribution': {
        'id': 'c-1',
        'payerMembershipId': jean,
        'receiverMembershipId': furaha,
        'witnessMembershipId': null,
        'amountMinor': 20000,
        'method': 'mpesa',
        'txReference': 'RK45TX9QPL',
        'status': jeanStatus,
        'isLate': false,
        'offlineId': 'o-1',
        'declaredAt': '2026-10-21T09:00:00.000Z',
      },
      'decisions': <Object>[],
    },
    {
      'membershipId': neema,
      'fullName': 'Mama Neema',
      'status': 'expected',
      'contribution': null,
      'decisions': <Object>[],
    },
  ],
};

Widget host(AppServices services, Widget child) => Services(
  services: services,
  child: MaterialApp(home: child),
);

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  testWidgets("inscription : numéro, code, nom et PIN, puis l'accueil", (tester) async {
    final backend = FakeBackend()
      ..on('POST', '/auth/otp/request', (_, _) => {'message': 'ok'})
      ..on('POST', '/auth/otp/verify', (_, _) => {'otpToken': 'otp', 'accountExists': false})
      ..on(
        'POST',
        '/auth/register',
        (_, _) => {'userId': 'u-1', 'deviceId': 'd-1', 'accessToken': 'acces', 'expiresIn': 900},
      )
      ..on('GET', '/groups', (_, _) => <Object>[]);
    final store = MemoryKeyValueStore();
    final services = backend.services(store);
    await services.auth.load();
    await tester.pumpWidget(MchangoApp(services: services));
    // Écran de démarrage, puis l'histoire en images (premier lancement)
    expect(find.text('Chaque cotisation, vérifiable.'), findsOneWidget);
    await tester.pump(MchangoApp.splashDuration);
    await tester.pumpAndSettle();
    expect(find.text("Seul, c'est long"), findsOneWidget);
    for (final title in ['Ensemble, on cotise', 'À chaque tour, un membre reçoit tout', 'Tout est vérifiable']) {
      await tester.tap(find.byKey(const Key('onboarding_next')));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
    }
    await tester.tap(find.text('Commencer'));
    await tester.pumpAndSettle();
    expect(store.data['onboarding_done'], '1', reason: "l'histoire ne se montre qu'une fois");

    await tester.enterText(find.byKey(const Key('phone')), '0991234567');
    await tester.tap(find.text('Recevoir un code par SMS'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('code')), '205412');
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('name')), 'Mama Furaha');
    await tester.enterText(find.byKey(const Key('pin')), '123456');
    await tester.enterText(find.byKey(const Key('pin2')), '123456');
    await tester.tap(find.text('Créer mon compte'));
    await tester.pump();
    expect(find.textContaining('suite'), findsOneWidget, reason: 'PIN faible refusé sans appel réseau');
    expect(backend.bodiesOf('POST', '/auth/register'), isEmpty);

    await tester.enterText(find.byKey(const Key('pin')), '482915');
    await tester.enterText(find.byKey(const Key('pin2')), '482915');
    // Génération de clé et PBKDF2 : vrai calcul asynchrone
    await tester.runAsync(() async {
      await tester.tap(find.text('Créer mon compte'));
      for (var i = 0; i < 100 && store.data['pin_hash'] == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });
    await tester.pumpAndSettle();

    final sent = backend.bodiesOf('POST', '/auth/register').single;
    expect(sent['fullName'], 'Mama Furaha');
    expect(sent['pin'], '482915');
    expect(base64.decode(sent['devicePublicKey'] as String), hasLength(32));
    expect(store.data['device_id'], 'd-1');
    expect(store.data['pin_hash'], startsWith('pbkdf2-sha256'));
    expect(store.data.values.any((v) => v == '482915'), isFalse, reason: 'le PIN ne doit pas être stocké');
    expect(find.text('Mes tontines'), findsOneWidget);
    expect(find.textContaining('aucune tontine'), findsOneWidget);
  });

  testWidgets('le bénéficiaire confirme un paiement déclaré', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/groups/$groupId/cycles/1', (_, _) => cycleJson(me: furaha))
      ..on(
        'POST',
        '/contributions/c-1/decisions',
        (_, body) => {
          ...(cycleJson(me: furaha)['payers'] as List).first['contribution'] as Map<String, dynamic>,
          'status': 'confirmed',
          'cycleStatus': 'open',
        },
      );
    final services = backend.services();
    await tester.pumpWidget(host(services, CycleScreen(group: Group.fromJson(groupJson), cycleNumber: 1)));
    await tester.pumpAndSettle();

    expect(find.text('Vous recevez ce tour'), findsOneWidget);
    expect(find.text('Papa Jean'), findsOneWidget);
    expect(find.textContaining('À confirmer'), findsOneWidget);
    await tester.tap(find.text("J'ai reçu"));
    await tester.pumpAndSettle();

    expect(backend.bodiesOf('POST', '/contributions/c-1/decisions').single, {'decision': 'confirm'});
    expect(find.text('Cotisation confirmée.'), findsOneWidget);
  });

  testWidgets("un payeur voit à qui payer, et ne voit pas le bouton de confirmation", (tester) async {
    final backend = FakeBackend()..on('GET', '/groups/$groupId/cycles/1', (_, _) => cycleJson(me: neema));
    await tester.pumpWidget(host(backend.services(), CycleScreen(group: Group.fromJson(groupJson), cycleNumber: 1)));
    await tester.pumpAndSettle();

    expect(find.text('Payez 20 000 FC à Mama Furaha'), findsOneWidget);
    expect(find.text('Numéro : +243990000001'), findsOneWidget);
    expect(find.text("J'ai payé"), findsOneWidget);
    expect(find.text("J'ai reçu"), findsNothing);
  });

  testWidgets('déclaration : même offlineId si on réessaie après une coupure', (tester) async {
    var attempts = 0;
    final backend = FakeBackend()
      ..on('POST', '/groups/$groupId/cycles/1/contributions', (_, body) {
        attempts++;
        if (attempts == 1) return error(503, 'Service indisponible.');
        return {...((cycleJson(me: neema)['payers'] as List).first['contribution'] as Map<String, dynamic>)};
      });
    final group = Group.fromJson(groupJson);
    await tester.pumpWidget(
      host(
        backend.services(),
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => DeclareScreen(group: group, cycleNumber: 1, beneficiary: group.members.first),
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

    await tester.tap(find.byKey(const Key('method_mpesa')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tx_reference')), 'rk45tx9qpl');
    final submit = find.text('Déclarer le paiement');
    await tester.scrollUntilVisible(submit, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Service indisponible.'), findsOneWidget);

    await tester.tap(submit);
    await tester.pumpAndSettle();
    final bodies = backend.bodiesOf('POST', '/groups/$groupId/cycles/1/contributions');
    expect(bodies, hasLength(2));
    expect(bodies[0]['offlineId'], bodies[1]['offlineId']);
    expect(bodies[1], containsPair('method', 'mpesa'));
    expect(bodies[1], containsPair('amountMinor', 20000));
    expect(find.text('ouvrir'), findsOneWidget, reason: "retour à l'écran précédent");
  });

  group('historique vérifié sur le téléphone', () {
    final vectors =
        jsonDecode(File('../../spec/test-vectors/audit_chain.json').readAsStringSync()) as Map<String, dynamic>;
    final chain = (vectors['chains'] as List).cast<Map<String, dynamic>>().firstWhere(
      (c) => (c['chain_id'] as String).startsWith('group:'),
    );
    final vectorGroupId = (chain['chain_id'] as String).substring('group:'.length);
    List<Map<String, dynamic>> named(List events) => [
      for (final e in events) {...(e as Map<String, dynamic>), 'actor_name': 'Mama Furaha'},
    ];

    Future<FakeBackend> show(WidgetTester tester, List events, {MemoryKeyValueStore? store}) async {
      final backend = FakeBackend()
        ..on(
          'GET',
          '/groups/$vectorGroupId/history',
          (_, _) => {'chainId': chain['chain_id'], 'events': named(events)},
        );
      await tester.pumpWidget(host(backend.services(store), HistoryScreen(groupId: vectorGroupId)));
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('journal intact (vecteurs produits par PostgreSQL)', (tester) async {
      final store = MemoryKeyValueStore();
      await show(tester, chain['events'] as List, store: store);
      expect(find.text('Intact'), findsOneWidget);
      expect(store.data['chain_head:$vectorGroupId'], startsWith('${(chain['events'] as List).length}:'));
    });

    testWidgets('journal falsifié : alerte', (tester) async {
      final tampered = (vectors['invalid_cases'] as List).first as Map<String, dynamic>;
      await show(tester, tampered['events'] as List);
      expect(find.text('Problème détecté'), findsOneWidget);
      expect(find.textContaining("à partir de l'événement n°${tampered['first_invalid_seq']}"), findsOneWidget);
    });

    testWidgets('historique réécrit depuis la dernière vérification : alerte', (tester) async {
      final store = MemoryKeyValueStore()..data['chain_head:$vectorGroupId'] = '2:${'f' * 64}';
      await show(tester, chain['events'] as List, store: store);
      expect(find.text('Problème détecté'), findsOneWidget);
      expect(find.textContaining('a changé depuis votre dernière vérification'), findsOneWidget);
    });
  });

  test('libellés des événements', () {
    expect(
      describeEvent('groups.insert', '{"name":"Likelemba"}', 'Mama Furaha'),
      'Mama Furaha a créé la tontine « Likelemba »',
    );
    expect(
      describeEvent('confirmations.insert', '{"decision":"witness"}', 'Papa Jean'),
      'Papa Jean a témoigné de la remise en espèces',
    );
    expect(
      describeEvent('contributions.update', '{"status":"confirmed","receipt_number":42}', 'X'),
      'Paiement confirmé (reçu MCH-00000042)',
    );
    expect(
      describeEvent('group.turn_order_set', '{"mode":"draw","seed":"${'ab' * 32}"}', 'Mama'),
      'Mama a lancé le tirage au sort (graine abababababab…)',
    );
    expect(describeEvent('inconnu', 'pas du json', 'X'), 'X : inconnu');
  });
}
