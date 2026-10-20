/// Un événement du journal d'audit, tel que renvoyé par l'API.
///
/// [createdAt] et [payload] restent des chaînes : ils sont hachés octet pour
/// octet et ne doivent jamais être reparsés ni reformatés (voir spec/audit-hash.md).
class AuditEvent {
  const AuditEvent({
    required this.chainId,
    required this.seq,
    required this.prevHash,
    required this.actorType,
    required this.actorId,
    required this.deviceId,
    required this.action,
    required this.createdAt,
    required this.payload,
    required this.signature,
    required this.hash,
  });

  factory AuditEvent.fromJson(Map<String, dynamic> json) => AuditEvent(
        chainId: json['chain_id'] as String,
        seq: json['seq'] as int,
        prevHash: json['prev_hash'] as String,
        actorType: json['actor_type'] as String,
        actorId: json['actor_id'] as String?,
        deviceId: json['device_id'] as String?,
        action: json['action'] as String,
        createdAt: json['created_at'] as String,
        payload: json['payload'] as String,
        signature: json['signature'] as String?,
        hash: json['hash'] as String,
      );

  final String chainId;
  final int seq;
  final String prevHash;

  /// `user`, `staff` ou `system`.
  final String actorType;
  final String? actorId;
  final String? deviceId;
  final String action;

  /// UTC, format exact `YYYY-MM-DDTHH:MM:SS.mmmZ`.
  final String createdAt;

  /// Texte JSON tel que stocké par le serveur.
  final String payload;
  final String? signature;
  final String hash;
}
