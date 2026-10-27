import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api/models.dart';
import '../../services.dart';
import '../../sms/operator_sms.dart';
import '../../util/format.dart';
import '../common.dart';
import '../receipts/receipt_screen.dart';
import 'declare_screen.dart';
import '../../l10n/l10n.dart';

/// Un tour : qui reçoit, qui a payé, et ce que j'ai à faire (payer, confirmer, témoigner).
class CycleScreen extends StatefulWidget {
  const CycleScreen({super.key, required this.group, required this.cycleNumber});

  final Group group;
  final int cycleNumber;

  @override
  State<CycleScreen> createState() => _CycleScreenState();
}

class _CycleScreenState extends State<CycleScreen> {
  int _version = 0;

  Group get g => widget.group;

  Member? _member(String membershipId) {
    for (final m in g.members) {
      if (m.membershipId == membershipId) return m;
    }
    return null;
  }

  void _reload() => setState(() => _version++);

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));
    _reload();
  }

  Future<void> _decide(Contribution c, String decision) async {
    String? note;
    if (decision == 'dispute') {
      note = await _askReason();
      if (note == null) return;
    }
    if (!mounted) return;
    final result = await Services.of(context).api.decide(c.id, decision, note: note);
    if (!mounted) return;
    showInfo(context, switch (result.status) {
      'confirmed' =>
        result.cycleStatus == 'completed'
            ? t('Cotisation confirmée. Tous ont payé : le tour est terminé.')
            : t('Cotisation confirmée.'),
      'disputed' => t('Contestation enregistrée. Le groupe la voit.'),
      _ => t('Réponse enregistrée. En attente des autres confirmations.'),
    });
    _reload();
  }

  Future<String?> _askReason() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t('Contester')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 500,
          decoration: InputDecoration(hintText: t("Ex. : je n'ai rien reçu, montant différent…")),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(t('Annuler'))),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) Navigator.pop(context, controller.text.trim());
            },
            child: Text(t('Contester')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Tour {n}', {'n': widget.cycleNumber}))),
      body: Loader<CycleDetail>(
        key: ValueKey(_version),
        load: () => Services.of(context).api.cycle(g.id, widget.cycleNumber),
        builder: (context, cycle, reload) {
          final beneficiary = _member(cycle.beneficiaryMembershipId);
          final myRow = cycle.myRow;
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          cycle.iAmBeneficiary ? t('Vous recevez ce tour') : t('Bénéficiaire : {name}', {'name': beneficiary?.fullName}),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        InfoRow(t('Échéance'), formatDate(cycle.dueDate), icon: Icons.event),
                        InfoRow(t('Statut'), cycleStatusLabels[cycle.status] ?? cycle.status, icon: Icons.flag_outlined),
                        InfoRow(
                          t('Chaque membre verse'),
                          formatAmount(g.contributionAmountMinor, g.currency),
                          icon: Icons.payments_outlined,
                        ),
                      ],
                    ),
                  ),
                ),
                if (myRow != null && beneficiary != null) _myPart(context, cycle, myRow, beneficiary),
                const SizedBox(height: 16),
                Text(t('Paiements'), style: Theme.of(context).textTheme.titleMedium),
                for (final p in cycle.payers) _payerTile(context, cycle, p),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _myPart(BuildContext context, CycleDetail cycle, PayerRow me, Member beneficiary) {
    final closed = cycle.status == 'completed' || cycle.status == 'cancelled';
    return Card(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: switch (me.status) {
            'expected' || 'late' when !closed => [
              Text(
                t('Payez {amount} à {name}', {'amount': formatAmount(g.contributionAmountMinor, g.currency), 'name': beneficiary.fullName}),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(t('Numéro : {phone}', {'phone': beneficiary.phone})),
              if (me.status == 'late') Text(t('⚠ Échéance dépassée')),
              const SizedBox(height: 12),
              BusyButton(
                label: t("J'ai payé"),
                icon: Icons.check,
                onPressed: () =>
                    _push(DeclareScreen(group: g, cycleNumber: cycle.cycleNumber, beneficiary: beneficiary)),
              ),
            ],
            'declared' => [Text(t('Votre paiement est déclaré. En attente de confirmation.'))],
            'disputed' => [Text(t('Votre paiement est contesté. Parlez-en avec le bénéficiaire.'))],
            'confirmed' => [
              Text(t('Votre paiement est confirmé.')),
              const SizedBox(height: 8),
              BusyButton(
                label: t('Voir mon reçu'),
                icon: Icons.receipt_long,
                outlined: true,
                onPressed: () => _push(ReceiptScreen(contributionId: me.contribution!.id)),
              ),
            ],
            _ => [Text(t('Ce tour est clos.'))],
          },
        ),
      ),
    );
  }

  Widget _payerTile(BuildContext context, CycleDetail cycle, PayerRow p) {
    final style = contributionStatusStyles[p.status]!;
    final c = p.contribution;
    final me = cycle.myMembershipId;
    final open = p.status == 'declared' || p.status == 'disputed';
    final canConfirm = cycle.iAmBeneficiary && open && c != null && !p.hasDecision(me, 'confirm');
    final canWitness =
        c != null && c.method == 'cash' && c.witnessMembershipId == me && open && !p.hasDecision(me, 'witness');
    final canDispute = (cycle.iAmBeneficiary || c?.witnessMembershipId == me) && p.status == 'declared';

    final details = <String>[
      if (c != null) methodLabels[c.method] ?? c.method,
      if (c?.txReference != null) 'ID ${c!.txReference}',
      if (c?.witnessMembershipId != null)
        t('témoin : {name}', {'name': _member(c!.witnessMembershipId!)?.fullName ?? '?'}),
      if (c?.isLate == true) t('en retard'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            ListTile(
              leading: Icon(style.icon, color: style.color, size: 32),
              title: Text(p.membershipId == me ? t('{name} (vous)', {'name': p.fullName}) : p.fullName),
              subtitle: Text([style.label, ...details].join(' · ')),
              trailing: p.status == 'confirmed'
                  ? IconButton(
                      tooltip: t('Reçu'),
                      icon: const Icon(Icons.receipt_long),
                      onPressed: () => _push(ReceiptScreen(contributionId: c!.id)),
                    )
                  : null,
            ),
            if (canConfirm || canWitness || canDispute)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (canConfirm)
                      FilledButton.icon(
                        icon: const Icon(Icons.check),
                        label: Text(t("J'ai reçu")),
                        onPressed: () => _guard(() => _decide(c, 'confirm')),
                      ),
                    if (canConfirm && c.txReference != null)
                      OutlinedButton.icon(
                        key: const Key('check_sms'),
                        icon: const Icon(Icons.content_paste_search),
                        label: Text(t('Vérifier avec mon SMS')),
                        onPressed: () => _checkWithSms(c),
                      ),
                    if (canWitness)
                      FilledButton.icon(
                        icon: const Icon(Icons.visibility),
                        label: Text(t("J'ai vu la remise")),
                        onPressed: () => _guard(() => _decide(c, 'witness')),
                      ),
                    if (canDispute)
                      OutlinedButton.icon(
                        icon: const Icon(Icons.report_outlined),
                        label: Text(t('Contester')),
                        onPressed: () => _guard(() => _decide(c!, 'dispute')),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Le bénéficiaire colle le SMS de l'argent reçu : l'app compare l'ID et le montant avec la
  /// déclaration. Une aide avant de confirmer, pas une confirmation automatique.
  Future<void> _checkWithSms(Contribution c) async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    final sms = parseOperatorSms(text);
    if (!mounted) return;
    final group = widget.group;
    final idOk = sms?.txId != null && sms!.txId == c.txReference?.toUpperCase();
    final amountOk = sms?.amountMinor == c.amountMinor && sms?.currency == group.currency;
    final (icon, color, message) = sms?.txId == null
        ? (Icons.help_outline, Colors.blueGrey,
            t("Aucun ID trouvé. Copiez d'abord le SMS de l'argent reçu, puis touchez à nouveau ce bouton."))
        : idOk && amountOk
        ? (Icons.check_circle, Colors.green,
            t("L'ID et le montant du SMS correspondent à la déclaration. Vous pouvez confirmer si vous avez bien reçu l'argent."))
        : idOk
        ? (Icons.warning_amber_rounded, Colors.orange,
            t("L'ID correspond, mais pas le montant : vérifiez avant de confirmer."))
        : (Icons.error_outline, Colors.red,
            t("L'ID du SMS ({sms}) ne correspond pas à celui déclaré ({declared}). Ne confirmez pas sans vérifier.", {
              'sms': sms!.txId,
              'declared': c.txReference,
            }));
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(icon, color: color, size: 40),
        title: Text(t('Vérification avec votre SMS')),
        content: Text(message),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: Text(t('OK')))],
      ),
    );
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }
}
