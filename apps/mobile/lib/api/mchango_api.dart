import 'api_client.dart';
import 'models.dart';

/// Appels typés vers l'API (contrats : spec/groups.md, spec/cycles.md, spec/receipts.md).
class MchangoApi {
  MchangoApi(this.client);

  final ApiClient client;

  Future<List<Group>> myGroups() async => [
    for (final g in await client.get('/groups') as List) Group.fromJson(g as Json),
  ];

  Future<Group> group(String id) async => Group.fromJson(await client.get('/groups/$id') as Json);

  Future<Group> createGroup({
    required String name,
    required String currency,
    required int contributionAmountMinor,
    required String frequency,
    required String startDate,
    required int maxMembers,
  }) async => Group.fromJson(
    await client.post('/groups', {
      'name': name,
      'currency': currency,
      'contributionAmountMinor': contributionAmountMinor,
      'frequency': frequency,
      'startDate': startDate,
      'maxMembers': maxMembers,
    }) as Json,
  );

  Future<Invitation> createInvitation(String groupId) async =>
      Invitation.fromJson(await client.post('/groups/$groupId/invitations') as Json);

  Future<GroupPreview> preview(String code) async =>
      GroupPreview.fromJson(await client.post('/groups/preview', {'code': code}) as Json);

  Future<String> join(String code) async {
    final res = await client.post('/groups/join', {'code': code, 'acceptRules': true}) as Json;
    return res['groupId'] as String;
  }

  Future<void> setChosenOrder(String groupId, List<String> membershipIds) =>
      client.put('/groups/$groupId/turn-order', {'membershipIds': membershipIds});

  Future<DrawResult> draw(String groupId) async =>
      DrawResult.fromJson(await client.post('/groups/$groupId/turn-order/draw') as Json);

  Future<void> start(String groupId) => client.post('/groups/$groupId/start');

  Future<Board> board(String groupId) async => Board.fromJson(await client.get('/groups/$groupId/cycles') as Json);

  Future<CycleDetail> cycle(String groupId, int number) async =>
      CycleDetail.fromJson(await client.get('/groups/$groupId/cycles/$number') as Json);

  Future<Contribution> declare({
    required String groupId,
    required int cycleNumber,
    required String method,
    required int amountMinor,
    required String offlineId,
    String? txReference,
    String? witnessMembershipId,
  }) async => Contribution.fromJson(
    await client.post('/groups/$groupId/cycles/$cycleNumber/contributions', {
      'method': method,
      'amountMinor': amountMinor,
      'offlineId': offlineId,
      'txReference': ?txReference,
      'witnessMembershipId': ?witnessMembershipId,
    }) as Json,
  );

  Future<Contribution> decide(String contributionId, String decision, {String? note}) async => Contribution.fromJson(
    await client.post('/contributions/$contributionId/decisions', {'decision': decision, 'note': ?note}) as Json,
  );

  Future<Receipt> receipt(String contributionId) async =>
      Receipt.fromJson(await client.get('/contributions/$contributionId/receipt') as Json);

  /// Demandes de nouveau PIN que je peux confirmer en tant que garant.
  Future<List<PinResetRequest>> pendingPinResets() async => [
    for (final r in await client.get('/pin-resets/pending') as List) PinResetRequest.fromJson(r as Json),
  ];

  Future<void> approvePinReset(String requestId) => client.post('/pin-resets/$requestId/approve');

  Future<void> rejectPinReset(String requestId) => client.post('/pin-resets/$requestId/reject');

  /// Tout l'historique du groupe, page par page.
  Future<List<HistoryEvent>> history(String groupId) async {
    final events = <HistoryEvent>[];
    while (true) {
      final page = await client.get(
        '/groups/$groupId/history',
        query: {'afterSeq': '${events.isEmpty ? 0 : events.last.audit.seq}'},
      ) as Json;
      final batch = [for (final e in page['events'] as List) HistoryEvent.fromJson(e as Json)];
      events.addAll(batch);
      if (batch.length < 500) return events;
    }
  }
}
