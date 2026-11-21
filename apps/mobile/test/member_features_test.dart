import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mchango/services.dart';
import 'package:mchango/ui/attestation/attestation_screen.dart';
import 'package:mchango/ui/goals/goal_screen.dart';
import 'package:mchango/ui/groups/group_screen.dart';
import 'package:mchango/ui/history/history_screen.dart';
import 'package:mchango_audit/mchango_audit.dart';

import 'fake_backend.dart';

// Échange de tour, objectif d'épargne, attestation de régularité, jour de paie.

const groupId = '11111111-1111-4111-8111-111111111111';
const furaha = 'aaaaaaaa-0000-4000-8000-000000000001';
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

Map<String, dynamic> cycle(int n, String id, String name, String status, {Map<String, dynamic>? goal}) => {
  'cycleNumber': n,
  'dueDate': '2026-12-${(24 + n).toString().padLeft(2, '0')}',
  'status': status,
  'beneficiary': {'membershipId': id, 'fullName': name, 'goal': goal},
  'confirmedCount': 0,
  'expectedCount': 2,
};

final groupJson = {
  'id': groupId,
  'name': 'Collègues DGI',
  'category': 'workers',
  'currency': 'CDF',
  'contributionAmountMinor': 20000,
  'frequency': 'monthly',
  'payday': 25,
  'paydayShift': 'before',
  'startDate': '2026-11-25',
  'status': 'active',
  'maxMembers': 30,
  'turnOrderMode': 'chosen',
  'drawSeed': null,
  'myRole': 'member',
  'memberCount': 3,
  'members': [member(furaha, 'Mama Furaha', 1, role: 'president'), member(jean, 'Papa Jean', 2), member(neema, 'Mama Neema', 3)],
};

final attestationJson = {
  'id': 'att-1',
  'code': 'K7MPQ2XWAB',
  'status': 'valid',
  'content': {
    'holder': {'fullName': 'Papa Jean', 'phone': '+24399*****02'},
    'memberSince': '2026-10-01',
    'tontines': {'joined': 2, 'completed': 1, 'active': 1},
    'contributions': {'confirmed': 12, 'onTime': 11, 'late': 1, 'rejected': 0, 'disputed': 0},
    'onTimeRatePercent': 92,
    'turnsReceived': 1,
  },
  'contentHash': 'ab' * 32,
  'qrPayload': 'MCHANGO-ATT1|K7MPQ2XWAB|${'ab' * 32}',
  'issuedAt': '2026-11-21T10:00:00.000Z',
  'expiresAt': '2027-02-19T10:00:00.000Z',
  'revokedAt': null,
};

Widget host(FakeBackend backend, Widget screen) =>
    Services(services: backend.services(), child: MaterialApp(home: screen));

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  testWidgets('groupe : jour de paie, objectif partagé, demande d\'échange reçue puis acceptée', (tester) async {
    var accepted = false;
    final backend = FakeBackend()
      ..on('GET', '/groups/$groupId', (_, _) => groupJson)
      ..on('GET', '/groups/$groupId/cycles', (_, _) => {
        'myMembershipId': jean,
        'cycles': [
          cycle(1, furaha, 'Mama Furaha', 'open', goal: {'kind': 'school', 'label': 'Minerval des enfants'}),
          cycle(2, jean, 'Papa Jean', 'upcoming'),
          cycle(3, neema, 'Mama Neema', 'upcoming'),
        ],
      })
      ..on('GET', '/groups/$groupId/swaps', (_, _) => [
        if (!accepted)
          {
            'id': 'swap-1',
            'groupId': groupId,
            'requester': {'membershipId': neema, 'fullName': 'Mama Neema'},
            'target': {'membershipId': jean, 'fullName': 'Papa Jean'},
            'requesterCycleNumber': 3,
            'targetCycleNumber': 2,
            'reason': 'Deuil dans la famille',
            'status': 'pending',
            'createdAt': '2026-11-21T08:00:00.000Z',
            'expiresAt': '2026-11-24T08:00:00.000Z',
            'decidedAt': null,
          },
      ])
      ..on('POST', '/swaps/swap-1/accept', (_, _) {
        accepted = true;
        return {
          'id': 'swap-1',
          'requester': {'membershipId': neema, 'fullName': 'Mama Neema'},
          'target': {'membershipId': jean, 'fullName': 'Papa Jean'},
          'requesterCycleNumber': 3,
          'targetCycleNumber': 2,
          'status': 'accepted',
          'expiresAt': '2026-11-24T08:00:00.000Z',
        };
      });
    await tester.pumpWidget(host(backend, const GroupScreen(groupId: groupId)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Le 25 de chaque mois (avancé si dimanche ou férié)'), findsOneWidget);
    expect(find.textContaining("Mama Neema propose d'échanger son tour 3 contre votre tour 2"), findsOneWidget);
    expect(find.text('« Deuil dans la famille »'), findsOneWidget);
    // Une demande reçue n'empêche pas d'en faire une ; le bouton est actif (mon tour n'a pas commencé)
    expect(tester.widget<ButtonStyleButton>(find.byKey(const Key('request_swap'))).onPressed, isNotNull);

    await tester.tap(find.text('Accepter'));
    await tester.pumpAndSettle();
    expect(accepted, isTrue);
    expect(find.byKey(const Key('swap_incoming')), findsNothing);

    await tester.scrollUntilVisible(find.textContaining('Objectif : Minerval des enfants'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('Objectif : Minerval des enfants'), findsOneWidget);
  });

  testWidgets('objectif : choisir le type, le texte, le montant, le partage ; envoyé à l\'API', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/groups/$groupId/goal', (_, _) => {'goal': null})
      ..on('PUT', '/groups/$groupId/goal', (_, body) => {'goal': body});
    // L'écran se ferme après l'enregistrement : il est ouvert depuis un autre écran
    await tester.pumpWidget(
      host(
        backend,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const GoalScreen(groupId: groupId, groupName: 'Collègues DGI', currency: 'USD'),
              ),
            ),
            child: const Text('ouvrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('goal_kind_business')));
    await tester.enterText(find.byKey(const Key('goal_label')), 'Stock de pagnes');
    await tester.enterText(find.byKey(const Key('goal_amount')), '150,50');
    await tester.scrollUntilVisible(find.byKey(const Key('goal_shared')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('goal_shared')));
    await tester.pump();
    await tester.scrollUntilVisible(find.text('Enregistrer mon objectif'), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Enregistrer mon objectif'));
    await tester.pumpAndSettle();

    expect(find.byType(GoalScreen), findsNothing);
    expect(backend.bodiesOf('PUT', '/groups/$groupId/goal').single, {
      'kind': 'business',
      'label': 'Stock de pagnes',
      'targetAmountMinor': 15050,
      'targetDate': null,
      'sharedWithGroup': true,
    });
  });

  testWidgets('attestation : chiffres, création, code et QR à montrer', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/me/attestation-stats', (_, _) => attestationJson['content'])
      ..on('GET', '/me/attestations', (_, _) => [])
      ..on('POST', '/me/attestations', (_, _) => attestationJson);
    await tester.pumpWidget(host(backend, const AttestationScreen()));
    await tester.pumpAndSettle();

    expect(find.text('92 %'), findsOneWidget);
    await tester.tap(find.byKey(const Key('attestation_amounts')));
    await tester.pump();
    await tester.tap(find.text('Créer une attestation'));
    await tester.pumpAndSettle();

    expect(backend.bodiesOf('POST', '/me/attestations').single, {'includeAmounts': true});
    expect(find.text('K7MPQ-2XWAB'), findsOneWidget);
    expect(find.text('Papa Jean'), findsOneWidget);
  });

  testWidgets('historique Travailleurs : chaînes privées vérifiées, falsification signalée', (tester) async {
    /// Chaîne valide de [n] événements, hachée comme le fait PostgreSQL (spec/audit-hash.md).
    List<Map<String, dynamic>> chain(String chainId, List<String> actions) {
      final out = <Map<String, dynamic>>[];
      var prev = '0' * 64;
      for (final (i, action) in actions.indexed) {
        final e = AuditEvent(
          chainId: chainId,
          seq: i + 1,
          prevHash: prev,
          actorType: 'system',
          actorId: null,
          deviceId: null,
          action: action,
          createdAt: '2026-11-21T10:00:0$i.000Z',
          payload: action == 'contributions.update' ? '{"status":"confirmed","receipt_number":7}' : '{"method":"mpesa"}',
          signature: null,
          hash: '',
        );
        prev = computeHash(e);
        out.add({
          'chain_id': chainId,
          'seq': i + 1,
          'prev_hash': e.prevHash,
          'actor_type': 'system',
          'actor_id': null,
          'device_id': null,
          'action': action,
          'created_at': e.createdAt,
          'payload': e.payload,
          'signature': null,
          'hash': prev,
          'actor_name': 'Papa Jean',
        });
      }
      return out;
    }

    final group = chain('group:$groupId', ['groups.insert', 'cycles.update']);
    final good = chain('group:$groupId:slot:1:$jean', ['contributions.insert', 'contributions.update']);
    final bad = chain('group:$groupId:slot:1:$neema', ['contributions.insert', 'contributions.update']);
    bad[1]['payload'] = '{"status":"rejected"}'; // contenu changé après coup : le hash ne correspond plus

    Map<String, dynamic> slot(int n, String id, String name, List<Map<String, dynamic>> events) => {
      'chainId': events.first['chain_id'],
      'cycleNumber': n,
      'payer': {'membershipId': id, 'fullName': name},
      'events': events,
    };
    final backend = FakeBackend()
      ..on('GET', '/groups/$groupId/history', (_, _) => {'chainId': 'group:$groupId', 'events': group})
      ..on('GET', '/groups/$groupId/private-history', (_, _) => {
        'chains': [slot(1, jean, 'Papa Jean', good), slot(1, neema, 'Mama Neema', bad)],
      });
    await tester.pumpWidget(host(backend, const HistoryScreen(groupId: groupId)));
    await tester.pumpAndSettle();

    expect(find.text('Paiements confidentiels'), findsOneWidget);
    expect(find.text('Tour 1 · Papa Jean'), findsOneWidget);
    expect(find.text('2 événement(s) vérifié(s)'), findsOneWidget);
    expect(find.text('Journal incohérent : prévenez le groupe et Mchango.'), findsOneWidget);
    // Une chaîne privée falsifiée suffit à lever l'alerte générale
    expect(find.text('Problème détecté'), findsOneWidget);
  });
}
