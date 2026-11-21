import 'package:flutter/material.dart';
import 'package:mchango_audit/mchango_audit.dart';

import '../../api/models.dart';
import '../../services.dart';
import '../../storage/key_value_store.dart';
import '../../util/format.dart';
import '../common.dart';
import '../theme.dart';
import 'event_label.dart';
import '../../l10n/l10n.dart';

/// Résultat de la vérification du journal sur le téléphone.
class HistoryCheck {
  HistoryCheck(this.events, this.verification, this.rewritten, [this.private = const []]);

  /// Travailleurs : chaînes privées des cotisations visibles de ce membre, vérifiées une à une.
  final List<PrivateCheck> private;

  final List<HistoryEvent> events;
  final ChainVerification verification;

  /// Le serveur présente pour un événement déjà vérifié un autre contenu qu'avant.
  final bool rewritten;

  bool get trusted => verification.isValid && !rewritten && private.every((p) => p.check.trusted);
}

/// Une chaîne privée de cotisation et sa vérification.
class PrivateCheck {
  PrivateCheck(this.chain, this.check);
  final PrivateChain chain;
  final HistoryCheck check;
}

/// Vérifie la chaîne et la compare au dernier point mémorisé sur ce téléphone.
/// Si tout est intact, mémorise la nouvelle tête.
Future<HistoryCheck> checkHistory(KeyValueStore store, String groupId, List<HistoryEvent> events) =>
    checkChain(store, 'group:$groupId', 'chain_head:$groupId', events);

/// Vérifie une chaîne quelconque (groupe ou chaîne privée) et la compare au dernier point mémorisé.
Future<HistoryCheck> checkChain(KeyValueStore store, String chainId, String key, List<HistoryEvent> events) async {
  final verification = verifyChain(chainId, [for (final e in events) e.audit]);

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
        load: () async {
          final main = await checkHistory(services.store, groupId, await services.api.history(groupId));
          // Ancienne API sans chaînes privées : on garde la vérification du groupe seule
          final chains = await services.api.privateHistory(groupId).catchError((_) => <PrivateChain>[]);
          final private = [
            for (final c in chains)
              PrivateCheck(c, await checkChain(services.store, c.chainId, 'chain_head:${c.chainId}', c.events)),
          ];
          return HistoryCheck(main.events, main.verification, main.rewritten, private);
        },
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
                      ? Brand.dangerBg
                      : null,
                ),
              if (check.private.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(t('Paiements confidentiels'), style: Theme.of(context).textTheme.titleMedium),
                Text(
                  t('Tontine de travailleurs : chaque paiement a son propre journal, visible seulement du payeur, du bénéficiaire, du témoin et du président.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                for (final p in check.private)
                  Card(
                    key: Key('private_${p.chain.chainId}'),
                    color: p.check.trusted ? null : Brand.dangerBg,
                    child: ExpansionTile(
                      leading: Icon(
                        p.check.trusted ? Icons.verified_user : Icons.gpp_bad,
                        color: p.check.trusted ? Brand.success : Brand.danger,
                      ),
                      title: Text(t('Tour {n} · {name}', {'n': p.chain.cycleNumber, 'name': p.chain.payerName})),
                      subtitle: Text(
                        p.check.trusted
                            ? t('{n} événement(s) vérifié(s)', {'n': p.chain.events.length})
                            : t('Journal incohérent : prévenez le groupe et Mchango.'),
                      ),
                      children: [
                        for (final e in p.chain.events.reversed)
                          ListTile(
                            dense: true,
                            title: Text(describeEvent(e.audit.action, e.audit.payload, e.actorName ?? 'Mchango')),
                            subtitle: Text(
                              '${formatDateTime(DateTime.parse(e.audit.createdAt))} · ${e.audit.hash.substring(0, 12)}…',
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
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
      color: ok ? Brand.successBg : Brand.dangerBg,
      child: ListTile(
        leading: Icon(ok ? Icons.verified_user : Icons.gpp_bad, color: ok ? Brand.success : Brand.danger, size: 36),
        title: Text(
          ok ? t('Intact') : t('Problème détecté'),
          style: TextStyle(fontWeight: FontWeight.bold, color: ok ? Brand.success : Brand.danger),
        ),
        subtitle: Text(message),
      ),
    );
  }
}
