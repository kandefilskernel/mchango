import 'api_client.dart';
import 'models.dart';

/// Appels et modèles des achats groupés (contrat : spec/achats.md).

int _int(Object? v) => (v as num).toInt();
int? _intOrNull(Object? v) => (v as num?)?.toInt();
DateTime? _dateOrNull(Object? v) => v == null ? null : DateTime.parse(v as String);

class PickupZone {
  PickupZone({required this.id, required this.city, required this.commune});

  factory PickupZone.fromJson(Json j) =>
      PickupZone(id: j['id'] as String, city: j['city'] as String, commune: j['commune'] as String);

  final String id;
  final String city;
  final String commune;
}

class OfferTier {
  OfferTier({required this.minQuantity, required this.unitPriceMinor});

  factory OfferTier.fromJson(Json j) =>
      OfferTier(minQuantity: _int(j['minQuantity']), unitPriceMinor: _int(j['unitPriceMinor']));

  final int minQuantity;
  final int unitPriceMinor;
}

class Offer {
  Offer({
    required this.id,
    required this.title,
    required this.description,
    required this.unitLabel,
    required this.currency,
    required this.regularPriceMinor,
    required this.endsAt,
    required this.pickupWindowHours,
    required this.status,
    required this.finalUnitPriceMinor,
    required this.merchantId,
    required this.merchantName,
    required this.merchantAddress,
    required this.city,
    required this.commune,
    required this.confirmedUnits,
    required this.thresholdUnits,
    required this.reachedUnitPriceMinor,
    required this.tiers,
    this.photos = const [],
  });

  factory Offer.fromJson(Json j) => Offer(
    id: j['id'] as String,
    title: j['title'] as String,
    description: j['description'] as String?,
    unitLabel: j['unitLabel'] as String,
    currency: j['currency'] as String,
    regularPriceMinor: _int(j['regularPriceMinor']),
    endsAt: DateTime.parse(j['endsAt'] as String),
    pickupWindowHours: _int(j['pickupWindowHours']),
    status: j['status'] as String,
    finalUnitPriceMinor: _intOrNull(j['finalUnitPriceMinor']),
    merchantId: j['merchantId'] as String,
    merchantName: j['merchantName'] as String,
    merchantAddress: j['merchantAddress'] as String,
    city: j['city'] as String,
    commune: j['commune'] as String,
    confirmedUnits: _int(j['confirmedUnits']),
    thresholdUnits: _intOrNull(j['thresholdUnits']) ?? 0,
    reachedUnitPriceMinor: _intOrNull(j['reachedUnitPriceMinor']),
    tiers: [for (final t in (j['tiers'] as List? ?? const [])) OfferTier.fromJson(t as Json)],
    photos: [for (final p in (j['photos'] as List? ?? const [])) p as String],
  );

  final String id;
  final String title;
  final String? description;
  final String unitLabel;
  final String currency;
  final int regularPriceMinor;
  final DateTime endsAt;
  final int pickupWindowHours;
  final String status;
  final int? finalUnitPriceMinor;
  final String merchantId;
  final String merchantName;
  final String merchantAddress;
  final String city;
  final String commune;

  /// Unités réellement réservées (jamais les invitations).
  final int confirmedUnits;

  /// Seuil minimum : sous ce nombre à la date de fin, l'offre est annulée.
  final int thresholdUnits;
  final int? reachedUnitPriceMinor;
  final List<OfferTier> tiers;

  /// Photos de la marchandise : adresses relatives à l'API (`/offers/<id>/photos/<n>`).
  final List<String> photos;

  bool get isOpen => status == 'open' && endsAt.isAfter(DateTime.now());

  /// Prix affiché : final après clôture, sinon palier atteint, sinon premier palier.
  int get displayPriceMinor =>
      finalUnitPriceMinor ?? reachedUnitPriceMinor ?? (tiers.isEmpty ? regularPriceMinor : tiers.first.unitPriceMinor);

  int get discountPercent => ((regularPriceMinor - displayPriceMinor) * 100 / regularPriceMinor).round();

  int get missingUnits => (thresholdUnits - confirmedUnits).clamp(0, thresholdUnits);

  /// Prochain palier pas encore atteint (null : le meilleur prix est atteint).
  OfferTier? get nextTier {
    for (final tier in tiers) {
      if (tier.minQuantity > confirmedUnits) return tier;
    }
    return null;
  }
}

class PurchaseOrder {
  PurchaseOrder({
    required this.id,
    required this.offerId,
    required this.quantity,
    required this.pickupName,
    required this.status,
    required this.title,
    required this.unitLabel,
    required this.currency,
    required this.offerStatus,
    required this.endsAt,
    required this.amountDueMinor,
    required this.indicativeTotalMinor,
    required this.pickupDeadline,
    required this.merchantName,
    required this.merchantAddress,
    required this.paymentStatus,
    required this.pickupCode,
  });

  factory PurchaseOrder.fromJson(Json j) => PurchaseOrder(
    id: j['id'] as String,
    offerId: j['offerId'] as String,
    quantity: _int(j['quantity']),
    pickupName: j['pickupName'] as String,
    status: j['status'] as String,
    title: j['title'] as String,
    unitLabel: j['unitLabel'] as String,
    currency: j['currency'] as String,
    offerStatus: j['offerStatus'] as String,
    endsAt: DateTime.parse(j['endsAt'] as String),
    amountDueMinor: _intOrNull(j['amountDueMinor']),
    indicativeTotalMinor: _intOrNull(j['indicativeTotalMinor']),
    pickupDeadline: _dateOrNull(j['pickupDeadline']),
    merchantName: j['merchantName'] as String,
    merchantAddress: j['merchantAddress'] as String,
    paymentStatus: j['paymentStatus'] as String?,
    pickupCode: j['pickupCode'] as String?,
  );

  final String id;
  final String offerId;
  final int quantity;
  final String pickupName;

  /// reserved, ready, paid, picked_up, cancelled, expired
  final String status;
  final String title;
  final String unitLabel;
  final String currency;
  final String offerStatus;
  final DateTime endsAt;

  /// Montant à payer, connu après la clôture (quantité × prix final).
  final int? amountDueMinor;

  /// Avant la clôture : quantité × prix du palier atteint (null si le seuil n'est pas atteint).
  final int? indicativeTotalMinor;
  final DateTime? pickupDeadline;
  final String merchantName;
  final String merchantAddress;
  final String? paymentStatus;
  final String? pickupCode;

  bool get isActive => status != 'cancelled' && status != 'expired';
  bool get canChange => status == 'reserved' && offerStatus == 'open' && endsAt.isAfter(DateTime.now());
}

class Merchant {
  Merchant({required this.id, required this.name, required this.address, required this.status, required this.commune});

  factory Merchant.fromJson(Json j) => Merchant(
    id: j['id'] as String,
    name: j['name'] as String,
    address: j['address'] as String,
    status: j['status'] as String,
    commune: j['commune'] as String,
  );

  final String id;
  final String name;
  final String address;
  final String status;
  final String commune;
}

class GroupProposal {
  GroupProposal({
    required this.offerId,
    required this.title,
    required this.unitLabel,
    required this.currency,
    required this.regularPriceMinor,
    required this.reachedUnitPriceMinor,
    required this.endsAt,
    required this.status,
    required this.proposedByName,
    required this.confirmedMembers,
    required this.confirmedUnits,
    required this.thresholdUnits,
  });

  factory GroupProposal.fromJson(Json j) => GroupProposal(
    offerId: j['offerId'] as String,
    title: j['title'] as String,
    unitLabel: j['unitLabel'] as String,
    currency: j['currency'] as String,
    regularPriceMinor: _int(j['regularPriceMinor']),
    reachedUnitPriceMinor: _intOrNull(j['reachedUnitPriceMinor']),
    endsAt: DateTime.parse(j['endsAt'] as String),
    status: j['status'] as String,
    proposedByName: j['proposedByName'] as String,
    confirmedMembers: _int(j['confirmedMembers']),
    confirmedUnits: _int(j['confirmedUnits']),
    thresholdUnits: _intOrNull(j['thresholdUnits']) ?? 0,
  );

  final String offerId;
  final String title;
  final String unitLabel;
  final String currency;
  final int regularPriceMinor;
  final int? reachedUnitPriceMinor;
  final DateTime endsAt;
  final String status;
  final String proposedByName;

  /// Membres du groupe qui ont réservé (jamais la liste de ceux qui n'ont pas répondu).
  final int confirmedMembers;
  final int confirmedUnits;
  final int thresholdUnits;
}

class PurchasesApi {
  PurchasesApi(this.client);

  final ApiClient client;

  Future<List<PickupZone>> zones() async => [
    for (final z in await client.get('/zones') as List) PickupZone.fromJson(z as Json),
  ];

  Future<List<Offer>> offers({String? zoneId}) async => [
    for (final o in await client.get('/offers', query: zoneId == null ? null : {'zoneId': zoneId}) as List)
      Offer.fromJson(o as Json),
  ];

  Future<Offer> offer(String id) async => Offer.fromJson(await client.get('/offers/$id') as Json);

  /// [offlineId] : créé une fois par réservation ; la renvoyer après une coupure ne crée pas de doublon.
  Future<PurchaseOrder> reserve({
    required String offerId,
    required int quantity,
    required String pickupName,
    required String offlineId,
  }) async => PurchaseOrder.fromJson(
    await client.post('/offers/$offerId/orders', {
      'quantity': quantity,
      'pickupName': pickupName,
      'offlineId': offlineId,
    }) as Json,
  );

  Future<List<PurchaseOrder>> myOrders() async => [
    for (final o in await client.get('/me/orders') as List) PurchaseOrder.fromJson(o as Json),
  ];

  Future<PurchaseOrder> cancelOrder(String orderId) async =>
      PurchaseOrder.fromJson(await client.post('/orders/$orderId/cancel') as Json);

  /// Propose l'offre à un de mes groupes : elle apparaît dans ses « Achats proposés ».
  Future<void> proposeToGroup(String offerId, String groupId) =>
      client.post('/offers/$offerId/shares', {'channel': 'group', 'groupId': groupId});

  /// Enregistre un partage WhatsApp (origine de l'invitation) ; renvoie le jeton du lien.
  Future<String> shareOnWhatsApp(String offerId) async {
    final res = await client.post('/offers/$offerId/shares', {'channel': 'whatsapp'}) as Json;
    return res['token'] as String;
  }

  /// La boutique ajoute une photo à une offre encore en brouillon (au plus 4).
  Future<void> uploadOfferPhoto(String merchantId, String offerId, List<int> bytes, String contentType) =>
      client.postBytes('/merchants/$merchantId/offers/$offerId/photos', bytes, contentType);

  /// La discussion sous une offre.
  Future<List<OfferMessage>> offerMessages(String offerId) async => [
    for (final m in await client.get('/offers/$offerId/messages') as List) OfferMessage.fromJson(m as Json),
  ];

  Future<void> postOfferMessage(String offerId, String body) => client.post('/offers/$offerId/messages', {'body': body});

  Future<List<GroupProposal>> groupProposals(String groupId) async => [
    for (final p in await client.get('/groups/$groupId/proposals') as List) GroupProposal.fromJson(p as Json),
  ];

  // ---------- Boutique ----------

  Future<List<Merchant>> myMerchants() async => [
    for (final m in await client.get('/me/merchants') as List) Merchant.fromJson(m as Json),
  ];

  Future<List<Offer>> merchantOffers(String merchantId) async => [
    for (final o in await client.get('/merchants/$merchantId/offers') as List) Offer.fromJson(o as Json),
  ];

  Future<Offer> createOffer(
    String merchantId, {
    required String title,
    required String unitLabel,
    required String currency,
    required int regularPriceMinor,
    required DateTime endsAt,
    required int pickupWindowHours,
    required List<OfferTier> tiers,
  }) async => Offer.fromJson(
    await client.post('/merchants/$merchantId/offers', {
      'title': title,
      'unitLabel': unitLabel,
      'currency': currency,
      'regularPriceMinor': regularPriceMinor,
      'endsAt': endsAt.toUtc().toIso8601String(),
      'pickupWindowHours': pickupWindowHours,
      'tiers': [
        for (final t in tiers) {'minQuantity': t.minQuantity, 'unitPriceMinor': t.unitPriceMinor},
      ],
    }) as Json,
  );

  Future<Offer> publishOffer(String merchantId, String offerId) async =>
      Offer.fromJson(await client.post('/merchants/$merchantId/offers/$offerId/publish') as Json);

  /// Commandes à encaisser et à remettre (prêtes et payées).
  Future<List<MerchantOrder>> merchantOrders(String merchantId) async => [
    for (final o in await client.get('/merchants/$merchantId/orders') as List) MerchantOrder.fromJson(o as Json),
  ];

  Future<MerchantOrder> confirmPayment(String merchantId, String orderId, {required String method, String? txReference}) async =>
      MerchantOrder.fromJson(
        await client.post('/merchants/$merchantId/orders/$orderId/confirm-payment', {
          'method': method,
          'txReference': ?txReference,
        }) as Json,
      );

  Future<MerchantOrder> confirmPickup(String merchantId, String orderId, String pickupCode) async =>
      MerchantOrder.fromJson(
        await client.post('/merchants/$merchantId/orders/$orderId/confirm-pickup', {'pickupCode': pickupCode}) as Json,
      );
}

/// Commande vue par la boutique : le code et le nom de retrait servent au comptoir.
class MerchantOrder {
  MerchantOrder({
    required this.id,
    required this.title,
    required this.quantity,
    required this.unitLabel,
    required this.pickupName,
    required this.status,
    required this.currency,
    required this.amountDueMinor,
    required this.paymentStatus,
    required this.pickupCode,
  });

  factory MerchantOrder.fromJson(Json j) => MerchantOrder(
    id: j['id'] as String,
    title: j['title'] as String,
    quantity: _int(j['quantity']),
    unitLabel: j['unitLabel'] as String,
    pickupName: j['pickupName'] as String,
    status: j['status'] as String,
    currency: j['currency'] as String,
    amountDueMinor: _intOrNull(j['amountDueMinor']) ?? 0,
    paymentStatus: j['paymentStatus'] as String?,
    pickupCode: j['pickupCode'] as String? ?? '',
  );

  final String id;
  final String title;
  final int quantity;
  final String unitLabel;
  final String pickupName;
  final String status;
  final String currency;
  final int amountDueMinor;
  final String? paymentStatus;
  final String pickupCode;
}

/// Un message sous une offre : question d'un membre ou réponse de la boutique.
class OfferMessage {
  OfferMessage.fromJson(Json j)
    : id = j['id'] as String,
      authorName = j['authorName'] as String,
      fromMerchant = j['fromMerchant'] as bool,
      mine = j['mine'] as bool,
      body = j['body'] as String,
      createdAt = DateTime.parse(j['createdAt'] as String);

  final String id;
  final String authorName;
  final bool fromMerchant;
  final bool mine;
  final String body;
  final DateTime createdAt;
}
