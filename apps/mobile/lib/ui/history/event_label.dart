import 'dart:convert';

import '../../l10n/l10n.dart';
import '../../util/format.dart';

/// Phrase lisible pour un événement du journal. [actor] : nom de l'auteur, ou « Mchango ».
String describeEvent(String action, String payloadJson, String actor) {
  final p = _decode(payloadJson);
  String? s(String key) => p[key]?.toString();
  final a = {'actor': actor};

  switch (action) {
    case 'groups.insert':
      return t('{actor} a créé la tontine « {name} »', {...a, 'name': s('name')});
    case 'groups.update':
      return switch (s('status')) {
        'active' => t('{actor} a démarré la tontine', a),
        'closed' => t('La tontine est terminée : tous les tours sont payés'),
        _ => t('{actor} a modifié la tontine', a),
      };
    case 'memberships.insert':
      return s('role') == 'president' ? t('{actor} est président(e)', a) : t('{actor} a rejoint la tontine', a);
    case 'memberships.update':
      return s('turn_order') == null
          ? t('Ordre des tours effacé')
          : t('Un membre reçoit au tour {n}', {'n': s('turn_order')});
    case 'group.invitation_created':
      return t("{actor} a créé un code d'invitation", a);
    case 'group.turn_order_set':
      return s('mode') == 'draw'
          ? t('{actor} a lancé le tirage au sort (graine {seed}…)', {...a, 'seed': s('seed')?.substring(0, 12)})
          : t("{actor} a fixé l'ordre des tours", a);
    case 'cycles.insert':
      return t('Tour {n} prévu le {date}', {'n': s('cycle_number'), 'date': formatDate(s('due_date') ?? '----')});
    case 'cycles.update':
      return t('Tour {n} : {status}', {'n': s('cycle_number'), 'status': cycleStatusLabels[s('status')] ?? s('status')});
    case 'contributions.insert':
      final method = methodLabels[s('method')] ?? s('method');
      return s('tx_reference') != null
          ? t('{actor} a déclaré un paiement de {amount} ({method}, ID {tx})', {
              ...a,
              'amount': _amount(p),
              'method': method,
              'tx': s('tx_reference'),
            })
          : t('{actor} a déclaré un paiement de {amount} ({method})', {...a, 'amount': _amount(p), 'method': method});
    case 'contributions.update':
      return switch (s('status')) {
        'confirmed' => t('Paiement confirmé (reçu {number})', {
          'number': 'MCH-${(s('receipt_number') ?? '').padLeft(8, '0')}',
        }),
        'disputed' => t('Paiement contesté'),
        'rejected' => t('Paiement rejeté'),
        _ => t('Paiement mis à jour'),
      };
    case 'confirmations.insert':
      return switch (s('decision')) {
        'confirm' => t('{actor} a confirmé avoir reçu le paiement', a),
        'witness' => t('{actor} a témoigné de la remise en espèces', a),
        'dispute' => t('{actor} a contesté : « {note} »', {...a, 'note': s('note')}),
        _ => t('{actor} a répondu à une déclaration', a),
      };
    case 'disputes.insert':
      return t('Litige ouvert');
    case 'disputes.update':
      return t('Litige clos');
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
