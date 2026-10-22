import 'package:flutter/material.dart';
import 'package:mchango_audit/mchango_audit.dart';

import '../../api/models.dart';
import '../../services.dart';
import '../../storage/key_value_store.dart';
import '../../util/format.dart';
import '../common.dart';
import 'event_label.dart';
import '../../l10n/l10n.dart';

/// Résultat de la vérification du journal sur le téléphone.
class HistoryCheck {
  HistoryCheck(this.events, this.verification, this.rewritten);

  final List<HistoryEvent> events;
  final ChainVerification verification;

  /// Le serveur présente pour un événement déjà vérifié un autre contenu qu'avant.
  final bool rewritten;

  bool get trusted => verification.isValid && !rewritten;
}

/// Vérifie la chaîne et la compare au dernier point mémorisé sur ce téléphone.
/// Si tout est intact, mémorise la nouvelle tête.
Future<HistoryCheck> checkHistory(KeyValueStore store, String groupId, List<HistoryEvent> events) async {
  final chainId = 'group:$groupId';
  final verification = verifyChain(chainId, [for (final e in events) e.audit]);

  final key = 'chain_head:$groupId';
  final known = (await store.read(key))?.split(':');
  var rewritten = false;
  if (known != null && known.length == 2) {
    final head = ChainHead(seq: int.parse(known[0]), hash: known[1]);
    final same = events.where((e) => e.audit.seq == head.seq);
    // Événement disparu, ou contenu différent : réécriture
    rewritten = same.isEmpty || isRewrite(head, same.first.audit);
  }
  if (verification.isValid && !rewritten && events.isNotEmpty) {
    await store.write(key, '${verification.head.seq}:${verification.head.hash}');
  }
  return HistoryCheck(events, verification, rewritten);
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key, required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(t('Historique'))),
      body: Loader<HistoryCheck>(
        load: () async => checkHistory(services.store, groupId, await services.api.history(groupId)),
        builder: (context, check, reload) => RefreshIndicator(
          onRefresh: reload,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _Banner(check: check),
              const SizedBox(height: 12),
              for (final e in check.events.reversed)
                ListTile(
                  dense: true,
                  leading: CircleAvatar(
                    radius: 16,
                    child: Text('${e.audit.seq}', style: const TextStyle(fontSize: 12)),
                  ),
                  title: Text(describeEvent(e.audit.action, e.audit.payload, e.actorName ?? 'Mchango')),
                  subtitle: Text(
                    '${formatDateTime(DateTime.parse(e.audit.createdAt))} · ${e.audit.hash.substring(0, 12)}…',
                  ),
                  tileColor: check.verification.firstInvalidSeq == e.audit.seq
                      ? Colors.red.withValues(alpha: 0.1)
                      : null,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.check});

  final HistoryCheck check;

  @override
  Widget build(BuildContext context) {
    final ok = check.trusted;
    final message = ok
        ? t("Journal vérifié sur ce téléphone : {n} événements, aucun n'a été modifié ni supprimé.", {'n': check.events.length})
        : check.rewritten
        ? t("Alerte : l'historique a changé depuis votre dernière vérification. Prévenez le groupe et Mchango.")
        : t("Alerte : le journal est incohérent à partir de l'événement n°{n}. Prévenez le groupe et Mchango.", {
            'n': check.verification.firstInvalidSeq,
          });
    return Card(
      color: ok ? Colors.green.shade50 : Colors.red.shade50,
      child: ListTile(
        leading: Icon(ok ? Icons.verified_user : Icons.gpp_bad, color: ok ? Colors.green : Colors.red, size: 36),
        title: Text(
          ok ? t('Intact') : t('Problème détecté'),
          style: TextStyle(fontWeight: FontWeight.bold, color: ok ? Colors.green.shade900 : Colors.red.shade900),
        ),
        subtitle: Text(message),
      ),
    );
  }
}
