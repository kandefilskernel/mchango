import 'package:mchango_audit/mchango_audit.dart';

typedef Json = Map<String, dynamic>;

class Member {
  Member({
    required this.membershipId,
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.role,
    required this.turnOrder,
  });

  factory Member.fromJson(Json j) => Member(
    membershipId: j['membershipId'] as String,
    userId: j['userId'] as String,
    fullName: j['fullName'] as String,
    phone: j['phone'] as String,
    role: j['role'] as String,
    turnOrder: j['turnOrder'] as int?,
  );

  final String membershipId;
  final String userId;
  final String fullName;
  final String phone;
  final String role;
  final int? turnOrder;
}

class Group {
  Group({
    required this.id,
    required this.name,
    required this.currency,
    required this.contributionAmountMinor,
    required this.frequency,
    required this.startDate,
    required this.status,
    required this.maxMembers,
    required this.turnOrderMode,
    required this.drawSeed,
    required this.myRole,
    required this.memberCount,
    required this.members,
    this.terms,
    this.category = 'community',
    this.payday,
    this.paydayShift,
  });

  factory Group.fromJson(Json j) => Group(
    id: j['id'] as String,
    name: j['name'] as String,
    currency: j['currency'] as String,
    contributionAmountMinor: j['contributionAmountMinor'] as int,
    frequency: j['frequency'] as String,
    startDate: j['startDate'] as String,
    status: j['status'] as String,
    maxMembers: j['maxMembers'] as int,
    turnOrderMode: j['turnOrderMode'] as String?,
    drawSeed: j['drawSeed'] as String?,
    myRole: j['myRole'] as String? ?? 'member',
    memberCount: j['memberCount'] as int? ?? 0,
    members: [for (final m in (j['members'] as List? ?? const [])) Member.fromJson(m as Json)],
    terms: j['terms'] == null ? null : GroupTerms.fromJson(j['terms'] as Json),
    // Absente d'une ancienne réponse : « communautaire » (la tontine d'avant les catégories)
    category: j['category'] as String? ?? 'community',
    payday: j['payday'] as int?,
    paydayShift: j['paydayShift'] as String?,
  );

  final String id;
  final String name;
  final String category;
  final String currency;
  final int contributionAmountMinor;
  final String frequency;
  final String startDate;
  final String status;
  final int maxMembers;
  final String? turnOrderMode;
  final String? drawSeed;
  final String myRole;
  final int memberCount;
  final List<Member> members;

  /// Signatures du règlement, tant que le groupe est en préparation (null ensuite).
  final GroupTerms? terms;

  /// Travailleurs : jour de paie (1 à 31) ; l'échéance est avancée (before) ou reportée (after)
  /// si elle tombe un dimanche ou un jour férié. null pour les autres tontines.
  final int? payday;
  final String? paydayShift;

  bool get isPresident => myRole == 'president';
  bool get isDraft => status == 'draft';
  bool get hasCompleteOrder => members.length >= 2 && members.every((m) => m.turnOrder != null);
}

class GroupPreview {
  GroupPreview.fromJson(Json j)
    : name = j['name'] as String,
      currency = j['currency'] as String,
      contributionAmountMinor = j['contributionAmountMinor'] as int,
      frequency = j['frequency'] as String,
      startDate = j['startDate'] as String,
      memberCount = j['memberCount'] as int,
      maxMembers = j['maxMembers'] as int,
      presidentName = j['presidentName'] as String?;

  final String name;
  final String currency;
  final int contributionAmountMinor;
  final String frequency;
  final String startDate;
  final int memberCount;
  final int maxMembers;
  final String? presidentName;
}

class Invitation {
  Invitation.fromJson(Json j)
    : code = j['code'] as String,
      expiresAt = DateTime.parse(j['expiresAt'] as String),
      shareText = j['shareText'] as String;

  final String code;
  final DateTime expiresAt;
  final String shareText;
}

class TurnOrderEntry {
  TurnOrderEntry.fromJson(Json j)
    : turn = j['turn'] as int,
      membershipId = j['membershipId'] as String,
      fullName = j['fullName'] as String;

  final int turn;
  final String membershipId;
  final String fullName;
}

class DrawResult {
  DrawResult.fromJson(Json j)
    : seed = j['seed'] as String,
      order = [for (final o in j['order'] as List) TurnOrderEntry.fromJson(o as Json)];

  final String seed;
  final List<TurnOrderEntry> order;
}

class CycleSummary {
  CycleSummary.fromJson(Json j)
    : cycleNumber = j['cycleNumber'] as int,
      dueDate = j['dueDate'] as String,
      status = j['status'] as String,
      beneficiaryMembershipId = (j['beneficiary'] as Json)['membershipId'] as String,
      beneficiaryName = (j['beneficiary'] as Json)['fullName'] as String,
      beneficiaryGoal = (j['beneficiary'] as Json)['goal'] == null
          ? null
          : SharedGoal.fromJson((j['beneficiary'] as Json)['goal'] as Json),
      confirmedCount = j['confirmedCount'] as int,
      // Absent d'une ancienne réponse : on retombe sur les confirmés
      declaredCount = j['declaredCount'] as int? ?? j['confirmedCount'] as int,
      expectedCount = j['expectedCount'] as int;

  final int cycleNumber;
  final String dueDate;
  final String status;
  final String beneficiaryMembershipId;
  final String beneficiaryName;

  /// Objectif du bénéficiaire, s'il a choisi de le montrer au groupe.
  final SharedGoal? beneficiaryGoal;
  final int confirmedCount;

  /// Paiements déclarés, confirmés ou non. Dès le premier, le tour ne s'échange plus.
  final int declaredCount;
  final int expectedCount;
}

class Board {
  Board.fromJson(Json j)
    : myMembershipId = j['myMembershipId'] as String,
      cycles = [for (final c in j['cycles'] as List) CycleSummary.fromJson(c as Json)];

  final String myMembershipId;
  final List<CycleSummary> cycles;
}

class Contribution {
  Contribution.fromJson(Json j)
    : id = j['id'] as String,
      payerMembershipId = j['payerMembershipId'] as String,
      receiverMembershipId = j['receiverMembershipId'] as String,
      witnessMembershipId = j['witnessMembershipId'] as String?,
      amountMinor = j['amountMinor'] as int,
      method = j['method'] as String,
      txReference = j['txReference'] as String?,
      status = j['status'] as String,
      isLate = j['isLate'] as bool,
      cycleStatus = j['cycleStatus'] as String?,
      risk = j['risk'] == null ? null : ContributionRisk.fromJson(j['risk'] as Json);

  final String id;
  final String payerMembershipId;
  final String receiverMembershipId;
  final String? witnessMembershipId;
  final int amountMinor;
  final String method;
  final String? txReference;
  final String status;
  final bool isLate;

  /// Renseigné après une confirmation : `completed` si le tour vient de se clore.
  final String? cycleStatus;

  /// Score de risque de la déclaration : visible du bénéficiaire et du témoin seulement.
  final ContributionRisk? risk;
}

/// Vert : rien d'inhabituel. Orange : vérifier son solde avant de confirmer.
/// Rouge : confirmer seulement avec le SMS de l'argent reçu.
class ContributionRisk {
  ContributionRisk.fromJson(Json j)
    : level = j['level'] as String,
      reasons = [for (final r in j['reasons'] as List) r as String];

  final String level;
  final List<String> reasons;
}

class Decision {
  Decision.fromJson(Json j) : decision = j['decision'] as String, membershipId = j['membershipId'] as String;

  final String decision;
  final String membershipId;
}

class PayerRow {
  PayerRow.fromJson(Json j)
    : membershipId = j['membershipId'] as String,
      fullName = j['fullName'] as String,
      status = j['status'] as String,
      contribution = j['contribution'] == null ? null : Contribution.fromJson(j['contribution'] as Json),
      decisions = [for (final d in j['decisions'] as List) Decision.fromJson(d as Json)];

  final String membershipId;
  final String fullName;

  /// expected, late, declared, disputed, confirmed
  final String status;
  final Contribution? contribution;
  final List<Decision> decisions;

  bool hasDecision(String membershipId, String decision) =>
      decisions.any((d) => d.membershipId == membershipId && d.decision == decision);
}

class CycleDetail {
  CycleDetail.fromJson(Json j)
    : myMembershipId = j['myMembershipId'] as String,
      cycleNumber = j['cycleNumber'] as int,
      dueDate = j['dueDate'] as String,
      status = j['status'] as String,
      beneficiaryMembershipId = j['beneficiaryMembershipId'] as String,
      privateStatuses = j['privateStatuses'] as bool? ?? false,
      payers = [for (final p in j['payers'] as List) PayerRow.fromJson(p as Json)];

  final String myMembershipId;
  final int cycleNumber;
  final String dueDate;
  final String status;
  final String beneficiaryMembershipId;

  /// Travailleurs : l'état des cotisations des collègues est masqué (statut « private »).
  final bool privateStatuses;
  final List<PayerRow> payers;

  bool get iAmBeneficiary => myMembershipId == beneficiaryMembershipId;
  PayerRow? get myRow {
    for (final p in payers) {
      if (p.membershipId == myMembershipId) return p;
    }
    return null;
  }
}

class Receipt {
  Receipt.fromJson(Json j)
    : receiptNumber = j['receiptNumber'] as String,
      groupName = j['groupName'] as String,
      cycleNumber = j['cycleNumber'] as int,
      currency = j['currency'] as String,
      amountMinor = j['amountMinor'] as int,
      method = j['method'] as String,
      txReference = j['txReference'] as String?,
      isLate = j['isLate'] as bool,
      payerName = (j['payer'] as Json)['fullName'] as String,
      beneficiaryName = (j['beneficiary'] as Json)['fullName'] as String,
      witnessName = (j['witness'] as Json?)?['fullName'] as String?,
      declaredAt = DateTime.parse(j['declaredAt'] as String),
      confirmedAt = DateTime.parse(j['confirmedAt'] as String),
      auditSeq = (j['audit'] as Json)['seq'] as int,
      auditHash = (j['audit'] as Json)['hash'] as String,
      qrPayload = j['qrPayload'] as String;

  final String receiptNumber;
  final String groupName;
  final int cycleNumber;
  final String currency;
  final int amountMinor;
  final String method;
  final String? txReference;
  final bool isLate;
  final String payerName;
  final String beneficiaryName;
  final String? witnessName;
  final DateTime declaredAt;
  final DateTime confirmedAt;
  final int auditSeq;
  final String auditHash;
  final String qrPayload;
}

/// Demande de nouveau PIN qu'un garant peut confirmer.
class PinResetRequest {
  PinResetRequest.fromJson(Json j)
    : requestId = j['requestId'] as String,
      fullName = j['fullName'] as String,
      phone = j['phone'] as String,
      groupName = j['groupName'] as String,
      createdAt = DateTime.parse(j['createdAt'] as String);

  final String requestId;
  final String fullName;
  final String phone;
  final String groupName;
  final DateTime createdAt;
}

/// Un événement du journal : la partie hachée (vérifiable) et le nom de l'auteur (affichage).
class HistoryEvent {
  HistoryEvent.fromJson(Json j) : audit = AuditEvent.fromJson(j), actorName = j['actor_name'] as String?;

  final AuditEvent audit;
  final String? actorName;
}

/// Carnet personnel (GET /me/carnet) : montants constatés, pas un solde.
class Carnet {
  Carnet({required this.totals, required this.upcoming, required this.groups});

  factory Carnet.fromJson(Json j) => Carnet(
    totals: [for (final t in j['totals'] as List) CarnetTotal.fromJson(t as Json)],
    upcoming: [for (final u in j['upcoming'] as List) CarnetStep.fromJson(u as Json)],
    groups: [for (final g in j['groups'] as List) CarnetGroup.fromJson(g as Json)],
  );

  final List<CarnetTotal> totals;
  final List<CarnetStep> upcoming;
  final List<CarnetGroup> groups;
}

class CarnetTotal {
  CarnetTotal({required this.currency, required this.paidMinor, required this.receivedMinor});

  factory CarnetTotal.fromJson(Json j) => CarnetTotal(
    currency: j['currency'] as String,
    paidMinor: j['paidMinor'] as int,
    receivedMinor: j['receivedMinor'] as int,
  );

  final String currency;
  final int paidMinor;
  final int receivedMinor;
}

/// Prochaine étape : un paiement à faire (pay) ou mon tour de recevoir (receive).
class CarnetStep {
  CarnetStep({
    required this.kind,
    required this.groupId,
    required this.groupName,
    required this.cycleNumber,
    required this.dueDate,
    required this.amountMinor,
    required this.currency,
    required this.counterpart,
    required this.late,
  });

  factory CarnetStep.fromJson(Json j) => CarnetStep(
    kind: j['kind'] as String,
    groupId: j['groupId'] as String,
    groupName: j['groupName'] as String,
    cycleNumber: j['cycleNumber'] as int,
    dueDate: j['dueDate'] as String,
    amountMinor: j['amountMinor'] as int,
    currency: j['currency'] as String,
    counterpart: j['counterpart'] as String?,
    late: j['late'] as bool,
  );

  final String kind;
  final String groupId;
  final String groupName;
  final int cycleNumber;
  final String dueDate;
  final int amountMinor;
  final String currency;
  final String? counterpart;
  final bool late;

  bool get isPayment => kind == 'pay';
}

class CarnetGroup {
  CarnetGroup({
    required this.groupId,
    required this.name,
    required this.status,
    required this.currency,
    required this.contributionAmountMinor,
    required this.myTurnCycle,
    required this.myTurnDate,
    required this.myTurnStatus,
    required this.paidCount,
    required this.paidMinor,
    required this.receivedCount,
    required this.receivedMinor,
    required this.pendingCount,
    this.goal,
  });

  factory CarnetGroup.fromJson(Json j) {
    final turn = j['myTurn'] as Json?;
    return CarnetGroup(
      groupId: j['groupId'] as String,
      name: j['name'] as String,
      status: j['status'] as String,
      currency: j['currency'] as String,
      contributionAmountMinor: j['contributionAmountMinor'] as int,
      myTurnCycle: turn?['cycleNumber'] as int?,
      myTurnDate: turn?['dueDate'] as String?,
      myTurnStatus: turn?['status'] as String?,
      paidCount: j['paidCount'] as int,
      paidMinor: j['paidMinor'] as int,
      receivedCount: j['receivedCount'] as int,
      receivedMinor: j['receivedMinor'] as int,
      pendingCount: j['pendingCount'] as int,
      goal: j['goal'] == null ? null : GoalProgress.fromJson(j['goal'] as Json),
    );
  }

  final String groupId;
  final String name;
  final String status;
  final String currency;
  final int contributionAmountMinor;
  final int? myTurnCycle;
  final String? myTurnDate;
  final String? myTurnStatus;
  final int paidCount;
  final int paidMinor;
  final int receivedCount;
  final int receivedMinor;
  final int pendingCount;

  /// Mon objectif d'épargne dans cette tontine et sa progression.
  final GoalProgress? goal;
}

/// Le règlement que chaque membre signe avant le démarrage (montant, date, ordre des tours).
class GroupTerms {
  GroupTerms({required this.hash, required this.ready, required this.signedBy, required this.missing, required this.allSigned});

  factory GroupTerms.fromJson(Json j) => GroupTerms(
    hash: j['hash'] as String,
    ready: j['ready'] as bool,
    signedBy: [for (final m in j['signedBy'] as List) m as String],
    missing: [for (final m in j['missing'] as List) (m as Json)['fullName'] as String],
    allSigned: j['allSigned'] as bool,
  );

  /// Empreinte du règlement : signer, c'est approuver exactement ce règlement-là.
  final String hash;

  /// Ordre des tours fixé pour tous : le règlement peut être signé.
  final bool ready;
  final List<String> signedBy;

  /// Noms des membres qui n'ont pas encore signé.
  final List<String> missing;
  final bool allSigned;
}

/// Objectif montré au groupe par un bénéficiaire (tableau des tours).
class SharedGoal {
  SharedGoal.fromJson(Json j) : kind = j['kind'] as String, label = j['label'] as String;

  final String kind;
  final String label;
}

/// Mon objectif d'épargne dans une tontine (spec/goals.md).
class SavingsGoal {
  SavingsGoal({
    required this.kind,
    required this.label,
    this.targetAmountMinor,
    this.targetDate,
    this.sharedWithGroup = false,
  });

  factory SavingsGoal.fromJson(Json j) => SavingsGoal(
    kind: j['kind'] as String,
    label: j['label'] as String,
    targetAmountMinor: j['targetAmountMinor'] as int?,
    targetDate: j['targetDate'] as String?,
    sharedWithGroup: j['sharedWithGroup'] as bool? ?? false,
  );

  final String kind;
  final String label;
  final int? targetAmountMinor;
  final String? targetDate;
  final bool sharedWithGroup;
}

/// Objectif et progression (carnet) : la mise reçue par rapport au montant visé.
class GoalProgress extends SavingsGoal {
  GoalProgress.fromJson(Json j)
    : effectiveTargetMinor = j['effectiveTargetMinor'] as int,
      progressMinor = j['progressMinor'] as int,
      progressPercent = j['progressPercent'] as int,
      reached = j['reached'] as bool,
      super(
        kind: j['kind'] as String,
        label: j['label'] as String,
        targetAmountMinor: j['targetAmountMinor'] as int?,
        targetDate: j['targetDate'] as String?,
        sharedWithGroup: j['sharedWithGroup'] as bool? ?? false,
      );

  final int effectiveTargetMinor;
  final int progressMinor;
  final int progressPercent;
  final bool reached;
}

/// Demande d'échange de tour entre deux membres (spec/swaps.md).
class TurnSwap {
  TurnSwap.fromJson(Json j)
    : id = j['id'] as String,
      requesterMembershipId = (j['requester'] as Json)['membershipId'] as String,
      requesterName = (j['requester'] as Json)['fullName'] as String? ?? '',
      targetMembershipId = (j['target'] as Json)['membershipId'] as String,
      targetName = (j['target'] as Json)['fullName'] as String? ?? '',
      requesterCycleNumber = j['requesterCycleNumber'] as int,
      targetCycleNumber = j['targetCycleNumber'] as int,
      reason = j['reason'] as String?,
      status = j['status'] as String,
      expiresAt = DateTime.parse(j['expiresAt'] as String);

  final String id;
  final String requesterMembershipId;
  final String requesterName;
  final String targetMembershipId;
  final String targetName;
  final int requesterCycleNumber;
  final int targetCycleNumber;
  final String? reason;

  /// pending, accepted, declined, cancelled, expired
  final String status;
  final DateTime expiresAt;

  bool get isPending => status == 'pending';
}

/// Chiffres d'une attestation de régularité (GET /me/attestation-stats, ou contenu figé).
class AttestationStats {
  AttestationStats.fromJson(Json j)
    : memberSince = j['memberSince'] as String,
      tontinesJoined = (j['tontines'] as Json)['joined'] as int,
      tontinesCompleted = (j['tontines'] as Json)['completed'] as int,
      confirmed = (j['contributions'] as Json)['confirmed'] as int,
      onTime = (j['contributions'] as Json)['onTime'] as int,
      late = (j['contributions'] as Json)['late'] as int,
      rejected = (j['contributions'] as Json)['rejected'] as int,
      onTimeRatePercent = j['onTimeRatePercent'] as int?,
      turnsReceived = j['turnsReceived'] as int;

  final String memberSince;
  final int tontinesJoined;
  final int tontinesCompleted;
  final int confirmed;
  final int onTime;
  final int late;
  final int rejected;
  final int? onTimeRatePercent;
  final int turnsReceived;
}

/// Attestation émise : contenu figé, code de vérification, QR (spec/attestations.md).
class Attestation {
  Attestation.fromJson(Json j)
    : id = j['id'] as String,
      code = j['code'] as String,
      status = j['status'] as String,
      holderName = ((j['content'] as Json)['holder'] as Json)['fullName'] as String,
      stats = AttestationStats.fromJson(j['content'] as Json),
      contentHash = j['contentHash'] as String,
      qrPayload = j['qrPayload'] as String,
      issuedAt = DateTime.parse(j['issuedAt'] as String),
      expiresAt = DateTime.parse(j['expiresAt'] as String);

  final String id;
  final String code;

  /// valid, expired, revoked
  final String status;
  final String holderName;
  final AttestationStats stats;
  final String contentHash;
  final String qrPayload;
  final DateTime issuedAt;
  final DateTime expiresAt;

  /// « K7MPQ2XWAB » → « K7MPQ-2XWAB » : plus facile à dicter.
  String get displayCode => '${code.substring(0, 5)}-${code.substring(5)}';
}

/// Travailleurs : chaîne privée d'une cotisation (un payeur, un tour), lisible seulement par le
/// payeur, le bénéficiaire, le témoin et le président (db/024_private_slot_chains.sql).
class PrivateChain {
  PrivateChain.fromJson(Json j)
    : chainId = j['chainId'] as String,
      cycleNumber = j['cycleNumber'] as int,
      payerName = (j['payer'] as Json)['fullName'] as String,
      events = [for (final e in j['events'] as List) HistoryEvent.fromJson(e as Json)];

  final String chainId;
  final int cycleNumber;
  final String payerName;
  final List<HistoryEvent> events;
}
