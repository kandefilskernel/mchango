// Vitrine pour les visuels (affiches, captures) : l'app branchée sur des données d'exemple,
// sans serveur ni compte réel. Jamais livrée aux membres.
//   flutter build web -t tool/showcase.dart -o build/showcase
// puis ouvrir index.html?screen=home|cycle|declare|receipt|carnet[&lang=sw|ln|en]
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mchango/api/api_client.dart';
import 'package:mchango/api/models.dart';
import 'package:mchango/auth/auth_repository.dart';
import 'package:mchango/l10n/l10n.dart';
import 'package:mchango/services.dart';
import 'package:mchango/storage/key_value_store.dart';
import 'package:mchango/ui/carnet/carnet_screen.dart';
import 'package:mchango/ui/cycles/cycle_screen.dart';
import 'package:mchango/ui/cycles/declare_screen.dart';
import 'package:mchango/ui/groups/home_screen.dart';
import 'package:mchango/ui/receipts/receipt_screen.dart';
import 'package:mchango/ui/theme.dart';

const _groupId = '11111111-1111-4111-8111-111111111111';
const _furaha = 'aaaaaaaa-0000-4000-8000-000000000001';
const _jean = 'aaaaaaaa-0000-4000-8000-000000000002';
const _neema = 'aaaaaaaa-0000-4000-8000-000000000003';
const _kabila = 'aaaaaaaa-0000-4000-8000-000000000004';

Map<String, Object?> _member(String id, String name, int turn, {String role = 'member'}) => {
  'membershipId': id,
  'userId': 'user-$id',
  'fullName': name,
  'phone': '+24399000000$turn',
  'role': role,
  'turnOrder': turn,
};

final _group = {
  'id': _groupId,
  'name': 'Kwetu Marché Mzee',
  'currency': 'CDF',
  'contributionAmountMinor': 20000,
  'frequency': 'weekly',
  'startDate': '2026-10-19',
  'status': 'active',
  'maxMembers': 10,
  'turnOrderMode': 'draw',
  'drawSeed': 'a1b2c3d4e5f60718293a4b5c6d7e8f90',
  'myRole': 'member',
  'memberCount': 4,
  'members': [
    _member(_furaha, 'Mama Furaha', 1, role: 'president'),
    _member(_jean, 'Papa Jean', 2),
    _member(_neema, 'Mama Neema', 3),
    _member(_kabila, 'Papa Kabila', 4),
  ],
};

Map<String, Object?> _contribution(String id, String payer, String status, String tx) => {
  'id': id,
  'payerMembershipId': payer,
  'receiverMembershipId': _furaha,
  'witnessMembershipId': null,
  'amountMinor': 20000,
  'method': 'mpesa',
  'txReference': tx,
  'status': status,
  'isLate': false,
  'offlineId': 'o-$id',
  'declaredAt': '2026-10-21T09:00:00.000Z',
};

final _routes = <String, Object>{
  '/groups': [
    _group,
    {..._group, 'id': 'g-2', 'name': 'Enseignants Kenya', 'currency': 'USD', 'contributionAmountMinor': 5000,
      'frequency': 'monthly', 'memberCount': 12, 'myRole': 'president'},
  ],
  '/pin-resets/pending': <Object>[],
  '/me/carnet': {
    'totals': [
      {'currency': 'CDF', 'paidMinor': 60000, 'receivedMinor': 0},
    ],
    'upcoming': [
      {'kind': 'pay', 'groupId': _groupId, 'groupName': 'Kwetu Marché Mzee', 'cycleNumber': 1, 'dueDate': '2026-10-26',
        'amountMinor': 20000, 'currency': 'CDF', 'counterpart': 'Mama Furaha', 'late': false},
      {'kind': 'receive', 'groupId': _groupId, 'groupName': 'Kwetu Marché Mzee', 'cycleNumber': 2, 'dueDate': '2026-11-02',
        'amountMinor': 60000, 'currency': 'CDF', 'counterpart': null, 'late': false},
    ],
    'groups': [
      {'groupId': _groupId, 'name': 'Kwetu Marché Mzee', 'status': 'active', 'currency': 'CDF', 'contributionAmountMinor': 20000,
        'frequency': 'weekly', 'myTurn': {'cycleNumber': 2, 'dueDate': '2026-11-02', 'status': 'upcoming'},
        'paidCount': 3, 'paidMinor': 60000, 'receivedCount': 0, 'receivedMinor': 0, 'pendingCount': 0},
    ],
  },
  '/groups/$_groupId/cycles/1': {
    'myMembershipId': _jean,
    'cycleNumber': 1,
    'dueDate': '2026-10-26',
    'status': 'open',
    'beneficiaryMembershipId': _furaha,
    'payers': [
      {'membershipId': _jean, 'fullName': 'Papa Jean', 'status': 'expected', 'contribution': null, 'decisions': <Object>[]},
      {'membershipId': _neema, 'fullName': 'Mama Neema', 'status': 'confirmed',
        'contribution': _contribution('c-2', _neema, 'confirmed', 'MP241021KX7Q'),
        'decisions': [{'membershipId': _furaha, 'decision': 'confirm', 'note': null, 'at': '2026-10-21T10:00:00.000Z'}]},
      {'membershipId': _kabila, 'fullName': 'Papa Kabila', 'status': 'declared',
        'contribution': _contribution('c-3', _kabila, 'declared', 'AM2410219ZT4'), 'decisions': <Object>[]},
    ],
  },
  '/contributions/c-2/receipt': {
    'receiptNumber': 'MCH-00000042',
    'groupName': 'Kwetu Marché Mzee',
    'cycleNumber': 1,
    'currency': 'CDF',
    'amountMinor': 20000,
    'method': 'mpesa',
    'txReference': 'MP241021KX7Q',
    'isLate': false,
    'payer': {'fullName': 'Mama Neema'},
    'beneficiary': {'fullName': 'Mama Furaha'},
    'witness': null,
    'declaredAt': '2026-10-21T09:00:00.000Z',
    'confirmedAt': '2026-10-21T10:00:00.000Z',
    'audit': {'seq': 27, 'hash': '9f2c1a7be41d0c35a8e6f1b2d4c7a9e05b3f8d1c6a2e4b7f9c0d3e5a1b8c6d2f'},
    'qrPayload': 'https://mchango.cd/r/MCH-00000042?h=9f2c1a7be41d0c35',
  },
};

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('fr_FR');
  final params = Uri.base.queryParameters;
  Lang.instance.current = AppLanguage.fromCode(params['lang']);

  final client = MockClient((request) async {
    final body = _routes[request.url.path];
    return http.Response.bytes(
      utf8.encode(jsonEncode(body ?? {'message': 'Exemple absent.'})),
      body == null ? 404 : 200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
  final store = MemoryKeyValueStore()..data.addAll({'full_name': 'Jean Kabeya', 'user_id': 'u-jean'});
  final services = AppServices(client: ApiClient('http://exemple', client: client), store: store);
  await services.auth.load();
  services.auth.status = AuthStatus.signedIn;
  services.auth.fullName = 'Jean Kabeya';

  final Widget screen = switch (params['screen']) {
    'cycle' => CycleScreen(group: Group.fromJson(_group), cycleNumber: 1),
    'receipt' => const ReceiptScreen(contributionId: 'c-2'),
    'carnet' => const CarnetScreen(),
    'declare' => DeclareScreen(
      group: Group.fromJson(_group),
      cycleNumber: 1,
      beneficiary: Group.fromJson(_group).members.first,
    ),
    _ => const HomeScreen(),
  };
  runApp(
    Services(
      services: services,
      child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: screen),
    ),
  );
}
