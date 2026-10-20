import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'audit_event.dart';

const formatVersion = 'mchango-v1';

/// `prev_hash` du premier événement de chaque chaîne.
final genesisPrevHash = '0' * 64;

/// Recalcule le hash d'un événement selon spec/audit-hash.md.
String computeHash(AuditEvent e) {
  final fields = [
    formatVersion,
    e.chainId,
    e.seq.toString(),
    e.prevHash,
    e.actorType,
    e.actorId ?? '',
    e.deviceId ?? '',
    e.action,
    e.createdAt,
    e.payload,
    e.signature ?? '',
  ];
  return sha256.convert(utf8.encode(fields.join('\n'))).toString();
}

/// Dernier point vérifié d'une chaîne, à mémoriser sur le téléphone.
class ChainHead {
  const ChainHead({required this.seq, required this.hash});

  /// Avant tout événement.
  static final genesis = ChainHead(seq: 0, hash: genesisPrevHash);

  final int seq;
  final String hash;

  @override
  bool operator ==(Object other) =>
      other is ChainHead && other.seq == seq && other.hash == hash;

  @override
  int get hashCode => Object.hash(seq, hash);
}

enum ChainFailure {
  /// L'événement n'appartient pas à la chaîne vérifiée.
  wrongChain,

  /// Numéro manquant, en double ou dans le désordre.
  seqGap,

  /// Le lien avec l'événement précédent est rompu.
  prevHashMismatch,

  /// Le contenu ne correspond plus à son hash.
  hashMismatch,
}

class ChainVerification {
  const ChainVerification._(this.head, this.firstInvalidSeq, this.failure);

  /// Dernier événement valide (ou le point de départ si aucun ne l'est).
  final ChainHead head;

  /// Premier seq invalide ; null si tout est intact.
  final int? firstInvalidSeq;
  final ChainFailure? failure;

  bool get isValid => firstInvalidSeq == null;
}

/// Vérifie [events] (triés par seq) à partir de [from].
///
/// Pour une synchronisation incrémentale, passer en [from] la dernière tête
/// mémorisée et seulement les événements reçus depuis.
ChainVerification verifyChain(
  String chainId,
  List<AuditEvent> events, {
  ChainHead? from,
}) {
  var head = from ?? ChainHead.genesis;
  for (final e in events) {
    final expectedSeq = head.seq + 1;
    final failure = e.chainId != chainId
        ? ChainFailure.wrongChain
        : e.seq != expectedSeq
            ? ChainFailure.seqGap
            : e.prevHash != head.hash
                ? ChainFailure.prevHashMismatch
                : computeHash(e) != e.hash
                    ? ChainFailure.hashMismatch
                    : null;
    if (failure != null) {
      return ChainVerification._(head, expectedSeq, failure);
    }
    head = ChainHead(seq: e.seq, hash: e.hash);
  }
  return ChainVerification._(head, null, null);
}

/// Vrai si le serveur présente, pour un seq déjà vérifié, un hash différent
/// de celui mémorisé : l'historique a été réécrit.
bool isRewrite(ChainHead known, AuditEvent served) =>
    served.seq == known.seq && served.hash != known.hash;
