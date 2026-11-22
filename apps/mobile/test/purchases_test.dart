import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mchango/api/purchases_api.dart';
import 'package:mchango/services.dart';
import 'package:mchango/ui/purchases/create_offer_screen.dart';
import 'package:mchango/ui/purchases/merchant_screen.dart';
import 'package:mchango/ui/purchases/my_orders_screen.dart';
import 'package:mchango/ui/purchases/offer_screen.dart';
import 'package:mchango/ui/purchases/offers_screen.dart';

import 'fake_backend.dart';

final _endsAt = DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String();

Map<String, dynamic> offerJson({int confirmed = 16, int? reached = 54000}) => {
  'id': 'o-1',
  'title': 'Riz',
  'description': null,
  'unitLabel': 'sac de 25 kg',
  'imageUrl': null,
  'currency': 'CDF',
  'regularPriceMinor': 60000,
  'endsAt': _endsAt,
  'pickupWindowHours': 72,
  'status': 'open',
  'finalUnitPriceMinor': null,
  'closedAt': null,
  'merchantId': 'm-1',
  'merchantName': 'Boutique Nyota',
  'merchantAddress': 'Av. Kinzazi 12',
  'zoneId': 'z-1',
  'city': 'Kinshasa',
  'commune': 'Matete',
  'confirmedUnits': confirmed,
  'thresholdUnits': 20,
  'missingUnits': 20 - confirmed,
  'reachedUnitPriceMinor': reached,
  'tiers': [
    {'minQuantity': 20, 'unitPriceMinor': 54000},
    {'minQuantity': 40, 'unitPriceMinor': 51000},
  ],
};

Map<String, dynamic> orderJson({String status = 'ready', String? code = 'MC-4832'}) => {
  'id': 'ord-1',
  'offerId': 'o-1',
  'quantity': 2,
  'pickupName': 'Aline Nzambe',
  'status': status,
  'createdAt': DateTime.now().toUtc().toIso8601String(),
  'title': 'Riz',
  'unitLabel': 'sac de 25 kg',
  'currency': 'CDF',
  'offerStatus': status == 'reserved' ? 'open' : 'closed',
  'endsAt': _endsAt,
  'finalUnitPriceMinor': status == 'reserved' ? null : 54000,
  'amountDueMinor': status == 'reserved' ? null : 108000,
  'indicativeTotalMinor': status == 'reserved' ? 108000 : null,
  'pickupDeadline': status == 'reserved' ? null : DateTime.now().add(const Duration(days: 3)).toUtc().toIso8601String(),
  'merchantId': 'm-1',
  'merchantName': 'Boutique Nyota',
  'merchantAddress': 'Av. Kinzazi 12',
  'paymentStatus': null,
  'pickupCode': code,
};

Widget _app(FakeBackend backend, Widget home) =>
    Services(services: backend.services(), child: MaterialApp(home: home));

void main() {
  setUpAll(() => initializeDateFormatting('fr_FR'));

  testWidgets('offres sans détour : prix collectif, compteur, puis réserver sa quantité', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/zones', (_, _) => [
        {'id': 'z-1', 'city': 'Kinshasa', 'commune': 'Matete'},
      ])
      ..on('GET', '/offers', (_, _) => [offerJson()])
      ..on('GET', '/offers/o-1', (_, _) => offerJson())
      ..on('GET', '/me/orders', (_, _) => [])
      ..on('POST', '/offers/o-1/orders', (_, _) => orderJson(status: 'reserved', code: null));
    await tester.pumpWidget(_app(backend, const OffersScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Riz'), findsOneWidget);
    expect(find.text('54 000 FC'), findsOneWidget);
    expect(find.text('-10 %'), findsOneWidget);
    expect(find.text('Réservé : 16 sur 20 sac de 25 kg'), findsOneWidget);
    expect(find.text('Encore 4 pour avoir le prix du groupe'), findsOneWidget);

    await tester.tap(find.byKey(const Key('offer_o-1')));
    await tester.pumpAndSettle();
    expect(find.text('Av. Kinzazi 12'), findsOneWidget);
    expect(find.text('À partir de 40'), findsOneWidget);

    await tester.tap(find.byKey(const Key('participate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('qty_plus')));
    await tester.tap(find.byKey(const Key('qty_plus')));
    await tester.pump();
    expect(find.text('Total indicatif : 162 000 FC'), findsOneWidget);

    // Sans nom pour le retrait, rien ne part
    await tester.tap(find.byKey(const Key('confirm_reservation')));
    await tester.pumpAndSettle();
    expect(backend.bodiesOf('POST', '/offers/o-1/orders'), isEmpty);

    await tester.enterText(find.byKey(const Key('pickup_name')), 'Aline Nzambe');
    await tester.tap(find.byKey(const Key('confirm_reservation')));
    await tester.pumpAndSettle();
    final sent = backend.bodiesOf('POST', '/offers/o-1/orders').single;
    expect(sent['quantity'], 3);
    expect(sent['pickupName'], 'Aline Nzambe');
    expect(sent['offlineId'], matches(RegExp(r'^[0-9a-f-]{36}$')));
    expect(find.textContaining('Réservation enregistrée'), findsOneWidget);
  });

  testWidgets('la zone choisie est gardée sur le téléphone et filtre les offres', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/zones', (_, _) => [
        {'id': 'z-1', 'city': 'Kinshasa', 'commune': 'Matete'},
      ])
      ..on('GET', '/offers', (_, _) => []);
    final services = backend.services();
    await tester.pumpWidget(Services(services: services, child: const MaterialApp(home: OffersScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Aucune offre en cours ici pour le moment.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('zone_z-1')));
    await tester.pumpAndSettle();
    expect(await services.store.read(OffersScreen.zoneKey), 'z-1');
    expect(backend.requests.last.url.queryParameters['zoneId'], 'z-1');
  });

  testWidgets('inviter : proposer à un de mes groupes, sans rien acheter', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/offers/o-1', (_, _) => offerJson())
      ..on('GET', '/me/orders', (_, _) => [])
      ..on('GET', '/groups', (_, _) => [
        {
          'id': 'g-1',
          'name': 'Les Solidaires',
          'currency': 'CDF',
          'contributionAmountMinor': 50000,
          'frequency': 'monthly',
          'startDate': '2026-12-01',
          'status': 'active',
          'maxMembers': 30,
          'myRole': 'member',
          'memberCount': 12,
        },
      ])
      ..on('POST', '/offers/o-1/shares', (_, _) => {'id': 's-1', 'offerId': 'o-1', 'channel': 'group', 'token': null});
    await tester.pumpWidget(
      _app(backend, const Scaffold(body: Builder(builder: _openOffer))),
    );
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('invite')));
    await tester.pumpAndSettle();
    expect(find.text('Aucun achat n\'est engagé par l\'envoi d\'une invitation.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('propose_g-1')));
    await tester.pumpAndSettle();
    expect(backend.bodiesOf('POST', '/offers/o-1/shares').single, {'channel': 'group', 'groupId': 'g-1'});
    expect(backend.bodiesOf('POST', '/offers/o-1/orders'), isEmpty);
    expect(find.text('Offre proposée à Les Solidaires.'), findsOneWidget);
  });

  testWidgets('déjà réservé : la fiche montre ma réservation au lieu de « Participer »', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/offers/o-1', (_, _) => offerJson())
      ..on('GET', '/me/orders', (_, _) => [orderJson(status: 'reserved', code: null)]);
    await tester.pumpWidget(_app(backend, const Scaffold(body: Builder(builder: _openOffer))));
    await tester.tap(find.text('ouvrir'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('my_reservation')), findsOneWidget);
    expect(find.text('Ma réservation : 2 sac de 25 kg'), findsOneWidget);
    expect(find.byKey(const Key('participate')), findsNothing);
  });

  testWidgets('mes commandes : montant à payer et code de retrait après la clôture', (tester) async {
    final backend = FakeBackend()..on('GET', '/me/orders', (_, _) => [orderJson()]);
    await tester.pumpWidget(_app(backend, const MyOrdersScreen()));
    await tester.pumpAndSettle();
    expect(find.text('MC-4832'), findsOneWidget);
    expect(find.text('À payer en boutique : 108 000 FC'), findsOneWidget);
    expect(find.text('Au nom de Aline Nzambe'), findsOneWidget);
    expect(find.byKey(const Key('cancel_ord-1')), findsNothing, reason: 'après la clôture, on ne se retire plus');
  });

  testWidgets('mes commandes : une réservation se retire tant que l\'offre est ouverte', (tester) async {
    final backend = FakeBackend()
      ..on('GET', '/me/orders', (_, _) => [orderJson(status: 'reserved', code: null)])
      ..on('POST', '/orders/ord-1/cancel', (_, _) => orderJson(status: 'cancelled', code: null));
    await tester.pumpWidget(_app(backend, const MyOrdersScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Total indicatif : 108 000 FC'), findsOneWidget);
    await tester.tap(find.byKey(const Key('cancel_ord-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Annuler la réservation'));
    await tester.pumpAndSettle();
    expect(backend.requests.where((r) => r.url.path == '/orders/ord-1/cancel'), hasLength(1));
  });

  testWidgets('boutique : retrouver par le code, encaisser, puis remettre contre le code', (tester) async {
    var status = 'ready';
    Map<String, dynamic> counterOrder() => {
      ...orderJson(status: status),
      'pickupCode': 'MC-4832',
      'paymentStatus': status == 'paid' ? 'confirmed' : null,
    };
    final backend = FakeBackend()
      ..on('GET', '/merchants/m-1/orders', (_, _) => [
        counterOrder(),
        {...orderJson(), 'id': 'ord-2', 'pickupName': 'Grâce M.', 'pickupCode': 'MC-1111'},
      ])
      ..on('POST', '/merchants/m-1/orders/ord-1/confirm-payment', (_, _) {
        status = 'paid';
        return counterOrder();
      })
      ..on('POST', '/merchants/m-1/orders/ord-1/confirm-pickup', (_, _) {
        status = 'picked_up';
        return counterOrder();
      });
    final merchant = Merchant(id: 'm-1', name: 'Boutique Nyota', address: 'Av. Kinzazi 12', status: 'active', commune: 'Matete');
    await tester.pumpWidget(_app(backend, MerchantScreen(merchant: merchant)));
    await tester.pumpAndSettle();
    expect(find.text('Commandes à encaisser ou à remettre : 2'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('counter_code')), 'mc-48');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('counter_ord-2')), findsNothing);
    await tester.tap(find.byKey(const Key('counter_ord-1')));
    await tester.pumpAndSettle();

    // Mobile money sans ID : refusé avant l'envoi
    await tester.tap(find.byKey(const Key('counter_method')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('M-Pesa').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_payment')));
    await tester.pumpAndSettle();
    expect(backend.bodiesOf('POST', '/merchants/m-1/orders/ord-1/confirm-payment'), isEmpty);

    await tester.enterText(find.byKey(const Key('counter_txref')), 'qt77ab12cd');
    await tester.tap(find.byKey(const Key('confirm_payment')));
    await tester.pumpAndSettle();
    expect(backend.bodiesOf('POST', '/merchants/m-1/orders/ord-1/confirm-payment').single, {
      'method': 'mpesa',
      'txReference': 'qt77ab12cd',
    });
    expect(find.text('Paiement confirmé.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('handover_code')), 'MC-4832');
    await tester.tap(find.byKey(const Key('confirm_pickup')));
    await tester.pumpAndSettle();
    expect(backend.bodiesOf('POST', '/merchants/m-1/orders/ord-1/confirm-pickup').single, {'pickupCode': 'MC-4832'});
    expect(find.text('Produit remis. Merci !'), findsOneWidget);
  });

  testWidgets('nouvelle offre : paliers vérifiés avant l\'envoi, puis création et publication', (tester) async {
    final backend = FakeBackend()
      ..on('POST', '/merchants/m-1/offers', (_, _) => {...offerJson(), 'id': 'o-9', 'status': 'draft'})
      ..on('POST', '/merchants/m-1/offers/o-9/publish', (_, _) => {...offerJson(), 'id': 'o-9'});
    await tester.pumpWidget(_app(backend, const CreateOfferScreen(merchantId: 'm-1')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('offer_title')), 'Riz');
    await tester.enterText(find.byKey(const Key('offer_unit')), 'sac de 25 kg');
    await tester.enterText(find.byKey(const Key('offer_regular')), '60 000');
    await tester.enterText(find.byKey(const Key('tier_qty_0')), '20');
    await tester.enterText(find.byKey(const Key('tier_price_0')), '60000');
    await tester.scrollUntilVisible(find.byKey(const Key('save_offer')), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byKey(const Key('save_offer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_offer')));
    await tester.pumpAndSettle();
    expect(find.text('Chaque palier doit être moins cher que le prix habituel.'), findsOneWidget);
    expect(backend.bodiesOf('POST', '/merchants/m-1/offers'), isEmpty);
    // Le message recouvre le bas de l'écran : on le ferme avant de corriger
    ScaffoldMessenger.of(tester.element(find.byType(CreateOfferScreen))).removeCurrentSnackBar();
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('tier_price_0')), '54000');
    await tester.scrollUntilVisible(find.byKey(const Key('add_tier')), -200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('add_tier')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tier_qty_1')), '40');
    await tester.enterText(find.byKey(const Key('tier_price_1')), '51000');
    await tester.scrollUntilVisible(find.byKey(const Key('save_offer')), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.byKey(const Key('save_offer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save_offer')));
    await tester.pumpAndSettle();

    final sent = backend.bodiesOf('POST', '/merchants/m-1/offers').single;
    expect(sent['regularPriceMinor'], 60000);
    expect(sent['pickupWindowHours'], 72);
    expect(sent['tiers'], [
      {'minQuantity': 20, 'unitPriceMinor': 54000},
      {'minQuantity': 40, 'unitPriceMinor': 51000},
    ]);
    expect(backend.requests.where((r) => r.url.path == '/merchants/m-1/offers/o-9/publish'), hasLength(1));
  });
}

/// Ouvre la fiche de l'offre o-1 par-dessus un premier écran (pour pouvoir revenir).
Widget _openOffer(BuildContext context) => TextButton(
  onPressed: () => Navigator.push(
    context,
    MaterialPageRoute<void>(builder: (_) => const OfferScreen(offerId: 'o-1')),
  ),
  child: const Text('ouvrir'),
);

