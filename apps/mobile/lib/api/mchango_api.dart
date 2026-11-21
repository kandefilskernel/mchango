import 'api_client.dart';
import 'models.dart';

/// Appels typés vers l'API (contrats : spec/groups.md, spec/cycles.md, spec/receipts.md).
class MchangoApi {
  MchangoApi(this.client);

  final ApiClient client;

  Future<List<Group>> myGroups() async => [
    for (final g in await client.get('/groups') as List) Group.fromJson(g as Json),
  ];

  /// Mon carnet : versé, reçu, prochains paiements et mon tour, toutes tontines confondues.
  Future<Carnet> carnet() async => Carnet.fromJson(await client.get('/me/carnet') as Json);

  /// Langue des SMS envoyés à ce membre (rappels).
  Future<void> setLanguage(String code) => client.put('/me/language', {'language': code});

  /// Avis du membre, sur Mchango ou sur une de ses tontines (lu par l'équipe).
  Future<void> sendFeedback({required String body, String? groupId, int? rating}) => client.post('/feedback', {
    'body': body,
    'groupId': ?groupId,
    'rating': ?rating,
  });

  Future<Group> group(String id) async => Group.fromJson(await client.get('/groups/$id') as Json);

  Future<Group> createGroup({
    required String name,
    required String currency,
    required int contributionAmountMinor,
    required String frequency,
    required String startDate,
    required int maxMembers,
    String category = 'community',
    int? payday,
    String? paydayShift,
  }) async => Group.fromJson(
    await client.post('/groups', {
      'name': name,
      'category': category,
      'payday': ?payday,
      'paydayShift': ?paydayShift,
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

  /// Signe le règlement affiché (son empreinte). Refusé s'il a changé entre-temps.
  Future<GroupTerms> signTerms(String groupId, String termsHash) async =>
      GroupTerms.fromJson(await client.post('/groups/$groupId/sign', {'termsHash': termsHash}) as Json);

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
    Map<String, Object>? smsCheck,
  }) async => Contribution.fromJson(
    await client.post('/groups/$groupId/cycles/$cycleNumber/contributions', {
      'method': method,
      'amountMinor': amountMinor,
      'offlineId': offlineId,
      'txReference': ?txReference,
      'witnessMembershipId': ?witnessMembershipId,
      'smsCheck': ?smsCheck,
    }) as Json,
  );

  /// [riskAcknowledged] : déclaration orange ou rouge, solde vérifié.
  /// [receivedTxReference] : déclaration rouge, ID lu dans le SMS de l'argent reçu.
  Future<Contribution> decide(
    String contributionId,
    String decision, {
    String? note,
    bool? riskAcknowledged,
    String? receivedTxReference,
  }) async => Contribution.fromJson(
    await client.post('/contributions/$contributionId/decisions', {
      'decision': decision,
      'note': ?note,
      'riskAcknowledged': ?riskAcknowledged,
      'receivedTxReference': ?receivedTxReference,
    }) as Json,
  );

  Future<Receipt> receipt(String contributionId) async =>
      Receipt.fromJson(await client.get('/contributions/$contributionId/receipt') as Json);

  /// Demandes de nouveau PIN que je peux confirmer en tant que garant.
  Future<List<PinResetRequest>> pendingPinResets() async => [
    for (final r in await client.get('/pin-resets/pending') as List) PinResetRequest.fromJson(r as Json),
  ];

  Future<void> approvePinReset(String requestId) => client.post('/pin-resets/$requestId/approve');

  Future<void> rejectPinReset(String requestId) => client.post('/pin-resets/$requestId/reject');

  /// Échanges de tour du groupe, les plus récents d'abord (spec/swaps.md).
  Future<List<TurnSwap>> swaps(String groupId) async => [
    for (final s in await client.get('/groups/$groupId/swaps') as List) TurnSwap.fromJson(s as Json),
  ];

  Future<TurnSwap> requestSwap(String groupId, String targetMembershipId, {String? reason}) async =>
      TurnSwap.fromJson(
        await client.post('/groups/$groupId/swaps', {'targetMembershipId': targetMembershipId, 'reason': ?reason})
            as Json,
      );

  /// [decision] : accept, decline (le membre sollicité) ou cancel (le demandeur).
  Future<TurnSwap> decideSwap(String swapId, String decision) async =>
      TurnSwap.fromJson(await client.post('/swaps/$swapId/$decision') as Json);

  /// Mon objectif d'épargne dans une tontine, ou null (spec/goals.md).
  Future<SavingsGoal?> goal(String groupId) async {
    final g = (await client.get('/groups/$groupId/goal') as Json)['goal'];
    return g == null ? null : SavingsGoal.fromJson(g as Json);
  }

  Future<void> setGoal(String groupId, SavingsGoal goal) => client.put('/groups/$groupId/goal', {
    'kind': goal.kind,
    'label': goal.label,
    'targetAmountMinor': goal.targetAmountMinor,
    'targetDate': goal.targetDate,
    'sharedWithGroup': goal.sharedWithGroup,
  });

  Future<void> removeGoal(String groupId) => client.delete('/groups/$groupId/goal');

  /// Ce qui entrerait dans une attestation émise maintenant.
  Future<AttestationStats> attestationStats() async =>
      AttestationStats.fromJson(await client.get('/me/attestation-stats') as Json);

  Future<List<Attestation>> myAttestations() async => [
    for (final a in await client.get('/me/attestations') as List) Attestation.fromJson(a as Json),
  ];

  Future<Attestation> issueAttestation({required bool includeAmounts}) async =>
      Attestation.fromJson(await client.post('/me/attestations', {'includeAmounts': includeAmounts}) as Json);

  Future<void> revokeAttestation(String id) => client.post('/me/attestations/$id/revoke');

  /// Travailleurs : les chaînes privées des cotisations que je peux lire (vide pour les autres tontines).
  Future<List<PrivateChain>> privateHistory(String groupId) async => [
    for (final c in (await client.get('/groups/$groupId/private-history') as Json)['chains'] as List)
      PrivateChain.fromJson(c as Json),
  ];

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
