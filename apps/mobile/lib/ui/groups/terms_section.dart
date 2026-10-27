import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/l10n.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import '../theme.dart';

/// « Règlement à signer » : ce qui engage chaque membre, qui a signé, et le bouton pour signer.
/// Tant que tout le monde n'a pas signé ce règlement-là, la tontine ne peut pas démarrer.
class TermsSection extends StatelessWidget {
  const TermsSection({super.key, required this.group, required this.onSigned});

  final Group group;
  final Future<void> Function() onSigned;

  @override
  Widget build(BuildContext context) {
    final g = group;
    final terms = g.terms;
    if (terms == null) return const SizedBox.shrink();
    final myUserId = Services.of(context).auth.userId;
    final me = g.members.where((m) => m.userId == myUserId).firstOrNull;
    final iSigned = me != null && terms.signedBy.contains(me.membershipId);
    final text = Theme.of(context).textTheme;

    return Card(
      key: const Key('terms_section'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.draw_outlined, color: Brand.green),
                const SizedBox(width: 8),
                Expanded(child: Text(t('Règlement à signer'), style: text.titleMedium)),
                if (terms.ready)
                  Text(
                    '${terms.signedBy.length}/${g.members.length}',
                    style: text.titleMedium?.copyWith(color: terms.allSigned ? Brand.green : Brand.goldDark),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (!terms.ready)
              Text(t("Le règlement sera à signer quand le président aura fixé l'ordre des tours."))
            else ...[
              Text(
                t(
                  'Chaque membre signe ce règlement avant le démarrage. Si le président change le montant, la date ou l\'ordre des tours, il faut signer à nouveau.',
                ),
                style: text.bodySmall,
              ),
              const SizedBox(height: 8),
              for (final m in [...g.members]..sort((a, b) => (a.turnOrder ?? 99).compareTo(b.turnOrder ?? 99)))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(
                        terms.signedBy.contains(m.membershipId) ? Icons.check_circle : Icons.hourglass_empty,
                        size: 20,
                        color: terms.signedBy.contains(m.membershipId) ? Colors.green : Colors.blueGrey,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(t('Tour {n} : {name}', {'n': m.turnOrder, 'name': m.fullName}))),
                      Text(
                        terms.signedBy.contains(m.membershipId) ? t('a signé') : t('en attente'),
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              if (me != null && !iSigned)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const Key('sign_terms'),
                    icon: const Icon(Icons.draw),
                    label: Text(t('Lire et signer le règlement')),
                    onPressed: () async {
                      if (await showSignDialog(context, g, me) == true) await onSigned();
                    },
                  ),
                )
              else if (iSigned)
                Row(
                  children: [
                    const Icon(Icons.verified, color: Brand.green, size: 20),
                    const SizedBox(width: 6),
                    Expanded(child: Text(t('Vous avez signé ce règlement.'))),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Le règlement en clair, puis la confirmation par PIN (ou empreinte). Renvoie true si signé.
Future<bool?> showSignDialog(BuildContext context, Group g, Member me) =>
    showDialog<bool>(context: context, builder: (_) => _SignDialog(group: g, me: me));

class _SignDialog extends StatefulWidget {
  const _SignDialog({required this.group, required this.me});

  final Group group;
  final Member me;

  @override
  State<_SignDialog> createState() => _SignDialogState();
}

class _SignDialogState extends State<_SignDialog> {
  final _pin = TextEditingController();
  bool _biometric = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final auth = Services.of(context).auth;
      final ok = await auth.biometricEnabled() && await auth.biometricAvailable();
      if (mounted) setState(() => _biometric = ok);
    });
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _sign({required bool withBiometric}) async {
    final services = Services.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final confirmed = withBiometric
          ? await services.auth.confirmWithBiometric(t('Signer le règlement de la tontine'))
          : await services.auth.confirmWithPin(_pin.text);
      if (!confirmed) {
        _pin.clear();
        setState(() => _error = withBiometric ? t('Empreinte non reconnue.') : t('PIN incorrect.'));
        return;
      }
      await services.api.signTerms(widget.group.id, widget.group.terms!.hash);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.group;
    final beneficiaryCount = g.members.length - 1;
    return AlertDialog(
      icon: const Icon(Icons.draw, size: 36),
      title: Text(t('Règlement de « {name} »', {'name': g.name})),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InfoRow(t('Cotisation par tour'), formatAmount(g.contributionAmountMinor, g.currency)),
            InfoRow(t('Fréquence'), frequencyLabels[g.frequency] ?? g.frequency),
            InfoRow(t('Premier tour'), formatDate(g.startDate)),
            InfoRow(t('Votre tour'), '${widget.me.turnOrder}'),
            InfoRow(
              t('Vous recevrez'),
              formatAmount(g.contributionAmountMinor * beneficiaryCount, g.currency),
            ),
            const SizedBox(height: 10),
            Text(
              t(
                "Je m'engage à payer ma cotisation à chaque tour, directement au bénéficiaire, et à la déclarer dans Mchango. {notice}",
                {'notice': noCustodyNotice},
              ),
            ),
            const SizedBox(height: 12),
            PinField(key: const Key('sign_pin'), controller: _pin, label: t('Votre PIN pour signer')),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context, false), child: Text(t('Annuler'))),
        if (_biometric)
          IconButton(
            tooltip: t('Utiliser mon empreinte'),
            onPressed: _busy ? null : () => _sign(withBiometric: true),
            icon: const Icon(Icons.fingerprint),
          ),
        FilledButton(
          key: const Key('confirm_sign'),
          onPressed: _busy ? null : () => _sign(withBiometric: false),
          child: Text(t('Je signe')),
        ),
      ],
    );
  }
}
