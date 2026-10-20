import 'dart:convert';

import '../../util/format.dart';

/// Phrase lisible pour un événement du journal. [actor] : nom de l'auteur, ou « Mchango ».
String describeEvent(String action, String payloadJson, String actor) {
  final p = _decode(payloadJson);
  String? s(String key) => p[key]?.toString();

  switch (action) {
    case 'groups.insert':
      return '$actor a créé la tontine « ${s('name')} »';
    case 'groups.update':
      return switch (s('status')) {
        'active' => '$actor a démarré la tontine',
        'closed' => 'La tontine est terminée : tous les tours sont payés',
        _ => '$actor a modifié la tontine',
      };
    case 'memberships.insert':
      return s('role') == 'president' ? '$actor est président(e)' : '$actor a rejoint la tontine';
    case 'memberships.update':
      return s('turn_order') == null ? 'Ordre des tours effacé' : 'Un membre reçoit au tour ${s('turn_order')}';
    case 'group.invitation_created':
      return "$actor a créé un code d'invitation";
    case 'group.turn_order_set':
      return s('mode') == 'draw'
          ? '$actor a lancé le tirage au sort (graine ${s('seed')?.substring(0, 12)}…)'
          : "$actor a fixé l'ordre des tours";
    case 'cycles.insert':
      return 'Tour ${s('cycle_number')} prévu le ${formatDate(s('due_date') ?? '----')}';
    case 'cycles.update':
      return 'Tour ${s('cycle_number')} : ${cycleStatusLabels[s('status')] ?? s('status')}';
    case 'contributions.insert':
      return '$actor a déclaré un paiement de ${_amount(p)} (${methodLabels[s('method')] ?? s('method')}'
          '${s('tx_reference') != null ? ', ID ${s('tx_reference')}' : ''})';
    case 'contributions.update':
      return switch (s('status')) {
        'confirmed' => 'Paiement confirmé (reçu MCH-${(s('receipt_number') ?? '').padLeft(8, '0')})',
        'disputed' => 'Paiement contesté',
        'rejected' => 'Paiement rejeté',
        _ => 'Paiement mis à jour',
      };
    case 'confirmations.insert':
      return switch (s('decision')) {
        'confirm' => '$actor a confirmé avoir reçu le paiement',
        'witness' => '$actor a témoigné de la remise en espèces',
        'dispute' => '$actor a contesté : « ${s('note')} »',
        _ => '$actor a répondu à une déclaration',
      };
    case 'disputes.insert':
      return 'Litige ouvert';
    case 'disputes.update':
      return 'Litige clos';
    default:
      return '$actor : $action';
  }
}

String _amount(Map<String, dynamic> p) {
  final minor = int.tryParse(p['amount_minor']?.toString() ?? '');
  // La devise n'est pas dans la ligne de cotisation : on affiche le montant brut
  return minor == null ? '?' : '$minor';
}

Map<String, dynamic> _decode(String json) {
  try {
    final v = jsonDecode(json);
    return v is Map<String, dynamic> ? v : const {};
  } catch (_) {
    return const {};
  }
}
