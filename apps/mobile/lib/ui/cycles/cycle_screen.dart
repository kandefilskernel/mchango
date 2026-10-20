import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../services.dart';
import '../../util/format.dart';
import '../common.dart';
import '../receipts/receipt_screen.dart';
import 'declare_screen.dart';

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
      'confirmed' => result.cycleStatus == 'completed'
          ? 'Cotisation confirmée. Tous ont payé : le tour est terminé.'
          : 'Cotisation confirmée.',
      'disputed' => 'Contestation enregistrée. Le groupe la voit.',
      _ => 'Réponse enregistrée. En attente des autres confirmations.',
    });
    _reload();
  }

  Future<String?> _askReason() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Contester'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 500,
          decoration: const InputDecoration(hintText: "Ex. : je n'ai rien reçu, montant différent…"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) Navigator.pop(context, controller.text.trim());
            },
            child: const Text('Contester'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Tour ${widget.cycleNumber}')),
      body: Loader<CycleDetail>(
        key: ValueKey(_version),
        load: () => Services.of(context).api.cycle(g.id, widget.cycleNumber),
        builder: (context, cycle, reload) {
          final beneficiary = _member(cycle.beneficiaryMembershipId);
          final myRow = cycle.myRow;
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(cycle.iAmBeneficiary ? 'Vous recevez ce tour' : 'Bénéficiaire : ${beneficiary?.fullName}',
                        style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    InfoRow('Échéance', formatDate(cycle.dueDate), icon: Icons.event),
                    InfoRow('Statut', cycleStatusLabels[cycle.status] ?? cycle.status, icon: Icons.flag_outlined),
                    InfoRow('Chaque membre verse', formatAmount(g.contributionAmountMinor, g.currency),
                        icon: Icons.payments_outlined),
                  ]),
                ),
              ),
              if (myRow != null && beneficiary != null) _myPart(context, cycle, myRow, beneficiary),
              const SizedBox(height: 16),
              Text('Paiements', style: Theme.of(context).textTheme.titleMedium),
              for (final p in cycle.payers) _payerTile(context, cycle, p),
            ]),
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
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: switch (me.status) {
          'expected' || 'late' when !closed => [
              Text('Payez ${formatAmount(g.contributionAmountMinor, g.currency)} à ${beneficiary.fullName}',
                  style: Theme.of(context).textTheme.titleMedium),
              Text('Numéro : ${beneficiary.phone}'),
              if (me.status == 'late') const Text('⚠ Échéance dépassée'),
              const SizedBox(height: 12),
              BusyButton(
                label: "J'ai payé",
                icon: Icons.check,
                onPressed: () => _push(DeclareScreen(group: g, cycleNumber: cycle.cycleNumber, beneficiary: beneficiary)),
              ),
            ],
          'declared' => [const Text('Votre paiement est déclaré. En attente de confirmation.')],
          'disputed' => [const Text('Votre paiement est contesté. Parlez-en avec le bénéficiaire.')],
          'confirmed' => [
              const Text('Votre paiement est confirmé.'),
              const SizedBox(height: 8),
              BusyButton(
                label: 'Voir mon reçu',
                icon: Icons.receipt_long,
                outlined: true,
                onPressed: () => _push(ReceiptScreen(contributionId: me.contribution!.id)),
              ),
            ],
          _ => [const Text('Ce tour est clos.')],
        }),
      ),
    );
  }

  Widget _payerTile(BuildContext context, CycleDetail cycle, PayerRow p) {
    final style = contributionStatusStyles[p.status]!;
    final c = p.contribution;
    final me = cycle.myMembershipId;
    final open = p.status == 'declared' || p.status == 'disputed';
    final canConfirm = cycle.iAmBeneficiary && open && c != null && !p.hasDecision(me, 'confirm');
    final canWitness = c != null &&
        c.method == 'cash' &&
        c.witnessMembershipId == me &&
        open &&
        !p.hasDecision(me, 'witness');
    final canDispute = (cycle.iAmBeneficiary || c?.witnessMembershipId == me) && p.status == 'declared';

    final details = <String>[
      if (c != null) methodLabels[c.method] ?? c.method,
      if (c?.txReference != null) 'ID ${c!.txReference}',
      if (c?.witnessMembershipId != null) 'témoin : ${_member(c!.witnessMembershipId!)?.fullName ?? '?'}',
      if (c?.isLate == true) 'en retard',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(children: [
          ListTile(
            leading: Icon(style.icon, color: style.color, size: 32),
            title: Text(p.membershipId == me ? '${p.fullName} (vous)' : p.fullName),
            subtitle: Text([style.label, ...details].join(' · ')),
            trailing: p.status == 'confirmed'
                ? IconButton(
                    tooltip: 'Reçu',
                    icon: const Icon(Icons.receipt_long),
                    onPressed: () => _push(ReceiptScreen(contributionId: c!.id)),
                  )
                : null,
          ),
          if (canConfirm || canWitness || canDispute)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                if (canConfirm)
                  FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text("J'ai reçu"),
                    onPressed: () => _guard(() => _decide(c, 'confirm')),
                  ),
                if (canWitness)
                  FilledButton.icon(
                    icon: const Icon(Icons.visibility),
                    label: const Text("J'ai vu la remise"),
                    onPressed: () => _guard(() => _decide(c, 'witness')),
                  ),
                if (canDispute)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.report_outlined),
                    label: const Text('Contester'),
                    onPressed: () => _guard(() => _decide(c!, 'dispute')),
                  ),
              ]),
            ),
        ]),
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
