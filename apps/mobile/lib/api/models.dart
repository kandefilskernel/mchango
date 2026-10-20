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
        members: [
          for (final m in (j['members'] as List? ?? const [])) Member.fromJson(m as Json),
        ],
      );

  final String id;
  final String name;
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

  bool get isPresident => myRole == 'president';
  bool get isDraft => status == 'draft';
  bool get hasCompleteOrder =>
      members.length >= 2 && members.every((m) => m.turnOrder != null);
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
        confirmedCount = j['confirmedCount'] as int,
        expectedCount = j['expectedCount'] as int;

  final int cycleNumber;
  final String dueDate;
  final String status;
  final String beneficiaryMembershipId;
  final String beneficiaryName;
  final int confirmedCount;
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
        cycleStatus = j['cycleStatus'] as String?;

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
}

class Decision {
  Decision.fromJson(Json j)
      : decision = j['decision'] as String,
        membershipId = j['membershipId'] as String;

  final String decision;
  final String membershipId;
}

class PayerRow {
  PayerRow.fromJson(Json j)
      : membershipId = j['membershipId'] as String,
        fullName = j['fullName'] as String,
        status = j['status'] as String,
        contribution = j['contribution'] == null
            ? null
            : Contribution.fromJson(j['contribution'] as Json),
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
        payers = [for (final p in j['payers'] as List) PayerRow.fromJson(p as Json)];

  final String myMembershipId;
  final int cycleNumber;
  final String dueDate;
  final String status;
  final String beneficiaryMembershipId;
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

/// Un événement du journal : la partie hachée (vérifiable) et le nom de l'auteur (affichage).
class HistoryEvent {
  HistoryEvent.fromJson(Json j)
      : audit = AuditEvent.fromJson(j),
        actorName = j['actor_name'] as String?;

  final AuditEvent audit;
  final String? actorName;
}
